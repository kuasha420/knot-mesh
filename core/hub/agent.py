#!/usr/bin/env python3
"""
Knot Swarm Worker Agent Daemon (knot-agent)
Runs as a systemd user daemon on mesh nodes (Strands and Anchor).
Discovers local hardware capabilities, reports heartbeats, claims eligible tasks
from the Knot Hub blackboard, executes them autonomously via `agy`, and reports telemetry.
Zero external dependencies (uses standard library Python 3).
"""

import glob
import hashlib
import json
import os
import re
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

DEFAULT_HUB_PORT = 4242
DEFAULT_POLL_INTERVAL = 3.0  # seconds between claim polls when idle


def is_on_ac_power() -> bool:
    """
    Detects whether the machine is running on AC / mains power.
    Desktops without internal batteries default to True.
    Laptops and handhelds (Steam Deck) inspect /sys/class/power_supply.
    """
    ps_dir = "/sys/class/power_supply"
    if not os.path.exists(ps_dir):
        return True
    supplies = os.listdir(ps_dir)
    has_system_battery = False
    for s in supplies:
        scope_file = os.path.join(ps_dir, s, "scope")
        scope = open(scope_file).read().strip() if os.path.exists(scope_file) else ""
        if scope == "Device":
            continue
        type_file = os.path.join(ps_dir, s, "type")
        st_type = open(type_file).read().strip().lower() if os.path.exists(type_file) else ""
        if st_type == "battery" or s.upper().startswith("BAT"):
            has_system_battery = True
            break
    if not has_system_battery:
        return True

    for s in supplies:
        online_file = os.path.join(ps_dir, s, "online")
        if os.path.exists(online_file):
            try:
                if open(online_file).read().strip() == "1":
                    return True
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
        type_file = os.path.join(ps_dir, s, "type")
        if os.path.exists(type_file):
            try:
                st_type = open(type_file).read().strip().lower()
                if st_type in ("mains", "usb"):
                    if os.path.exists(online_file) and open(online_file).read().strip() == "1":
                        return True
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return False


def get_battery_capacity() -> int | None:
    """
    Returns current battery capacity percentage (0-100) if available.
    """
    ps_dir = "/sys/class/power_supply"
    if not os.path.exists(ps_dir):
        return None
    for s in os.listdir(ps_dir):
        if s.upper().startswith("BAT"):
            cap_file = os.path.join(ps_dir, s, "capacity")
            if os.path.exists(cap_file):
                try:
                    with open(cap_file, "r") as f:
                        return int(f.read().strip())
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return None


def detect_node_id() -> str:
    # 1. Explicit environment variable override
    env_id = os.environ.get("KNOT_NODE_ID")
    if env_id:
        return env_id.strip()

    # 2. Local configured node identity file
    user_home = os.environ.get("HOME", os.path.expanduser("~"))
    node_id_file = os.path.join(user_home, ".config/knot/node_id")
    if os.path.exists(node_id_file):
        try:
            with open(node_id_file, "r") as f:
                val = f.read().strip()
                if val:
                    return val
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # 3. Dynamic match against active swarm node definitions
    hostname = socket.gethostname().lower()
    active_id = "home"
    for active_file in ["/run/knot/active_swarm", os.path.join(user_home, ".local/state/knot/active_swarm")]:
        if os.path.exists(active_file):
            try:
                with open(active_file, "r") as f:
                    c = f.read().strip()
                    if c and c != "none":
                        active_id = c
                        break
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_id}/nodes")
    if os.path.isdir(nodes_dir):
        for f in os.listdir(nodes_dir):
            if f.endswith(".json"):
                fpath = os.path.join(nodes_dir, f)
                try:
                    with open(fpath, "r") as jf:
                        m = json.load(jf)
                        nid = m.get("id", f[:-5])
                        m_host = (m.get("hostname") or "").lower()
                        aliases = [a.lower() for a in m.get("aliases", [])]
                        if hostname == nid.lower() or hostname == m_host or hostname in aliases:
                            return nid
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return socket.gethostname()


def detect_capabilities(node_id: str) -> list[str]:
    caps = ["any", "general", node_id]

    # Architecture
    arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()
    if arch:
        caps.append(arch)

    # GPU detection
    try:
        if subprocess.run(["nvidia-smi", "-L"], capture_output=True).returncode == 0:
            caps.extend(["gpu_cuda", "nvidia_gpu", "rtx_3050"])
    except Exception as _err:
        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    try:
        p = subprocess.run(["lspci"], capture_output=True, text=True)
        if "radeon" in p.stdout.lower() or "amd" in p.stdout.lower():
            caps.append("amd_gpu")
    except Exception as _err:
        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # Steam Deck specific checks
    is_deck = False
    dmi_prod = "/sys/devices/virtual/dmi/id/product_name"
    if os.path.exists(dmi_prod):
        try:
            with open(dmi_prod, "r") as f:
                content = f.read().lower()
                if "jupiter" in content or "galileo" in content:
                    is_deck = True
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    if is_deck or node_id == "steamdeck":
        caps.extend(["steamdeck", "embedded_gamepad", "handheld_display", "controller_input"])

    if node_id == "laptop":
        caps.extend(["x86_compute", "portable_testbed"])

    if node_id == "desktop":
        caps.extend(["anchor", "high_memory", "master_planner"])

    return list(dict.fromkeys(caps))


def ensure_headless_shims() -> str:
    """
    Creates dummy executable shims for browser and desktop opener binaries in
    ~/.local/share/knot/shims/ to ensure headless background tasks (systemd services)
    can NEVER trigger GUI browser tabs or desktop dialogs even if agy invokes xdg-open.
    Returns the absolute path to the shims directory.
    """
    shims_dir = os.path.expanduser("~/.local/share/knot/shims")
    os.makedirs(shims_dir, exist_ok=True)
    shim_script = "#!/bin/sh\n# Knot Headless Shim: Exit immediately to prevent GUI spawns\nexit 0\n"
    binaries = [
        "xdg-open", "kde-open", "kde-open5", "kde-open6",
        "kioexec", "kfmclient", "gio", "sensible-browser",
        "x-www-browser", "chromium", "google-chrome-stable",
        "google-chrome", "brave", "firefox"
    ]
    for b in binaries:
        path = os.path.join(shims_dir, b)
        if not os.path.exists(path):
            try:
                with open(path, "w") as f:
                    f.write(shim_script)
                os.chmod(path, 0o755)
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return shims_dir


def is_online(host: str = "oauth2.googleapis.com", port: int = 443, timeout: float = 1.5) -> bool:
    """
    Fast pre-flight network and DNS readiness probe. Prevents agy from attempting
    Google OAuth token refresh when network/DNS is temporarily resolving or offline
    (e.g., immediately after waking from sleep), which would erroneously trigger interactive auth.
    """
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except Exception:
        return False


def get_headless_systemd_env() -> list[str]:
    """
    Returns systemd-run --setenv arguments to enforce completely headless execution.
    """
    shims_dir = ensure_headless_shims()
    return [
        f"--setenv=PATH={shims_dir}:/usr/local/bin:/usr/bin:/bin",
        "--setenv=BROWSER=/bin/true",
        "--setenv=DE=generic",
        "--setenv=XDG_CURRENT_DESKTOP=",
        "--setenv=KDE_FULL_SESSION=",
        "--setenv=KDE_SESSION_VERSION=",
    ]


def is_headless() -> bool:
    """
    Checks if current execution is in a non-interactive headless context.
    """
    if not sys.stdin.isatty():
        return True
    if os.environ.get("JOURNAL_STREAM") or os.environ.get("INVOCATION_ID"):
        return True
    if os.environ.get("DE") == "generic" or not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY"):
        return True
    return False


def is_kwallet_unlocked() -> bool:
    """
    Checks if KWallet or the desktop Secret Service keyring is unlocked.
    Returns True if unlocked, or if KWallet is not enabled/installed.
    Returns False if KWallet/Secret Service is present and confirmed locked.
    """
    # 1. Check KDE KWallet DBus interface (Plasma 6 kwalletd6 and Plasma 5 kwalletd5)
    for service, path in [("org.kde.kwalletd6", "/modules/kwalletd6"), ("org.kde.kwalletd5", "/modules/kwalletd5")]:
        try:
            p_enabled = subprocess.run(
                ["busctl", "--user", "call", service, path, "org.kde.KWallet", "isEnabled"],
                capture_output=True, text=True, timeout=1.5
            )
            if p_enabled.returncode == 0 and "true" in p_enabled.stdout:
                wallet = "kdewallet"
                p_wallet = subprocess.run(
                    ["busctl", "--user", "call", service, path, "org.kde.KWallet", "localWallet"],
                    capture_output=True, text=True, timeout=1.5
                )
                if p_wallet.returncode == 0:
                    m = re.search(r"\"([^\"]+)\"", p_wallet.stdout)
                    if m:
                        wallet = m.group(1)
                p_open = subprocess.run(
                    ["busctl", "--user", "call", service, path, "org.kde.KWallet", "isOpen", "s", wallet],
                    capture_output=True, text=True, timeout=1.5
                )
                if p_open.returncode == 0:
                    if "false" in p_open.stdout:
                        return False
                    if "true" in p_open.stdout:
                        return True
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # 2. Check FreeDesktop Secret Service default collection Locked property
    try:
        p_sec = subprocess.run(
            ["busctl", "--user", "get-property", "org.freedesktop.secrets",
             "/org/freedesktop/secrets/aliases/default", "org.freedesktop.Secret.Collection", "Locked"],
            capture_output=True, text=True, timeout=1.5
        )
        if p_sec.returncode == 0:
            if "true" in p_sec.stdout:
                return False
            if "false" in p_sec.stdout:
                return True
    except Exception as _err:
        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # 3. Probe secret-tool search as fallback
    try:
        p_st = subprocess.run(
            ["secret-tool", "search", "service", "gemini"],
            capture_output=True, text=True, timeout=1.5
        )
        if p_st.returncode == 0 and p_st.stdout:
            for line in p_st.stdout.splitlines():
                if line.startswith("secret = "):
                    val = line[len("secret = "):].strip()
                    if not val:
                        return False
                    return True
    except Exception as _err:
        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    return True


_account_info_cache: dict = {}
_account_info_cached_at: float = 0.0
_account_info_token_sig: str = ""


def sync_oauth_token_file() -> dict | None:
    """
    Synchronizes and parses OAuth token from Secret Service / KWallet or local cache.
    Returns the parsed dict if available.
    """
    primary_token = os.path.expanduser("~/.gemini/antigravity-cli/antigravity-oauth-token")

    # Check Secret Service for updated token if wallet is unlocked
    if is_kwallet_unlocked():
        try:
            sp = subprocess.run(["secret-tool", "search", "service", "gemini"], capture_output=True, text=True, timeout=3)
            for line in sp.stdout.splitlines():
                if line.startswith("secret = "):
                    secret_json = line[len("secret = "):].strip()
                    if "refresh_token" in secret_json or "access_token" in secret_json:
                        parsed = json.loads(secret_json)
                        os.makedirs(os.path.dirname(primary_token), exist_ok=True)
                        try:
                            with open(primary_token, "r") as existing_f:
                                existing_content = existing_f.read().strip()
                        except Exception:
                            existing_content = ""
                        if existing_content != secret_json:
                            with open(primary_token, "w") as tf:
                                tf.write(secret_json + "\n")
                            os.chmod(primary_token, 0o600)
                        return parsed
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # Fallback to local token files
    token_candidates = [
        primary_token,
        os.path.expanduser("~/.gemini/jetski-standalone-oauth-token"),
    ]
    for tf in token_candidates:
        if os.path.exists(tf) and os.path.getsize(tf) > 50:
            try:
                with open(tf, "r") as f:
                    return json.load(f)
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return None


def has_oauth_token_file() -> bool:
    """
    Checks if an OAuth token file exists on disk with a valid token payload.
    Allows headless operations on autologin nodes even if KWallet is locked.
    """
    token_candidates = [
        os.path.expanduser("~/.gemini/antigravity-cli/antigravity-oauth-token"),
        os.path.expanduser("~/.gemini/jetski-standalone-oauth-token"),
    ]
    for tf in token_candidates:
        if os.path.exists(tf) and os.path.getsize(tf) > 50:
            try:
                with open(tf, "r") as f:
                    d = json.load(f)
                    tok = d.get("token", {}) if isinstance(d, dict) else {}
                    if tok.get("access_token") or tok.get("refresh_token"):
                        return True
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
    return False


def fetch_account_info() -> dict:
    """
    Fetches Google account identity (email, name, picture) and subscription tier.
    Cached in-memory for 1 hour to prevent API throttling, but automatically invalidates
    immediately when a new account OAuth token is detected. Zero token cost.
    """
    global _account_info_cache, _account_info_cached_at, _account_info_token_sig
    now = time.time()
    tdata = sync_oauth_token_file()
    if not tdata:
        return _account_info_cache or {}

    token_obj = tdata.get("token", {})
    access_token = token_obj.get("access_token")
    refresh_token = token_obj.get("refresh_token", "")
    token_expiry = token_obj.get("expiry", "")
    auth_method = tdata.get("auth_method", "consumer")
    subscription = "Google AI Pro" if auth_method == "consumer" else "Google Workspace"

    token_sig = hashlib.sha256((refresh_token or access_token or "").encode("utf-8")).hexdigest()

    # Return cache if valid (< 1 hr) AND token hasn't changed
    if _account_info_cache and (now - _account_info_cached_at < 3600) and (_account_info_token_sig == token_sig) and _account_info_cache.get("email"):
        _account_info_cache["token_expiry"] = token_expiry
        return _account_info_cache

    result = {
        "email": "",
        "name": "",
        "picture": "",
        "subscription": subscription,
        "token_expiry": token_expiry,
        "auth_method": auth_method
    }

    if not access_token or not is_online():
        if _account_info_cache:
            _account_info_cache["token_expiry"] = token_expiry
            return _account_info_cache
        return result

    try:
        req = urllib.request.Request(
            "https://www.googleapis.com/oauth2/v3/userinfo",
            headers={"Authorization": f"Bearer {access_token}"}
        )
        with urllib.request.urlopen(req, timeout=4.0) as resp:
            uinfo = json.loads(resp.read().decode("utf-8"))
            result["email"] = uinfo.get("email", "")
            result["name"] = uinfo.get("name", "")
            result["picture"] = uinfo.get("picture", "")
            if result["email"]:
                _account_info_cache = result
                _account_info_cached_at = now
                _account_info_token_sig = token_sig
    except Exception:
        if _account_info_cache:
            _account_info_cache["token_expiry"] = token_expiry
            return _account_info_cache

    return result


def find_agy_binary() -> str:
    return (
        shutil.which("agy")
        or shutil.which("antigravity")
        or (os.path.expanduser("~/.local/bin/agy") if os.path.exists(os.path.expanduser("~/.local/bin/agy")) else None)
        or "/usr/bin/agy"
    )


def get_agy_info() -> tuple[str, str]:
    ver = "unknown"
    auth = "unknown"
    agy_bin = find_agy_binary()
    try:
        p = subprocess.run([agy_bin, "--version"], capture_output=True, text=True, timeout=3)
        if p.returncode == 0 and p.stdout.strip():
            ver = p.stdout.strip().split()[-1]
    except Exception:
        ver = "not_found"

    tdata = sync_oauth_token_file()
    has_valid_token = False
    if tdata and (tdata.get("token", {}).get("refresh_token") or tdata.get("token", {}).get("access_token")):
        has_valid_token = True

    if has_valid_token:
        auth = "AUTHENTICATED"
    else:
        if not is_online():
            return ver, "UNAUTHENTICATED"
        # Skip headless probe if KWallet is locked to avoid desktop warnings
        if not is_kwallet_unlocked() and is_headless():
            print("[knot-agent] KWallet is locked on autologin node; skipping headless auth probe")
            return ver, "UNAUTHENTICATED"
        # Fallback to systemd probe with headless browser prevention and 30s timeout
        try:
            cmd = ["systemd-run", "--user", "--pipe"] + get_headless_systemd_env() + [
                agy_bin, "-p", "ping", "--output-format", "json"
            ]
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            if p.returncode == 0 and '"status":"SUCCESS"' in p.stdout.replace(" ", ""):
                auth = "AUTHENTICATED"
            else:
                auth = "UNAUTHENTICATED"
        except Exception:
            auth = "UNAUTHENTICATED"

    return ver, auth


def fetch_model_quota() -> dict | None:
    """
    Queries agy /usage in JSON format to extract 5h and weekly quota fractions.
    Consumes zero tokens. Enforces headless shims and preflight network check.
    """
    if not is_online():
        return None

    if not is_kwallet_unlocked() and not has_oauth_token_file():
        print("[knot-agent] KWallet is locked on autologin node and no token file found; skipping headless quota probe")
        return None

    agy_bin = find_agy_binary()
    cmd = ["systemd-run", "--user", "--pipe"] + get_headless_systemd_env() + [
        agy_bin,
        "-p", "/usage",
        "--output-format", "json"
    ]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        raw_out = p.stdout.strip()
        json_line = None
        for line in reversed(raw_out.splitlines()):
            line = line.strip()
            if line.startswith("{") and ('"command"' in line or '"groups"' in line):
                json_line = line
                break
        if not json_line:
            return None

        data = json.loads(json_line)
        groups = data.get("command", {}).get("data", {}).get("groups", [])

        result = {
            "gemini_5h_fraction": 1.0,
            "gemini_5h_reset": "",
            "gemini_weekly_fraction": 1.0,
            "gemini_weekly_reset": "",
            "third_party_5h_fraction": 1.0,
            "third_party_5h_reset": "",
            "third_party_weekly_fraction": 1.0,
            "third_party_weekly_reset": "",
            "account": fetch_account_info(),
            "fetched_at": int(time.time())
        }

        for group in groups:
            gname = group.get("name", "").lower()
            buckets = group.get("buckets", [])
            for b in buckets:
                window = b.get("window", "")
                frac = float(b.get("remaining_fraction", 1.0))
                reset = b.get("reset_time", "")
                bid = b.get("id", "")

                if "gemini" in gname:
                    if window == "5h" or "5h" in bid:
                        result["gemini_5h_fraction"] = frac
                        result["gemini_5h_reset"] = reset
                    elif window == "weekly" or "weekly" in bid:
                        result["gemini_weekly_fraction"] = frac
                        result["gemini_weekly_reset"] = reset
                else:
                    if window == "5h" or "5h" in bid:
                        result["third_party_5h_fraction"] = frac
                        result["third_party_5h_reset"] = reset
                    elif window == "weekly" or "weekly" in bid:
                        result["third_party_weekly_fraction"] = frac
                        result["third_party_weekly_reset"] = reset

        return result
    except Exception as e:
        print(f"[!] Quota fetch failed: {e}", file=sys.stderr)
        return None


class HubClient:
    def __init__(self, hub_url: str):
        self.hub_url = hub_url.rstrip("/")
        self.ssl_ctx = ssl.create_default_context()
        self.ssl_ctx.check_hostname = False
        self.ssl_ctx.verify_mode = ssl.CERT_NONE

    def _post(self, path: str, payload: dict, timeout: float = 10.0) -> dict | None:
        url = f"{self.hub_url}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=self.ssl_ctx) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception as e:
            # Suppress poll logs
            if "/tasks/claim" not in path:
                print(f"[!] Hub request failed ({path}): {e}", file=sys.stderr)
            return None

    def _get(self, path: str, timeout: float = 10.0):
        url = f"{self.hub_url}{path}"
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=timeout, context=self.ssl_ctx) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception:
            return None

    def get_conversation(self, conv_id: str) -> dict | None:
        return self._get(f"/chat/conversations/{conv_id}")

    def get_node_session(self, conv_id: str, node_id: str) -> str | None:
        data = self._get(f"/chat/session?conv_id={conv_id}&node_id={node_id}")
        if data and data.get("agy_session_id"):
            return data["agy_session_id"]
        return None

    def set_node_session(self, conv_id: str, node_id: str, agy_session_id: str) -> bool:
        resp = self._post("/chat/session", {
            "conv_id": conv_id,
            "node_id": node_id,
            "agy_session_id": agy_session_id
        })
        return bool(resp and resp.get("ok"))

    def send_node_heartbeat(self, node_id: str, hostname: str, capabilities: list[str],
                            agy_ver: str, agy_auth: str, quota: dict | None = None,
                            power: dict | None = None) -> dict | None:
        payload = {
            "node_id": node_id,
            "hostname": hostname,
            "capabilities": capabilities,
            "agy_version": agy_ver,
            "agy_auth": agy_auth
        }
        if quota:
            payload["quota"] = quota
        if power:
            payload["power"] = power
        return self._post("/node/heartbeat", payload)

    def post_node_activity(self, node_id: str, activity: dict) -> bool:
        resp = self._post("/node/activity", {
            "node_id": node_id,
            "activity": activity
        }, timeout=2.0)
        return bool(resp and resp.get("ok"))

    def get_swarm_activity(self, timeout_sec: int = 1800) -> dict:
        data = self._get(f"/swarm/activity?timeout_sec={timeout_sec}", timeout=3.0)
        if data and isinstance(data, dict):
            return data
        return {"active": False, "reasons": ["hub_unreachable"]}

    def claim_task(self, node_id: str, capabilities: list[str]) -> dict | None:
        resp = self._post("/tasks/claim", {
            "node_id": node_id,
            "capabilities": capabilities
        }, timeout=5.0)
        if resp and resp.get("id"):
            return resp
        return None

    def send_task_heartbeat(self, task_id: str, node_id: str) -> bool:
        resp = self._post("/tasks/heartbeat", {
            "task_id": task_id,
            "node_id": node_id
        }, timeout=5.0)
        return bool(resp and resp.get("ok"))

    def post_task_result(self, task_id: str, node_id: str, status: str, result: str,
                         session_id: str = "", duration_sec: float = 0.0, tokens_used: int = 0) -> dict | None:
        return self._post("/tasks/result", {
            "task_id": task_id,
            "node_id": node_id,
            "status": status,
            "result": result,
            "session_id": session_id,
            "duration_seconds": duration_sec,
            "tokens_used": tokens_used
        })


class AgentWorker:
    def __init__(self, hub_url: str, node_id: str | None = None):
        self.node_id = node_id or detect_node_id()
        self.hostname = socket.gethostname()
        self.capabilities = detect_capabilities(self.node_id)
        self.hub = HubClient(hub_url)
        self.stop_event = threading.Event()
        self.current_task_id = None
        self.agy_ver, self.agy_auth = "loading", "loading"
        self.quota_info = None
        self.account_info = {}
        self.last_quota_fetch = 0
        self._quota_lock = threading.Lock()
        self._exec_lock = threading.Lock()
        self.is_executing_task = False
        self.current_activity: dict = {}
        self.power_inhibitor_proc = None
        self.dbus_inhibit_cookie: int | None = None
        self._power_lock = threading.Lock()
        self.consecutive_hub_failures = 0
        self.selected_model = "gemini-3.8-flash-high"

    def _refresh_quota_bg(self):
        with self._quota_lock:
            if self.agy_auth != "AUTHENTICATED":
                return
            if not is_kwallet_unlocked() and not has_oauth_token_file():
                print("[knot-agent] KWallet is locked on autologin node and no token file found; skipping headless quota probe")
                self.last_quota_fetch = time.time()
                return
            self.last_quota_fetch = time.time()
            try:
                self.account_info = fetch_account_info()
                q = fetch_model_quota()
                if q:
                    q["account"] = self.account_info
                    self.quota_info = q
                    g5 = round(q.get("gemini_5h_fraction", 1.0) * 100)
                    gw = round(q.get("gemini_weekly_fraction", 1.0) * 100)
                    print(f"[*] Quota telemetry updated: Gemini 5h={g5}%, Weekly={gw}% (Account: {self.account_info.get('email', 'unknown')})")
                elif self.account_info:
                    if not self.quota_info:
                        self.quota_info = {"account": self.account_info, "fetched_at": int(time.time())}
                    else:
                        self.quota_info["account"] = self.account_info
            except Exception as e:
                print(f"[!] Quota fetch error: {e}")

    def heartbeat_worker(self):
        last_auth_recheck = 0.0
        while not self.stop_event.is_set():
            now = time.time()
            # If unauthenticated, periodically re-check every 30s to detect user login
            if self.agy_auth != "AUTHENTICATED" and (now - last_auth_recheck > 30):
                last_auth_recheck = now
                self.agy_ver, self.agy_auth = get_agy_info()
                if self.agy_auth == "AUTHENTICATED":
                    print(f"[+] Antigravity CLI re-authenticated successfully! ({self.agy_ver})")

            # Dynamic account-switch detection & quota refresh
            if self.agy_auth == "AUTHENTICATED":
                acc = fetch_account_info()
                if acc and acc.get("email"):
                    old_email = (self.account_info or {}).get("email", "")
                    new_email = acc.get("email", "")
                    if old_email and new_email and old_email != new_email:
                        print(f"[*] Antigravity account switched on {self.node_id}: {old_email} -> {new_email}")
                        self.account_info = acc
                        self.quota_info = {"account": acc, "fetched_at": int(time.time())}
                        self.last_quota_fetch = 0  # Force immediate quota refresh for new account
                        threading.Thread(target=self._refresh_quota_bg, daemon=True).start()
                    elif not self.account_info:
                        self.account_info = acc
                        if not self.quota_info:
                            self.quota_info = {"account": acc, "fetched_at": int(time.time())}

            # Only query quota if authenticated and interval has elapsed
            if self.agy_auth == "AUTHENTICATED" and (now - self.last_quota_fetch > 300):
                threading.Thread(target=self._refresh_quota_bg, daemon=True).start()

            power_status = {
                "on_ac": is_on_ac_power(),
                "sleep_inhibited": bool((self.power_inhibitor_proc and self.power_inhibitor_proc.poll() is None) or self.dbus_inhibit_cookie is not None),
                "is_executing_task": self.is_executing_task,
                "activity": self.current_activity
            }
            hb_resp = self.hub.send_node_heartbeat(
                node_id=self.node_id,
                hostname=self.hostname,
                capabilities=self.capabilities,
                agy_ver=self.agy_ver,
                agy_auth=self.agy_auth,
                quota=self.quota_info,
                power=power_status
            )
            if hb_resp is None:
                self.consecutive_hub_failures += 1
                if self.consecutive_hub_failures >= 3:
                    try:
                        new_url = resolve_hub_url()
                        if new_url and new_url != self.hub.hub_url:
                            print(f"[*] Hub unreachable ({self.consecutive_hub_failures} attempts); re-resolved Hub URL: {self.hub.hub_url} -> {new_url}")
                            self.hub = HubClient(new_url)
                            self.consecutive_hub_failures = 0
                    except Exception as e:
                        print(f"[!] Error re-resolving Hub URL: {e}", file=sys.stderr)
            else:
                self.consecutive_hub_failures = 0
                if hb_resp.get("selected_model"):
                    self.selected_model = hb_resp["selected_model"]

            self.stop_event.wait(10.0)

    def power_inhibitor_worker(self):
        """
        Monitors AC power, battery health, and wholesale swarm activity.
        Enforces sleep/idle inhibition via dual systemd and D-Bus layers when:
          1. Node is on AC power OR battery level > 15%.
          2. Swarm is active (local task executing OR Hub reports active tasks / recent chat / manual wake hold).
        Releases inhibition when:
          - Battery is low (<= 15% and on battery) to prevent device drain.
          - Swarm has been idle across all nodes for > 30 minutes.
        """
        while not self.stop_event.is_set():
            try:
                on_ac = is_on_ac_power()
                batt_cap = get_battery_capacity()

                # Critical battery safeguard: if discharging on battery and <= 15%, release inhibition
                if not on_ac and batt_cap is not None and batt_cap <= 15:
                    with self._power_lock:
                        if self.power_inhibitor_proc or self.dbus_inhibit_cookie is not None:
                            self._release_power_inhibit("Battery critical (<=15%), preserving hardware charge")
                    self.stop_event.wait(10.0)
                    continue

                # Check if swarm is active
                is_active = self.is_executing_task
                activity_reasons = ["local_task_executing"] if is_active else []
                if not is_active:
                    activity = self.hub.get_swarm_activity(timeout_sec=1800)
                    if activity.get("active"):
                        is_active = True
                        activity_reasons = activity.get("reasons", ["swarm_activity"])

                with self._power_lock:
                    if is_active:
                        if (not self.power_inhibitor_proc or self.power_inhibitor_proc.poll() is not None) and self.dbus_inhibit_cookie is None:
                            self._acquire_power_inhibit(activity_reasons)
                    else:
                        if self.power_inhibitor_proc or self.dbus_inhibit_cookie is not None:
                            self._release_power_inhibit("Swarm is dormant / idle (>30m)")

            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

            self.stop_event.wait(10.0)

    def _acquire_power_inhibit(self, reasons: list[str]):
        reason_str = f"Knot Swarm Active ({', '.join(reasons)})"

        # 1. Freedesktop / KDE D-Bus PowerManagement Inhibit (unprivileged, works directly with PowerDevil)
        if shutil.which("gdbus") and self.dbus_inhibit_cookie is None:
            try:
                res = subprocess.run([
                    "gdbus", "call", "--session",
                    "--dest", "org.freedesktop.PowerManagement.Inhibit",
                    "--object-path", "/org/freedesktop/PowerManagement/Inhibit",
                    "--method", "org.freedesktop.PowerManagement.Inhibit.Inhibit",
                    "KnotSwarm", reason_str
                ], capture_output=True, text=True, timeout=3)
                if res.returncode == 0 and "uint32" in res.stdout:
                    m = re.search(r"uint32\s+(\d+)", res.stdout)
                    if m:
                        self.dbus_inhibit_cookie = int(m.group(1))
                        print(f"[Power] ⚡ D-Bus PowerManagement inhibited (Cookie {self.dbus_inhibit_cookie})")
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

        # 2. Systemd sleep:idle inhibitor (via sudo or unprivileged)
        proc = None
        try:
            cmd = ["sudo", "-n", "systemd-inhibit", "--what=sleep:idle", "--who=Knot Swarm", f"--why={reason_str}", "sleep", "infinity"]
            proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(0.2)
            if proc.poll() is not None:
                # Sudo failed or not permitted, try unprivileged sleep:idle inhibitor
                cmd = ["systemd-inhibit", "--what=sleep:idle", "--who=Knot Swarm", f"--why={reason_str}", "sleep", "infinity"]
                proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                time.sleep(0.2)
                if proc.poll() is not None:
                    # Final fallback to idle inhibitor
                    cmd = ["systemd-inhibit", "--what=idle", "--who=Knot Swarm", f"--why={reason_str}", "sleep", "infinity"]
                    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

        self.power_inhibitor_proc = proc
        if proc and proc.poll() is None:
            print(f"[Power] ⚡ Systemd sleep & idle inhibited (PID {proc.pid})")

    def _release_power_inhibit(self, reason: str):
        # 1. Release D-Bus inhibitor
        if self.dbus_inhibit_cookie is not None and shutil.which("gdbus"):
            try:
                subprocess.run([
                    "gdbus", "call", "--session",
                    "--dest", "org.freedesktop.PowerManagement.Inhibit",
                    "--object-path", "/org/freedesktop/PowerManagement/Inhibit",
                    "--method", "org.freedesktop.PowerManagement.Inhibit.UnInhibit",
                    str(self.dbus_inhibit_cookie)
                ], capture_output=True, text=True, timeout=3)
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
            self.dbus_inhibit_cookie = None

        # 2. Terminate systemd-inhibit process
        if self.power_inhibitor_proc:
            try:
                self.power_inhibitor_proc.terminate()
                self.power_inhibitor_proc.wait(timeout=2)
            except Exception:
                try:
                    self.power_inhibitor_proc.kill()
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
            self.power_inhibitor_proc = None
        print(f"[Power] 💤 Sleep inhibitor released: {reason}")

    def task_heartbeat_loop(self, task_id: str, done_event: threading.Event):
        while not done_event.is_set() and not self.stop_event.is_set():
            done_event.wait(10.0)
            if not done_event.is_set():
                self.hub.send_task_heartbeat(task_id, self.node_id)

    def execute_agy_task(self, prompt: str, project: str = "knot", conversation_id: str | None = None,
                         task_id: str | None = None, task_title: str | None = None,
                         model: str | None = None) -> tuple[str, str, str, float, int]:
        """
        Executes prompt via agy inside user systemd slice with --dangerously-skip-permissions.
        Binds to native Antigravity project and conversation if provided.
        Enforces sequential execution via _exec_lock to prevent simultaneous token generation.
        Tails session transcript in real-time to stream active tool calls, commands, and thoughts to Hub.
        Returns: (status, response, session_id, duration_sec, tokens_used)
        """
        if self.agy_auth != "AUTHENTICATED":
            return "ERROR", "Antigravity CLI is not authenticated on this node. Run 'knot auth' to log in.", "", 0.0, 0

        if not is_online():
            return "ERROR", "Network or DNS offline on this node. Task deferred.", "", 0.0, 0

        if not is_kwallet_unlocked() and not has_oauth_token_file():
            print("[knot-agent] KWallet is locked on autologin node and no token file found; skipping headless agy execution")
            return "ERROR", "KWallet is locked on autologin node. Please unlock KWallet to execute tasks.", "", 0.0, 0

        knot_dir = (
            os.environ.get("KNOT_ROOT")
            or (os.path.expanduser("~/.local/share/knot-mesh") if os.path.isdir(os.path.expanduser("~/.local/share/knot-mesh")) else None)
            or (os.path.expanduser("~/knot-mesh") if os.path.isdir(os.path.expanduser("~/knot-mesh")) else None)
            or (os.path.expanduser("~/knot") if os.path.isdir(os.path.expanduser("~/knot")) else None)
            or os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
        )
        cmd = ["systemd-run", "--user", "--pipe"] + get_headless_systemd_env()
        if os.path.isdir(knot_dir):
            cmd.append(f"--working-directory={knot_dir}")
        agy_bin = find_agy_binary()
        cmd.extend([
            agy_bin,
            "-p", prompt,
            "--output-format", "json",
            "--dangerously-skip-permissions",
            "--print-timeout", "30m0s"
        ])
        if project:
            cmd.extend(["--project", project])
        if conversation_id:
            cmd.extend(["--conversation", conversation_id])

        model_to_use = model or self.selected_model
        if model_to_use:
            cmd.extend(["--model", model_to_use])

        with self._exec_lock:
            self.is_executing_task = True
            start_ts = time.time()
            self.current_activity = {
                "is_executing": True,
                "node_id": self.node_id,
                "task_id": task_id,
                "task_title": task_title or ("Swarm Turn" if not task_id else "Worker Task"),
                "conv_id": conversation_id or "knot",
                "model": model_to_use,
                "step_index": 0,
                "status": "THINKING",
                "tool_name": None,
                "tool_action": "Planning steps & analyzing context...",
                "tool_summary": "Planning",
                "command": None,
                "thinking_snippet": None,
                "started_at": start_ts,
                "elapsed_sec": 0.0,
                "last_updated": time.time()
            }
            try:
                self.hub.post_node_activity(self.node_id, self.current_activity)
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

            stop_tail = threading.Event()

            def _tail_worker():
                transcript_path = None
                # Discover transcript path
                for _ in range(30):
                    if stop_tail.is_set():
                        return
                    if conversation_id:
                        for base in ["~/.gemini/antigravity-cli/brain", "~/.gemini/antigravity/brain"]:
                            cand = os.path.expanduser(f"{base}/{conversation_id}/.system_generated/logs/transcript.jsonl")
                            if os.path.exists(cand):
                                transcript_path = cand
                                break
                    if transcript_path:
                        break
                    try:
                        for base in ["~/.gemini/antigravity-cli/brain", "~/.gemini/antigravity/brain"]:
                            dirs = glob.glob(os.path.expanduser(f"{base}/*"))
                            dirs = [d for d in dirs if os.path.isdir(d) and os.path.basename(d) != "scratch"]
                            if dirs:
                                dirs.sort(key=lambda d: os.path.getmtime(d), reverse=True)
                                newest = dirs[0]
                                if os.path.getmtime(newest) >= start_ts - 5.0:
                                    cand = os.path.join(newest, ".system_generated", "logs", "transcript.jsonl")
                                    if os.path.exists(cand):
                                        transcript_path = cand
                                        break
                    except Exception as _err:
                        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                    if transcript_path:
                        break
                    time.sleep(0.3)

                if not transcript_path or not os.path.exists(transcript_path):
                    while not stop_tail.is_set():
                        time.sleep(1.0)
                        self.current_activity["elapsed_sec"] = round(time.time() - start_ts, 1)
                        try:
                            self.hub.post_node_activity(self.node_id, self.current_activity)
                        except Exception as _err:
                            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                    return

                last_hb = time.time()
                try:
                    with open(transcript_path, "r", encoding="utf-8", errors="replace") as tf:
                        if conversation_id:
                            tf.seek(0, os.SEEK_END)
                        while not stop_tail.is_set():
                            line = tf.readline()
                            if line:
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    obj = json.loads(line)
                                    step_idx = obj.get("step_index", self.current_activity.get("step_index", 0))
                                    tool_calls = obj.get("tool_calls")
                                    thinking = obj.get("thinking")
                                    msg_type = obj.get("type")
                                    did_update = False

                                    if thinking and isinstance(thinking, str):
                                        snip = thinking.strip()[:140]
                                        if snip:
                                            self.current_activity["thinking_snippet"] = snip
                                            did_update = True

                                    if tool_calls and isinstance(tool_calls, list) and len(tool_calls) > 0:
                                        t0 = tool_calls[0]
                                        t_name = t0.get("name", "tool")
                                        t_args = t0.get("args", {})
                                        t_action = t_args.get("toolAction") or t_name
                                        t_summary = t_args.get("toolSummary") or t_name
                                        cmd_str = t_args.get("CommandLine") if t_name == "run_command" else None

                                        if t_name == "run_command":
                                            status_val = "COMMAND"
                                        elif "wait" in str(t_action).lower() or "wait" in str(t_name).lower():
                                            status_val = "WAITING"
                                        elif "fanout" in str(t_name) or "post" in str(t_name):
                                            status_val = "DISPATCHING"
                                        else:
                                            status_val = "TOOL_USE"

                                        self.current_activity.update({
                                            "step_index": step_idx,
                                            "status": status_val,
                                            "tool_name": t_name,
                                            "tool_action": t_action,
                                            "tool_summary": t_summary,
                                            "command": cmd_str,
                                            "args_summary": str(t_args)[:120] if t_name != "run_command" else None,
                                            "elapsed_sec": round(time.time() - start_ts, 1),
                                            "last_updated": time.time()
                                        })
                                        did_update = True
                                    elif msg_type == "GENERIC":
                                        self.current_activity.update({
                                            "step_index": step_idx,
                                            "status": "THINKING",
                                            "tool_action": "Evaluating output & deciding next action...",
                                            "tool_summary": "Synthesizing",
                                            "command": None,
                                            "elapsed_sec": round(time.time() - start_ts, 1),
                                            "last_updated": time.time()
                                        })
                                        did_update = True

                                    if did_update:
                                        self.hub.post_node_activity(self.node_id, self.current_activity)
                                        last_hb = time.time()
                                except Exception as _err:
                                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                            else:
                                now_t = time.time()
                                if now_t - last_hb >= 1.5:
                                    self.current_activity["elapsed_sec"] = round(now_t - start_ts, 1)
                                    try:
                                        self.hub.post_node_activity(self.node_id, self.current_activity)
                                    except Exception as _err:
                                        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                                    last_hb = now_t
                                time.sleep(0.25)
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

            tail_thread = threading.Thread(target=_tail_worker, daemon=True)
            tail_thread.start()

            try:
                p = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
                duration_sec = round(time.time() - start_ts, 2)
                raw_out = p.stdout.strip()

                # Find the JSON telemetry line
                json_line = None
                for line in reversed(raw_out.splitlines()):
                    line = line.strip()
                    if line.startswith("{") and '"status"' in line:
                        json_line = line
                        break

                if json_line:
                    data = json.loads(json_line)
                    raw_status = data.get("status", "SUCCESS" if p.returncode == 0 else "FAILED")
                    status = "COMPLETED" if raw_status in ("SUCCESS", "COMPLETED") else raw_status
                    response = data.get("response", "")
                    session_id = data.get("conversation_id", "") or conversation_id or ""
                    dur = float(data.get("duration_seconds", duration_sec))
                    tokens = int(data.get("usage", {}).get("total_tokens", 0))
                    return status, response, session_id, dur, tokens
                else:
                    status = "COMPLETED" if p.returncode == 0 else "FAILED"
                    err_msg = raw_out or p.stderr.strip() or f"Process exited with code {p.returncode}"
                    return status, err_msg, conversation_id or "", duration_sec, 0

            except subprocess.TimeoutExpired:
                return "TIMEOUT", "Task exceeded maximum allowed runtime (1800s)", conversation_id or "", 1800.0, 0
            except Exception as e:
                return "ERROR", f"Subprocess execution error: {e}", conversation_id or "", round(time.time() - start_ts, 2), 0
            finally:
                stop_tail.set()
                tail_thread.join(timeout=0.5)
                self.is_executing_task = False
                self.current_activity = {
                    "is_executing": False,
                    "node_id": self.node_id,
                    "status": "IDLE",
                    "tool_action": None,
                    "elapsed_sec": round(time.time() - start_ts, 1),
                    "last_updated": time.time()
                }
                try:
                    self.hub.post_node_activity(self.node_id, self.current_activity)
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    def chat_mention_worker(self):
        """
        Listens to Swarm Konversations across all channels (conv_id=all) for direct mentions
        (@node_id or @swarm for desktop) and responds autonomously in the channel,
        preserving native agy project context and conversation session.
        """
        last_seen_ts = int(time.time())
        while not self.stop_event.is_set():
            self.stop_event.wait(4.0)
            if self.stop_event.is_set():
                break
            try:
                url = f"{self.hub.hub_url}/chat/messages?conv_id=all&limit=20"
                req = urllib.request.Request(url, headers={"Accept": "application/json"})
                with urllib.request.urlopen(req, timeout=5.0, context=self.hub.ssl_ctx) as resp:
                    messages = json.loads(resp.read().decode("utf-8"))
                    for m in messages:
                        m_ts = m.get("created_at", 0)
                        if m_ts <= last_seen_ts:
                            continue
                        last_seen_ts = max(last_seen_ts, m_ts)

                        sender = m.get("sender", "")
                        if sender == self.node_id:
                            continue

                        mentions = m.get("mentions", [])
                        content = m.get("content", "")
                        conv_id = m.get("conv_id", "main")

                        # Parse metadata for cascade control
                        meta = m.get("meta", {})
                        if isinstance(meta, str):
                            try:
                                meta = json.loads(meta)
                            except Exception:
                                meta = {}
                        turn_depth = int(meta.get("turn_depth", 0))
                        is_human = sender.startswith("human") or sender in ("user", "operator")

                        should_respond = False
                        is_swarm_broadcast = any(k in mentions for k in ["@swarm", "swarm", "@all", "all"])
                        if is_swarm_broadcast:
                            # Swarm-level broadcasts must only be coordinated by the master planner / anchor node (desktop)
                            if self.node_id == "desktop":
                                should_respond = True
                        else:
                            # Direct mentions to specific nodes
                            if f"@{self.node_id}" in mentions or self.node_id in mentions:
                                should_respond = True

                        # Anti-cascade guardrails: halt ping-pong chatter loops between peer agents
                        if should_respond and not is_human:
                            # 1. Cap automated agent-to-agent cascade depth
                            if turn_depth >= 2:
                                should_respond = False
                            # 2. Ignore passive acknowledgments / wrap-ups if no question mark is present
                            ack_markers = [
                                "confirmed", "standing by", "consensus confirmed",
                                "wrap-up acknowledged", "acknowledged.", "synchronized",
                                "idle, and standing by"
                            ]
                            lower_c = content.lower()
                            if any(am in lower_c for am in ack_markers) and "?" not in content:
                                should_respond = False

                        if should_respond and self.agy_auth == "AUTHENTICATED":
                            # 1. Look up conversation details and project
                            conv = self.hub.get_conversation(conv_id)
                            project_id = conv.get("project_id", "knot") if conv else "knot"
                            conv_title = conv.get("title", f"#{conv_id}") if conv else f"#{conv_id}"

                            # 2. Look up existing native agy conversation session for this node in this channel
                            existing_session_id = self.hub.get_node_session(conv_id, self.node_id)

                            print(f"\n[💬] @{self.node_id} mentioned by @{sender} in #{conv_id} (project: {project_id}, session: {existing_session_id or 'new'}): \"{content[:60]}...\"")

                            prompt = (
                                f"You are @{self.node_id}, an autonomous agent node in the Knot Swarm.\n"
                                f"In channel #{conv_id} ({conv_title}) under project '{project_id}', @{sender} said:\n"
                                f"\"{content}\"\n\n"
                                f"Respond concisely and helpfully to the channel as @{self.node_id}.\n"
                                f"- Your concluding markdown response will be automatically posted to channel #{conv_id}. If you need to post interim progress updates while executing long multi-step tasks, you may use `knot_chat_post`.\n"
                                f"- CRITICAL: Use Linda Tuplespace MCP tools (`knot_task_post`, `knot_task_fanout`, `knot_task_wait`) for multi-node task execution and barrier joins. NEVER use chat @mentions for task execution, polling, or barrier synchronization.\n"
                                f"- Never mention peer nodes for passive acknowledgments, readiness confirmations, or status handshakes. Only mention a peer node if you have an explicit new question or directive for them."
                            )

                            # Resolve model hierarchically:
                            # 1. Message meta override
                            # 2. Conversation node override
                            # 3. Conversation default model
                            # 4. Global node model (self.selected_model)
                            msg_meta = m.get("meta") or {}
                            conv_node_models = conv.get("node_models") or {} if conv else {}
                            conv_selected_model = conv.get("selected_model") if conv else None
                            turn_model = (
                                msg_meta.get("model") or
                                conv_node_models.get(self.node_id) or
                                conv_selected_model or
                                self.selected_model
                            )

                            start_turn_time = time.time()
                            status, reply, session_id, dur, tokens = self.execute_agy_task(
                                prompt=prompt,
                                project=project_id,
                                conversation_id=existing_session_id,
                                task_title=f"#{conv_id} Response",
                                model=turn_model
                            )

                            # 3. Persist native agy conversation session if newly created or updated
                            target_session = session_id or existing_session_id
                            if target_session and target_session != existing_session_id:
                                self.hub.set_node_session(conv_id, self.node_id, target_session)

                            # Check if the agent already posted directly via knot_chat_post during this execution
                            already_posted = False
                            try:
                                recent_msgs = self.hub._get(f"/chat/messages?conv_id={conv_id}&limit=5")
                                if recent_msgs and isinstance(recent_msgs, list):
                                    for rm in recent_msgs:
                                        if rm.get("sender") == self.node_id and rm.get("created_at", 0) >= int(start_turn_time):
                                            already_posted = True
                                            break
                            except Exception as _err:
                                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

                            is_wrapper_stub = False
                            if reply:
                                low_reply = reply.lower().strip()
                                is_wrapper_stub = any(low_reply.startswith(p) for p in [
                                    "i have posted", "i have dispatched", "as @", "here is the channel response",
                                    "i have shared", "i have updated the channel"
                                ])

                            if reply and status == "COMPLETED":
                                if already_posted and is_wrapper_stub:
                                    print(f"[*] Suppressed redundant wrapper reply in #{conv_id} (session: {target_session[:8] if target_session else 'none'})")
                                else:
                                    self.hub._post("/chat/messages", {
                                        "sender": self.node_id,
                                        "content": reply,
                                        "conv_id": conv_id,
                                        "reply_to": m.get("id"),
                                        "meta": {
                                            "session_id": target_session,
                                            "project_id": project_id,
                                            "duration_seconds": dur,
                                            "tokens_used": tokens,
                                            "turn_depth": turn_depth + 1
                                        }
                                    })
                                    print(f"[✓] Posted reply to #{conv_id} in {dur}s (session: {target_session[:8] if target_session else 'none'})")
                            elif status != "COMPLETED":
                                error_notice = f"⚠️ **@{self.node_id} execution notice ({status}):**\n\n> {reply or 'Subprocess did not return a response.'}"
                                self.hub._post("/chat/messages", {
                                    "sender": self.node_id,
                                    "content": error_notice,
                                    "conv_id": conv_id,
                                    "reply_to": m.get("id"),
                                    "meta": {
                                        "session_id": target_session,
                                        "project_id": project_id,
                                        "duration_seconds": dur,
                                        "tokens_used": tokens,
                                        "turn_depth": turn_depth + 1,
                                        "error": True
                                    }
                                })
                                print(f"[!] Posted failure notification to #{conv_id} (status: {status})")

                            # 4. Background transcript ingestion if session exists
                            if target_session:
                                def _bg_chat_ingest(s_id=target_session):
                                    try:
                                        from core.memory.palace import MemoryPalaceClient
                                        palace = MemoryPalaceClient()
                                        for cand in [
                                            os.path.expanduser(f"~/.gemini/antigravity-cli/brain/{s_id}/.system_generated/logs/transcript.jsonl"),
                                            os.path.expanduser(f"~/.gemini/antigravity/brain/{s_id}/.system_generated/logs/transcript.jsonl"),
                                        ]:
                                            if os.path.exists(cand):
                                                palace.ingest_antigravity_transcript(cand, s_id, self.node_id)
                                                break
                                    except Exception as _err:
                                        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                                threading.Thread(target=_bg_chat_ingest, daemon=True).start()
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    def run(self):
        print(f"[*] Knot Swarm Worker starting on node: {self.node_id} ({self.hostname})")
        print(f"[*] Capabilities: {', '.join(self.capabilities)}")
        print(f"[*] Hub URL: {self.hub.hub_url}")

        self.agy_ver, self.agy_auth = get_agy_info()
        print(f"[*] Antigravity CLI: {self.agy_ver} (Auth: {self.agy_auth})")

        # Start background node heartbeat
        hb_thread = threading.Thread(target=self.heartbeat_worker, daemon=True)
        hb_thread.start()

        # Start Swarm Konversations mention listener
        chat_thread = threading.Thread(target=self.chat_mention_worker, daemon=True)
        chat_thread.start()

        # Fetch initial model quota in background
        threading.Thread(target=self._refresh_quota_bg, daemon=True).start()

        # Start background power / prevent-sleep manager
        power_thread = threading.Thread(target=self.power_inhibitor_worker, daemon=True)
        power_thread.start()

        while not self.stop_event.is_set():
            task = self.hub.claim_task(self.node_id, self.capabilities)
            if task:
                task_id = task["id"]
                title = task.get("title", "Untitled Task")
                prompt = task.get("prompt", "")
                task_meta = {}
                try:
                    task_meta = json.loads(task.get("meta") or "{}")
                except Exception as _err:
                    sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
                task_project = task_meta.get("project") or "knot"
                task_conv = task_meta.get("conversation_id") or None

                print(f"\n[+] Claimed Task: [{task_id[:8]}] {title} (Project: {task_project})")
                print(f"    Prompt: \"{prompt[:80]}...\"")

                # Start concurrent task heartbeat renewals
                task_done = threading.Event()
                thb_thread = threading.Thread(target=self.task_heartbeat_loop, args=(task_id, task_done), daemon=True)
                thb_thread.start()

                try:
                    task_model = (task.get("meta") or {}).get("model")
                    status, response, session_id, dur, tokens = self.execute_agy_task(
                        prompt=prompt,
                        project=task_project,
                        conversation_id=task_conv,
                        task_id=task_id,
                        task_title=title,
                        model=task_model
                    )
                finally:
                    task_done.set()

                print(f"[✓] Completed [{task_id[:8]}] in {dur}s ({tokens} tokens) | Status: {status}")
                self.hub.post_task_result(
                    task_id=task_id,
                    node_id=self.node_id,
                    status=status,
                    result=response,
                    session_id=session_id,
                    duration_sec=dur,
                    tokens_used=tokens
                )

                # Background session transcript ingestion
                if session_id:
                    def _bg_ingest():
                        try:
                            from core.memory.palace import MemoryPalaceClient
                            palace = MemoryPalaceClient()
                            for cand in [
                                os.path.expanduser(f"~/.gemini/antigravity-cli/brain/{session_id}/.system_generated/logs/transcript.jsonl"),
                                os.path.expanduser(f"~/.gemini/antigravity/brain/{session_id}/.system_generated/logs/transcript.jsonl"),
                            ]:
                                if os.path.exists(cand):
                                    palace.ingest_antigravity_transcript(cand, session_id, self.node_id)
                                    print(f"[*] Ingested transcript for session {session_id[:8]} into Memory Palace.")
                                    break
                        except Exception as e:
                            print(f"[!] Memory Palace transcript ingest failed for session {session_id[:8]}: {e}", file=sys.stderr)
                    threading.Thread(target=_bg_ingest, daemon=True).start()

                # Refresh quota in background after task completion
                threading.Thread(target=self._refresh_quota_bg, daemon=True).start()
            else:
                self.stop_event.wait(DEFAULT_POLL_INTERVAL)


def resolve_hub_url() -> str:
    if os.environ.get("KNOT_HUB_URL"):
        return os.environ["KNOT_HUB_URL"]

    my_host = socket.gethostname().lower()
    user_home = os.environ.get("HOME", os.path.expanduser("~"))
    knot_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

    active_id = "office"
    for active_profile_file in ["/run/knot/active_swarm", os.path.join(user_home, ".local/state/knot/active_swarm")]:
        if os.path.exists(active_profile_file):
            try:
                with open(active_profile_file, "r") as f:
                    content = f.read().strip()
                    if content and content != "none":
                        active_id = content
                        break
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    conf_candidates = [
        f"/etc/knot/swarms.d/{active_id}.conf",
        os.path.join(user_home, f".config/knot/swarms/{active_id}.conf"),
        os.path.join(user_home, f".config/knot/swarms/{active_id}/swarm.conf"),
    ]

    anchor_host = ""
    anchor_id = "desktop"
    hub_port = DEFAULT_HUB_PORT

    for conf_path in conf_candidates:
        if os.path.exists(conf_path):
            try:
                with open(conf_path, "r") as f:
                    for line in f:
                        if line.startswith("ANCHOR_HOST="):
                            anchor_host = line.split("=", 1)[1].strip().strip('"')
                        elif line.startswith("ANCHOR_ID="):
                            anchor_id = line.split("=", 1)[1].strip().strip('"')
                        elif line.startswith("HUB_PORT="):
                            hub_port = int(line.split("=", 1)[1].strip().strip('"'))
            except Exception as _err:
                sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")
            if anchor_host or anchor_id:
                break

    # If this machine is the anchor, connect directly to loopback
    if my_host in (anchor_host.lower(), anchor_id.lower(), "desktop"):
        return f"https://127.0.0.1:{hub_port}"

    # Try resolving Anchor IP via resolver.sh first (vital for strands where hostnames lack DNS)
    try:
        resolver = os.path.join(knot_root, "core/resolver.sh")
        if os.path.exists(resolver):
            target = anchor_id or "desktop"
            p = subprocess.run([resolver, target, str(hub_port)], capture_output=True, text=True, timeout=3)
            if p.returncode == 0 and p.stdout.strip():
                ip = p.stdout.strip()
                if ip and ip != "127.0.0.1":
                    return f"https://{ip}:{hub_port}"
    except Exception as _err:
        sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # If anchor_host is an IP or resolvable hostname
    if anchor_host:
        try:
            socket.gethostbyname(anchor_host)
            return f"https://{anchor_host}:{hub_port}"
        except Exception as _err:
            sys.stderr.write(f"Notice: [agent] Handled exception: {_err}\n")

    # Fallback to local loopback HTTPS
    return f"https://127.0.0.1:{hub_port}"


def main():
    hub_url = resolve_hub_url()
    worker = AgentWorker(hub_url=hub_url)

    def handle_sig(sig, frame):
        print("\n[*] Stopping Knot Swarm Worker...")
        worker.stop_event.set()
        with worker._power_lock:
            worker._release_power_inhibit("Daemon shutdown")
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_sig)
    signal.signal(signal.SIGTERM, handle_sig)

    worker.run()


if __name__ == "__main__":
    main()
