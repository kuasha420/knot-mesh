#!/usr/bin/env python3
"""
Knot Swarm Blackboard Hub (knot-hub)
Lightweight coordination daemon implementing Linda Tuplespace primitives (OUT, IN, RD),
DAG task dependency resolution, batch fan-out / barrier joins, Swarm Konversations channel ledger,
3-state atomic artifact lease vault, and real-time Server-Sent Events (SSE).
Zero external dependencies (uses standard library Python 3).
"""

import base64
import glob
import io
import json
import mimetypes
import os
import logging
import re
import secrets
import shutil
import socket
import sqlite3
import ssl
import subprocess
import sys
import tarfile
import threading
import time
import uuid
from typing import Optional, Dict, Any, List, Tuple, Union

logger = logging.getLogger("knot-hub")
from http.server import HTTPServer, ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

from datetime import datetime, timezone

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HUB_DIR = os.path.abspath(os.path.dirname(__file__))
for _p in (REPO_ROOT, HUB_DIR):
    if _p not in sys.path:
        sys.path.insert(0, _p)

WEB_DIST_DIR = os.path.abspath(
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "web", "dist")
)

DEFAULT_PORT = 4242
DEFAULT_DB_PATH = os.path.expanduser("~/.config/knot/hub.db")
DEFAULT_LEASE_TTL = 60  # seconds
DEFAULT_ARTIFACT_LEASE_TTL = 120  # seconds

OFFICIAL_MODELS = [
    {
        "id": "gemini-3.8-flash-high",
        "name": "Gemini 3.8 Flash (High)",
        "tier": "flash",
        "provider": "google",
        "description": "Fast & intelligent with high reasoning effort"
    },
    {
        "id": "gemini-3.8-flash-medium",
        "name": "Gemini 3.8 Flash (Medium)",
        "tier": "flash",
        "provider": "google",
        "description": "Fast & efficient with medium reasoning effort"
    },
    {
        "id": "gemini-3.8-flash-low",
        "name": "Gemini 3.8 Flash (Low)",
        "tier": "flash",
        "provider": "google",
        "description": "Ultra-fast with minimal reasoning overhead"
    },
    {
        "id": "gemini-3.7-flash-high",
        "name": "Gemini 3.7 Flash (High)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.7 Flash with high reasoning effort"
    },
    {
        "id": "gemini-3.7-flash-medium",
        "name": "Gemini 3.7 Flash (Medium)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.7 Flash with medium reasoning effort"
    },
    {
        "id": "gemini-3.7-flash-low",
        "name": "Gemini 3.7 Flash (Low)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.7 Flash with minimal reasoning overhead"
    },
    {
        "id": "gemini-3.6-flash-high",
        "name": "Gemini 3.6 Flash (High)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.6 Flash with high reasoning effort"
    },
    {
        "id": "gemini-3.6-flash-medium",
        "name": "Gemini 3.6 Flash (Medium)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.6 Flash with medium reasoning effort"
    },
    {
        "id": "gemini-3.6-flash-low",
        "name": "Gemini 3.6 Flash (Low)",
        "tier": "flash",
        "provider": "google",
        "description": "Gemini 3.6 Flash with minimal reasoning overhead"
    },
    {
        "id": "gemini-3.1-pro-high",
        "name": "Gemini 3.1 Pro (High)",
        "tier": "pro",
        "provider": "google",
        "description": "Deep reasoning heavyweight model for complex architecture"
    },
    {
        "id": "gemini-3.1-pro-low",
        "name": "Gemini 3.1 Pro (Low)",
        "tier": "pro",
        "provider": "google",
        "description": "Pro-tier model with low reasoning effort"
    },
    {
        "id": "claude-sonnet-4-6",
        "name": "Claude Sonnet 4.6 (Thinking)",
        "tier": "claude",
        "provider": "anthropic",
        "description": "Anthropic Claude Sonnet 4.6 with thinking mode"
    },
    {
        "id": "claude-opus-4-6-thinking",
        "name": "Claude Opus 4.6 (Thinking)",
        "tier": "claude",
        "provider": "anthropic",
        "description": "Anthropic Claude Opus 4.6 with extended thinking"
    },
    {
        "id": "gpt-oss-120b-medium",
        "name": "GPT-OSS 120B (Medium)",
        "tier": "oss",
        "provider": "openai",
        "description": "Open weights 120B parameter model"
    },
]
AVAILABLE_MODELS = OFFICIAL_MODELS
DEFAULT_SWARM_MODEL = "gemini-3.8-flash-high"

_cached_live_models = None
_cached_live_models_ts = 0


def get_available_models() -> list[dict]:
    global _cached_live_models, _cached_live_models_ts
    now = time.time()
    if _cached_live_models and (now - _cached_live_models_ts < 300):
        return _cached_live_models

    agy_bin = shutil.which("agy") or os.path.expanduser("~/.local/bin/agy")
    if agy_bin and os.path.exists(agy_bin):
        try:
            res = subprocess.run([agy_bin, "models"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0 and res.stdout:
                parsed = []
                for line in res.stdout.splitlines():
                    clean = re.sub(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])", "", line).strip()
                    if not clean or "Fetching" in clean or clean.startswith("⠋") or clean.startswith("⠙"):
                        continue
                    parts = clean.split(None, 1)
                    if len(parts) == 2:
                        mid, mname = parts[0].strip(), parts[1].strip()
                        tier = "flash" if "flash" in mid else ("pro" if "pro" in mid else ("claude" if "claude" in mid else ("oss" if "oss" in mid else "general")))
                        prov = "google" if "gemini" in mid else ("anthropic" if "claude" in mid else ("openai" if "gpt" in mid else "other"))
                        parsed.append({
                            "id": mid,
                            "name": mname,
                            "tier": tier,
                            "provider": prov,
                            "description": f"Antigravity official model: {mname}"
                        })
                if parsed:
                    _cached_live_models = parsed
                    _cached_live_models_ts = now
                    return parsed
        except Exception as e:
            sys.stderr.write(f"[knot-hub] Error querying agy models: {e}\n")

    _cached_live_models = OFFICIAL_MODELS
    _cached_live_models_ts = now
    return OFFICIAL_MODELS



def format_reset_countdown(reset_iso: str | None) -> str:
    if not reset_iso:
        return "-"
    try:
        clean_iso = re.sub(r"(\.\d{6})\d+", r"\1", str(reset_iso))
        dt = datetime.fromisoformat(clean_iso.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        diff = dt - now
        secs = int(diff.total_seconds())
        if secs <= 0:
            return "Ready"
        hrs = secs // 3600
        mins = (secs % 3600) // 60
        days = hrs // 24
        if days > 0:
            rem_hrs = hrs % 24
            return f"in {days}d {rem_hrs}h"
        return f"in {hrs}h {mins}m"
    except Exception:
        return str(reset_iso)[:16]

# Global subscriber queues for SSE broadcasting
_subscribers_lock = threading.Lock()
_subscribers = set()


def broadcast_event(event_type: str, data: dict):
    payload = f"event: {event_type}\ndata: {json.dumps(data)}\n\n".encode("utf-8")
    with _subscribers_lock:
        dead = []
        for q in _subscribers:
            try:
                q.put_nowait(payload)
            except Exception:
                dead.append(q)
        for d in dead:
            _subscribers.discard(d)


KNOT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
)
REGISTRY_NODES_DIR = os.path.join(KNOT_ROOT, "registry", "nodes")
SCREEN_CACHE_DIR = "/tmp/knot_screens"
SCREEN_CACHE_TTL = 8.0  # seconds for thumbnail
SCREEN_CACHE_TTL_HI = 1.2  # seconds for high-quality expanded stream

_node_screen_locks: dict[str, threading.Lock] = {}
_screen_locks_mutex = threading.Lock()


def get_node_manifest(node_id: str) -> dict:
    if not re.match(r"^[a-zA-Z0-9_-]+$", str(node_id)):
        return {}
    active_swarm, _ = get_active_swarm_info()
    paths = [
        os.path.expanduser(f"~/.config/knot/swarms/{active_swarm}/nodes/{node_id}.json"),
        os.path.join(REGISTRY_NODES_DIR, f"{node_id}.json"),
    ]
    manifest = {}
    for path in paths:
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    manifest = json.load(f)
                    break
            except Exception as e:
                logger.warning("Error reading node manifest %s: %s", path, e)

    # Check database nodes table if ip is missing
    if not manifest.get("ip_hint") and not manifest.get("ip"):
        try:
            if os.path.isfile(DEFAULT_DB_PATH):
                with sqlite3.connect(DEFAULT_DB_PATH) as conn:
                    conn.row_factory = sqlite3.Row
                    row = conn.execute("SELECT ip FROM nodes WHERE id = ? OR hostname = ?", (node_id, node_id)).fetchone()
                    if row and row["ip"]:
                        manifest["ip_hint"] = row["ip"]
        except Exception as e:
            logger.warning("Error querying db for node %s IP: %s", node_id, e)

    # Check cached leases
    if not manifest.get("ip_hint") and not manifest.get("ip"):
        cache_dir = os.path.expanduser("~/.cache/knot/leases")
        if os.path.isdir(cache_dir):
            for lfile in (f"{active_swarm}_{node_id}", node_id):
                lpath = os.path.join(cache_dir, lfile)
                if os.path.isfile(lpath):
                    try:
                        with open(lpath, "r") as lf:
                            lip = lf.read().strip()
                            if lip:
                                manifest["ip_hint"] = lip
                                break
                    except Exception as e:
                        logger.warning("Error reading lease %s: %s", lpath, e)

    return manifest


def get_canonical_node_id(node_id: str) -> str:
    if not node_id:
        return "unknown"
    nid_lower = str(node_id).lower().strip()
    active_swarm, _ = get_active_swarm_info()
    user_home = os.path.expanduser("~")
    nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")
    if os.path.isdir(nodes_dir):
        for f in os.listdir(nodes_dir):
            if f.endswith(".json"):
                fp = os.path.join(nodes_dir, f)
                try:
                    with open(fp, "r", encoding="utf-8") as jf:
                        m = json.load(jf)
                        can_id = m.get("id", f[:-5])
                        m_host = (m.get("hostname") or "").lower()
                        aliases = [a.lower() for a in m.get("aliases", [])]
                        if nid_lower in (can_id.lower(), m_host, *aliases):
                            return can_id
                except Exception as e:
                    sys.stderr.write(f"Notice: [hub] Failed to parse node manifest {fp}: {e}\n")
    return node_id


def _get_screen_lock(node_id: str) -> threading.Lock:
    with _screen_locks_mutex:
        if node_id not in _node_screen_locks:
            _node_screen_locks[node_id] = threading.Lock()
        return _node_screen_locks[node_id]


def _generate_screen_placeholder_svg(node_id: str, message: str = "Display Offline / Sleeping") -> bytes:
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="480" height="270" viewBox="0 0 480 270">
  <rect width="480" height="270" fill="#16161e"/>
  <rect x="2" y="2" width="476" height="266" rx="8" fill="#1a1b26" stroke="#24283b" stroke-width="2"/>
  <circle cx="240" cy="100" r="28" fill="#24283b" stroke="#7aa2f7" stroke-width="1.5" stroke-dasharray="4 2"/>
  <path d="M228 92h24v16h-24z" fill="none" stroke="#7aa2f7" stroke-width="2" rx="2"/>
  <path d="M236 108v4h8v-4" fill="none" stroke="#7aa2f7" stroke-width="2"/>
  <text x="240" y="150" fill="#c0caf5" font-family="monospace" font-size="14" font-weight="bold" text-anchor="middle">@{node_id}</text>
  <text x="240" y="175" fill="#565f89" font-family="monospace" font-size="11" text-anchor="middle">{message}</text>
  <text x="240" y="240" fill="#414868" font-family="monospace" font-size="9" text-anchor="middle">KNOT SWARM TELEMETRY DISPLAY</text>
</svg>"""
    return svg.encode("utf-8")


def capture_node_screen(node_id: str, force: bool = False, quality: str = "low") -> tuple[bytes | None, str]:
    if not re.match(r"^[a-zA-Z0-9_-]+$", str(node_id)):
        return None, "image/jpeg"

    is_high = quality in ("high", "hi", "hd", "1")
    os.makedirs(SCREEN_CACHE_DIR, exist_ok=True)
    cache_file = os.path.join(SCREEN_CACHE_DIR, f"{node_id}_hi.jpg" if is_high else f"{node_id}.jpg")
    ttl = SCREEN_CACHE_TTL_HI if is_high else SCREEN_CACHE_TTL

    now = time.time()
    if not force and os.path.isfile(cache_file):
        try:
            mtime = os.path.getmtime(cache_file)
            if (now - mtime) < ttl and os.path.getsize(cache_file) > 500:
                with open(cache_file, "rb") as f:
                    return f.read(), "image/jpeg"
        except Exception as e:
            sys.stderr.write(f"Notice: [hub] Failed to read cached screen {cache_file}: {e}\n")

    lock = _get_screen_lock(node_id)
    lock_timeout = 2.0 if is_high else 5.0
    acquired = lock.acquire(timeout=lock_timeout)
    if not acquired:
        if os.path.isfile(cache_file) and os.path.getsize(cache_file) > 500:
            with open(cache_file, "rb") as f:
                return f.read(), "image/jpeg"
        return _generate_screen_placeholder_svg(node_id, "Capture In Progress..."), "image/svg+xml"

    try:
        if not force and os.path.isfile(cache_file):
            mtime = os.path.getmtime(cache_file)
            if (time.time() - mtime) < ttl and os.path.getsize(cache_file) > 500:
                with open(cache_file, "rb") as f:
                    return f.read(), "image/jpeg"

        manifest = get_node_manifest(node_id)
        raw_png = os.path.join(SCREEN_CACHE_DIR, f"{node_id}_raw.png")

        res_geom = (1280, 720) if is_high else (480, 270)
        res_qual = 82 if is_high else 60

        # Determine if node_id represents the local host
        local_hostname = socket.gethostname().lower()
        active_swarm, _ = get_active_swarm_info()
        is_local = (
            node_id.lower() in (local_hostname, "desktop", "localhost")
            or manifest.get("role") == "anchor"
            or manifest.get("ip_hint") in ("127.0.0.1", "::1")
        )

        raw_bytes = None
        if is_local:
            env = os.environ.copy()
            env.setdefault("WAYLAND_DISPLAY", "wayland-0")
            env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
            cmd_capture = ["spectacle", "-b", "-n", "-o", raw_png]
            res1 = subprocess.run(cmd_capture, env=env, capture_output=True, text=True, timeout=4)
            if res1.returncode == 0 and os.path.isfile(raw_png):
                with open(raw_png, "rb") as f:
                    raw_bytes = f.read()
            elif res1.returncode != 0:
                logger.warning("Local spectacle screen capture failed (rc=%s): %s", res1.returncode, res1.stderr.strip())
        else:
            ip = manifest.get("ip_hint") or ""
            if not ip and "interfaces" in manifest:
                for iface in manifest["interfaces"].values():
                    if isinstance(iface, dict) and iface.get("ip"):
                        ip = iface["ip"]
                        break
            user = manifest.get("user") or os.environ.get("USER") or "user"
            port = str(manifest.get("port") or 22)

            if ip:
                remote_cmd = (
                    f"WAYLAND_DISPLAY=wayland-0 spectacle -b -n -o /tmp/knot_screen_{node_id}.png && "
                    f"cat /tmp/knot_screen_{node_id}.png && rm -f /tmp/knot_screen_{node_id}.png"
                )
                ssh_cmd = [
                    "ssh", "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=accept-new",
                    "-p", port, f"{user}@{ip}", remote_cmd
                ]
                res = subprocess.run(ssh_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6)
                if res.returncode == 0 and len(res.stdout) > 500:
                    raw_bytes = res.stdout
                elif res.returncode != 0:
                    logger.warning("Remote spectacle capture failed on %s (rc=%s): %s", node_id, res.returncode, res.stderr.decode('utf-8', errors='replace').strip())

        if raw_bytes and len(raw_bytes) > 500:
            try:
                from PIL import Image
                import io
                with Image.open(io.BytesIO(raw_bytes)) as img:
                    img.thumbnail(res_geom)
                    img.convert("RGB").save(cache_file, "JPEG", quality=res_qual)
                with open(cache_file, "rb") as f:
                    return f.read(), "image/jpeg"
            except Exception as img_err:
                logger.warning("Failed to process screenshot with PIL: %s", img_err)
                with open(cache_file, "wb") as f:
                    f.write(raw_bytes)
                return raw_bytes, "image/png"

        if os.path.isfile(cache_file) and os.path.getsize(cache_file) > 500:
            with open(cache_file, "rb") as f:
                return f.read(), "image/jpeg"

        return _generate_screen_placeholder_svg(node_id, "Display Unavailable"), "image/svg+xml"
    except Exception as e:
        if os.path.isfile(cache_file) and os.path.getsize(cache_file) > 500:
            with open(cache_file, "rb") as f:
                return f.read(), "image/jpeg"
        return _generate_screen_placeholder_svg(node_id, f"Display Offline ({type(e).__name__})"), "image/svg+xml"
    finally:
        lock.release()

def install_authorized_key(pubkey: str):
    if not pubkey or not pubkey.strip():
        return
    user_home = os.path.expanduser("~")
    ssh_dir = os.path.join(user_home, ".ssh")
    os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
    auth_file = os.path.join(ssh_dir, "authorized_keys")
    existing = ""
    if os.path.exists(auth_file):
        try:
            with open(auth_file, "r") as f:
                existing = f.read()
        except Exception as ex:
            sys.stderr.write(f"[knot-hub] Error reading authorized_keys: {ex}\n")
    if pubkey.strip() not in existing:
        try:
            with open(auth_file, "a") as f:
                if existing and not existing.endswith("\n"):
                    f.write("\n")
                f.write(f"{pubkey.strip()}\n")
            os.chmod(auth_file, 0o600)
        except Exception as e:
            sys.stderr.write(f"Failed to append to authorized_keys: {e}\n")


# =====================================================================
# Device-to-Device (D2D) Workspace Fabric Helpers & Subprocess Adapters
# =====================================================================

def sync_ssh_config(repo_root: str = REPO_ROOT) -> bool:
    """Synchronize Anchor ~/.ssh/config so enrolled nodes are immediately reachable.
    Enforces PSL Rule 1: zero silent error swallowing with structured stderr logging.
    """
    ssh_script = os.path.join(repo_root, "core/modules/ssh.sh")
    if not os.path.isfile(ssh_script):
        sys.stderr.write(f"[knot-hub] SSH sync script not found: {ssh_script}\n")
        return False
    try:
        proc = subprocess.run(
            ["bash", ssh_script, "sync-config"],
            capture_output=True,
            text=True,
            check=False
        )
        if proc.returncode != 0:
            sys.stderr.write(
                f"[knot-hub] SSH config sync exited with code {proc.returncode}: {proc.stderr.strip()}\n"
            )
            return False
        return True
    except Exception as exc:
        sys.stderr.write(f"[knot-hub] Error executing SSH config sync: {exc}\n")
        return False


def recompile_and_restart_deskflow(
    topo_path: str,
    nodes_dir: str,
    mode: str = "unlocked",
    restart_stripd: bool = False,
    repo_root: str = REPO_ROOT
) -> bool:
    """Compile deskflow configuration from topology & node manifests, then restart deskflow service.
    Enforces PSL Rule 1: zero silent error swallowing with structured stderr logging.
    """
    compile_script = os.path.join(repo_root, "core/modules/compile_deskflow.py")
    if not os.path.isfile(compile_script):
        sys.stderr.write(f"[knot-hub] Deskflow compile script not found: {compile_script}\n")
        return False

    user_home = os.path.expanduser("~")
    cfg_dir = os.path.join(user_home, ".config/Deskflow")
    os.makedirs(cfg_dir, exist_ok=True)
    conf_out = os.path.join(cfg_dir, "deskflow-server.conf")

    try:
        cmd = [
            sys.executable,
            compile_script,
            "--topology", topo_path,
            "--nodes-dir", nodes_dir,
            "--mode", mode,
            "--output", conf_out
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            sys.stderr.write(
                f"[knot-hub] Deskflow compilation failed (code {proc.returncode}): {proc.stderr.strip()}\n"
            )
            logger.error("Deskflow compilation failed: %s", proc.stderr.strip())
            return False

        # Restart knot-deskflow service
        restart_proc = subprocess.run(
            ["systemctl", "--user", "restart", "knot-deskflow.service"],
            capture_output=True,
            text=True,
            check=False
        )
        if restart_proc.returncode != 0:
            sys.stderr.write(
                f"[knot-hub] Restarting knot-deskflow.service failed (code {restart_proc.returncode}): {restart_proc.stderr.strip()}\n"
            )

        if restart_stripd:
            stripd_proc = subprocess.run(
                ["systemctl", "--user", "restart", "knot-stripd.service"],
                capture_output=True,
                text=True,
                check=False
            )
            if stripd_proc.returncode != 0:
                sys.stderr.write(
                    f"[knot-hub] Restarting knot-stripd.service failed (code {stripd_proc.returncode}): {stripd_proc.stderr.strip()}\n"
                )

        return True
    except Exception as exc:
        sys.stderr.write(f"[knot-hub] Error updating Deskflow configuration: {exc}\n")
        return False


class EnrollmentCoordinator:
    """Manages ephemeral cryptographic 6-digit OTP pairing and synchronous CLI rendezvous."""

    def __init__(self):
        self.sessions: dict[str, dict] = {}
        self.lock = threading.Lock()

    def create_invite(self, expires_in: int = 600, anchor_ip: str = "") -> dict:
        pin = f"{secrets.randbelow(900000) + 100000}"
        from core.hub.tls import ensure_hub_tls
        tls_info = ensure_hub_tls()
        fp_short = tls_info["fingerprint_short"]
        token = f"{pin}.{fp_short}"

        session = {
            "pin": pin,
            "token": token,
            "fingerprint": tls_info["fingerprint"],
            "fingerprint_short": fp_short,
            "anchor_ip": anchor_ip,
            "created_at": time.time(),
            "expires_at": time.time() + expires_in,
            "attempts": 0,
            "max_attempts": 5,
            "status": "waiting_join",
            "strand_request": None,
            "rendezvous_event": threading.Event(),
            "approval_event": threading.Event(),
            "approval_result": None
        }
        with self.lock:
            self.sessions[pin] = session
        return session

    def join_request(self, pin: str, strand_payload: dict) -> tuple[bool, str, Optional[dict]]:
        with self.lock:
            if pin not in self.sessions:
                return False, "Invalid or expired PIN", None
            session = self.sessions[pin]
            if time.time() > session["expires_at"]:
                del self.sessions[pin]
                return False, "PIN has expired", None
            if session["attempts"] >= session["max_attempts"]:
                del self.sessions[pin]
                return False, "Too many failed attempts; PIN locked", None
            
            session["strand_request"] = strand_payload
            session["status"] = "waiting_approval"
            session["rendezvous_event"].set()

        # Wait for Anchor approval (up to 120 seconds)
        approved = session["approval_event"].wait(timeout=120.0)
        if not approved:
            return False, "Join request timed out waiting for Anchor approval", None
        return True, "Approved", session["approval_result"]

    def wait_rendezvous(self, pin: str, timeout: float = 120.0) -> Optional[dict]:
        with self.lock:
            if pin not in self.sessions:
                return None
            session = self.sessions[pin]
        event = session["rendezvous_event"]
        if event.wait(timeout=timeout):
            return session["strand_request"]
        return None

    def approve_enrollment(self, pin: str, placement: str, anchor_meta: dict) -> tuple[bool, str]:
        with self.lock:
            if pin not in self.sessions:
                return False, "Session not found or expired"
            session = self.sessions[pin]
            session["placement"] = placement
            session["approval_result"] = {
                "status": "accepted",
                "placement": placement,
                **anchor_meta
            }
            session["status"] = "approved"
            session["approval_event"].set()
            return True, "Approved"


enrollment_coordinator = EnrollmentCoordinator()

_dist_bundle_cache: Optional[bytes] = None
_dist_bundle_cache_ts: float = 0
_dist_bundle_lock = threading.Lock()


def get_distribution_bundle() -> bytes:
    """Dynamically packages a clean, lightweight tarball of knot-mesh excluding heavy/build artifacts."""
    global _dist_bundle_cache, _dist_bundle_cache_ts
    now = time.time()
    with _dist_bundle_lock:
        if _dist_bundle_cache is not None and (now - _dist_bundle_cache_ts < 300):
            return _dist_bundle_cache

        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w:gz") as tar:
            def tar_filter(tarinfo):
                name = tarinfo.name
                for excl in ("/.git", "/node_modules", "/__pycache__", ".pyc", "/dist/knot-mesh.tar.gz", ".log"):
                    if excl in name:
                        return None
                return tarinfo

            for item in ("bin", "core", "systemd", "templates", "install.sh", "LICENSE", "README.md"):
                p = os.path.join(REPO_ROOT, item)
                if os.path.exists(p):
                    tar.add(p, arcname=f"knot-mesh/{item}", filter=tar_filter)

        data = buf.getvalue()
        _dist_bundle_cache = data
        _dist_bundle_cache_ts = now
        return data


def get_active_swarm_info() -> tuple[str, str]:
    """Returns (swarm_id, swarm_name) based on active runtime swarm profile."""
    active_swarm = os.environ.get("KNOT_ACTIVE_SWARM", "").strip()
    if not active_swarm:
        for path in ("/run/knot/active_swarm", os.path.expanduser("~/.local/state/knot/active_swarm")):
            if os.path.isfile(path):
                try:
                    with open(path, "r") as f:
                        content = f.read().strip()
                        if content and content != "none":
                            active_swarm = content
                            break
                except Exception as e:
                    logger.warning("Error reading %s: %s", path, e)
    if not active_swarm:
        swarms_dir = os.path.expanduser("~/.config/knot/swarms")
        if os.path.isdir(swarms_dir):
            for d in os.listdir(swarms_dir):
                if os.path.isfile(os.path.join(swarms_dir, d, "topology.json")):
                    active_swarm = d
                    break
    if not active_swarm:
        active_swarm = "home"

    swarm_name = f"{active_swarm.capitalize()} Swarm"
    for conf_dir in ("/etc/knot/swarms.d", os.path.expanduser("~/.config/knot/swarms"), os.path.expanduser(f"~/.config/knot/swarms/{active_swarm}")):
        conf_file = os.path.join(conf_dir, "swarm.conf") if os.path.basename(conf_dir) == active_swarm else os.path.join(conf_dir, f"{active_swarm}.conf")
        if os.path.isfile(conf_file):
            try:
                with open(conf_file, "r") as cf:
                    for line in cf:
                        if line.startswith("SWARM_NAME="):
                            name_val = line.split("=", 1)[1].strip().strip('"').strip("'")
                            if name_val:
                                swarm_name = name_val
                                break
            except Exception as e:
                logger.warning("Error reading %s: %s", conf_file, e)
    return active_swarm, swarm_name


def render_onboarding_html(swarm_name: str, anchor_host: str, anchor_port: str, token: str, pin: str, fp_short: str) -> str:
    """Renders modern dark-mode landing page for Magic URL browser visitors."""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Knot Swarm Onboarding — {swarm_name}</title>
  <style>
    :root {{
      --bg: #0b0f19;
      --card: #111827;
      --border: #1f293d;
      --primary: #06b6d4;
      --primary-hover: #0891b2;
      --accent: #10b981;
      --text: #f3f4f6;
      --muted: #9ca3af;
      --code-bg: #030712;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: var(--bg);
      color: var(--text);
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      padding: 20px;
    }}
    .card {{
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 16px;
      padding: 32px;
      max-width: 680px;
      width: 100%;
      box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.5), 0 8px 10px -6px rgba(0, 0, 0, 0.5);
    }}
    .badge {{
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: rgba(6, 182, 212, 0.1);
      color: var(--primary);
      border: 1px solid rgba(6, 182, 212, 0.25);
      border-radius: 9999px;
      padding: 4px 12px;
      font-size: 0.85rem;
      font-weight: 600;
      margin-bottom: 16px;
    }}
    .badge-dot {{
      width: 8px;
      height: 8px;
      background: var(--accent);
      border-radius: 50%;
      box-shadow: 0 0 8px var(--accent);
    }}
    h1 {{ font-size: 1.8rem; font-weight: 700; margin-bottom: 8px; color: #fff; }}
    p.subtitle {{ color: var(--muted); font-size: 0.95rem; margin-bottom: 24px; }}
    .grid {{ display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin-bottom: 24px; }}
    .stat {{ background: rgba(255, 255, 255, 0.03); border: 1px solid var(--border); border-radius: 10px; padding: 12px; }}
    .stat-label {{ font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; color: var(--muted); margin-bottom: 4px; }}
    .stat-val {{ font-size: 1.05rem; font-weight: 600; font-family: monospace; color: var(--primary); word-break: break-all; }}
    .command-box {{
      background: var(--code-bg);
      border: 1px solid var(--border);
      border-radius: 12px;
      padding: 16px;
      position: relative;
      margin-bottom: 24px;
    }}
    .command-text {{
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.95rem;
      color: #38bdf8;
      word-break: break-all;
      line-height: 1.5;
    }}
    .copy-btn {{
      margin-top: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      background: var(--primary);
      color: #000;
      font-weight: 600;
      border: none;
      border-radius: 8px;
      padding: 10px 16px;
      cursor: pointer;
      font-size: 0.95rem;
      transition: background 0.2s;
    }}
    .copy-btn:hover {{ background: var(--primary-hover); }}
    .steps {{ list-style: none; counter-reset: step-counter; }}
    .steps li {{
      position: relative;
      padding-left: 36px;
      margin-bottom: 12px;
      color: var(--muted);
      font-size: 0.9rem;
      line-height: 1.4;
    }}
    .steps li::before {{
      content: counter(step-counter);
      counter-increment: step-counter;
      position: absolute;
      left: 0;
      top: 0;
      width: 24px;
      height: 24px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid var(--border);
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.75rem;
      font-weight: 600;
      color: var(--primary);
    }}
    .footer {{ text-align: center; margin-top: 24px; font-size: 0.8rem; color: var(--muted); }}
  </style>
</head>
<body>
  <div class="card">
    <div class="badge"><span class="badge-dot"></span> Knot Swarm Pairing Active</div>
    <h1>Magic Strand Onboarding</h1>
    <p class="subtitle">Enroll this secondary device into the <strong>{swarm_name}</strong> mesh with zero prior configuration.</p>
    
    <div class="grid">
      <div class="stat">
        <div class="stat-label">Anchor Node</div>
        <div class="stat-val">{anchor_host}</div>
      </div>
      <div class="stat">
        <div class="stat-label">Pairing PIN</div>
        <div class="stat-val">{pin}</div>
      </div>
      <div class="stat">
        <div class="stat-label">TLS Fingerprint</div>
        <div class="stat-val">{fp_short}...</div>
      </div>
    </div>

    <div class="command-box">
      <div class="command-text" id="cmd">curl -kfsSL https://{anchor_host}:{anchor_port}/join/{token} | bash</div>
      <button class="copy-btn" id="copy-btn" onclick="copyCmd()">
        <span>Copy One-Liner Command</span>
      </button>
    </div>

    <ul class="steps">
      <li>Open any terminal on your secondary laptop or handheld device.</li>
      <li>Paste and run the one-liner command above. The installer will download directly over local LAN.</li>
      <li>Cryptographic TLS pinning verifies the Anchor and completes spatial pairing automatically.</li>
    </ul>
  </div>
  <div class="footer">Knot Mesh v1.0 • Distributed Workspace Coordination Engine</div>

  <script>
    function copyCmd() {{
      const text = document.getElementById('cmd').innerText;
      navigator.clipboard.writeText(text).then(() => {{
        const btn = document.getElementById('copy-btn');
        btn.innerHTML = '<span>Copied to Clipboard! ✓</span>';
        btn.style.background = '#10b981';
        setTimeout(() => {{
          btn.innerHTML = '<span>Copy One-Liner Command</span>';
          btn.style.background = '#06b6d4';
        }}, 2500);
      }});
    }}
  </script>
</body>
</html>"""


def render_bootstrap_script(swarm_name: str, anchor_host: str, anchor_port: str, token: str, pin: str, fp_short: str) -> str:
    """Renders dynamic, self-enrolling bash script for curl | bash execution."""
    return f"""#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Zero-Setup Strand Onboarding Bootstrap
# Swarm: {swarm_name} | Anchor: {anchor_host}:{anchor_port}

C_RESET=$'\\033[0m'
C_BOLD=$'\\033[1m'
C_GREEN=$'\\033[1;32m'
C_CYAN=$'\\033[1;36m'
C_YELLOW=$'\\033[1;33m'
C_RED=$'\\033[1;31m'
C_DIM=$'\\033[2m'

ANCHOR_HOST="{anchor_host}"
ANCHOR_PORT="{anchor_port}"
TOKEN="{token}"
PIN="{pin}"
FP_SHORT="{fp_short}"
INSTALL_DIR="$HOME/.local/share/knot-mesh"
BIN_DIR="$HOME/.local/bin"

echo -e "${{C_CYAN}}${{C_BOLD}}"
cat << 'EOF_BANNER'
  ██╗  ██╗███╗   ██╗ ██████╗ ████████╗   ███╗   ███╗███████╗███████╗██╗  ██╗
  ██║ ██╔╝████╗  ██║██╔═══██╗╚══██╔══╝   ████╗ ████║██╔════╝██╔════╝██║  ██║
  █████═╝ ██╔██╗ ██║██║   ██║   ██║█████╗██╔████╔██║█████╗  ███████╗███████║
  ██╔═██╗ ██║╚██╗██║██║   ██║   ██║╚════╝██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║
  ██║ ╚██╗██║ ╚████║╚██████╔╝   ██║      ██║ ╚═╝ ██║███████╗███████║██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝    ╚═╝      ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝
EOF_BANNER
echo -e "${{C_RESET}}${{C_DIM}}         Zero-Setup Strand Onboarding for Arch Linux / KDE Plasma 6 Wayland${{C_RESET}}\\n"
echo -e "${{C_CYAN}}[•] Initiating onboarding to Anchor at ${{C_BOLD}}${{ANCHOR_HOST}}:${{ANCHOR_PORT}}${{C_RESET}}..."

# Step 1: Cryptographic TLS Fingerprint Pinning
echo -e "${{C_CYAN}}[•] Cryptographically verifying Anchor TLS certificate...${{C_RESET}}"
python3 -c '
import sys, socket, ssl, hashlib

host = sys.argv[1]
port = int(sys.argv[2])
expected_fp = sys.argv[3].lower()

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

try:
    with socket.create_connection((host, port), timeout=10) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as ssock:
            der = ssock.getpeercert(binary_form=True)
            if not der:
                print("Error: Could not retrieve peer certificate", file=sys.stderr)
                sys.exit(1)
            fp = hashlib.sha256(der).hexdigest().lower()
            if not fp.startswith(expected_fp):
                print("SECURITY ALERT: Certificate mismatch! Expected " + expected_fp + ", received " + fp, file=sys.stderr)
                sys.exit(1)
            print("[✓] Anchor TLS verified: " + fp[:16] + "...")
except Exception as e:
    print("TLS verification failed: " + str(e), file=sys.stderr)
    sys.exit(1)
' "$ANCHOR_HOST" "$ANCHOR_PORT" "$FP_SHORT"

# Step 2: Download distribution bundle directly from Anchor over LAN
echo -e "${{C_CYAN}}[•] Downloading Knot Mesh bundle directly from Anchor over LAN...${{C_RESET}}"
mkdir -p "$INSTALL_DIR"
curl -kfsSL "https://${{ANCHOR_HOST}}:${{ANCHOR_PORT}}/dist/knot-mesh.tar.gz" | tar -xzf - -C "$(dirname "$INSTALL_DIR")"

# Step 3: Setup command symlinks and permissions
echo -e "${{C_CYAN}}[•] Configuring Knot binaries and permissions...${{C_RESET}}"
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/bin/knot" "$BIN_DIR/knot"
ln -sf "$INSTALL_DIR/bin/knot-installer" "$BIN_DIR/knot-installer"
ln -sf "$INSTALL_DIR/bin/knot-autounlock" "$BIN_DIR/knot-autounlock"
ln -sf "$INSTALL_DIR/bin/knot-agent" "$BIN_DIR/knot-agent"
ln -sf "$INSTALL_DIR/bin/knot-stripd" "$BIN_DIR/knot-stripd"
chmod +x "$INSTALL_DIR/bin/knot" "$INSTALL_DIR/bin/knot-installer" "$INSTALL_DIR/bin/knot-autounlock" "$INSTALL_DIR/bin/knot-agent" "$INSTALL_DIR/bin/knot-stripd"
chmod +x "$INSTALL_DIR/core/installer/display.sh" "$INSTALL_DIR/core/installer/enroll.py"

export PATH="$BIN_DIR:$PATH"

# Pre-authenticate sudo credentials if available so background system setup succeeds seamlessly
if command -v sudo >/dev/null; then
  local sudo_test_out=""
  if ! sudo_test_out="$(sudo -n true 2>&1)"; then
    if [ -r /dev/tty ]; then
      echo -e "${{C_CYAN}}[•] Root privileges requested to configure OpenSSH and system services...${{C_RESET}}"
      sudo -v </dev/tty || echo -e "${{C_YELLOW}}[!] Notice: Sudo authentication cancelled. Continuing with user-level setup...${{C_RESET}}"
    fi
  fi
fi

# Step 4: Execute enrollment handshake
echo -e "${{C_CYAN}}[•] Submitting Strand enrollment to Anchor...${{C_RESET}}"
"$BIN_DIR/knot-installer" join "${{ANCHOR_HOST}}:${{ANCHOR_PORT}}" "$TOKEN" --auto

echo -e "\\n${{C_GREEN}}${{C_BOLD}}[✓] Success! This device is now onboarded and paired with the Swarm Anchor.${{C_RESET}}\\n"
"""


class Database:
    def __init__(self, db_path: str):
        self.db_path = db_path
        os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
        self._local = threading.local()
        self._node_activities: dict[str, dict] = {}
        self._activities_lock = threading.Lock()
        self._init_schema()

    def set_node_activity(self, node_id: str, activity: dict):
        with self._activities_lock:
            self._node_activities[node_id] = activity

    def get_node_activity(self, node_id: str) -> dict:
        with self._activities_lock:
            return self._node_activities.get(node_id, {})

    def get_all_node_activities(self) -> dict[str, dict]:
        with self._activities_lock:
            return dict(self._node_activities)

    def get_connection(self) -> sqlite3.Connection:
        if not hasattr(self._local, "conn"):
            conn = sqlite3.connect(self.db_path, check_same_thread=False)
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            conn.row_factory = sqlite3.Row
            self._local.conn = conn
        return self._local.conn

    def _init_schema(self):
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA journal_mode=WAL;")
        with conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    prompt TEXT NOT NULL,
                    target_plane TEXT NOT NULL DEFAULT 'any',
                    status TEXT NOT NULL DEFAULT 'QUEUED',
                    claimed_by TEXT,
                    claimed_at INTEGER,
                    lease_ttl_sec INTEGER DEFAULT 60,
                    heartbeat_at INTEGER,
                    result TEXT,
                    session_id TEXT,
                    duration_seconds REAL,
                    tokens_used INTEGER,
                    retry_count INTEGER DEFAULT 0,
                    batch_id TEXT,
                    parent_id TEXT,
                    dependencies TEXT DEFAULT '[]',
                    meta TEXT DEFAULT '{}',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_target ON tasks(target_plane);")

            # Idempotent column migrations for existing databases
            cur = conn.cursor()
            cur.execute("PRAGMA table_info(tasks)")
            existing_task_cols = {row[1] for row in cur.fetchall()}
            task_migrations = {
                "batch_id": "TEXT",
                "parent_id": "TEXT",
                "dependencies": "TEXT DEFAULT '[]'",
                "meta": "TEXT DEFAULT '{}'"
            }
            for col_name, col_def in task_migrations.items():
                if col_name not in existing_task_cols:
                    conn.execute(f"ALTER TABLE tasks ADD COLUMN {col_name} {col_def}")

            conn.execute("CREATE INDEX IF NOT EXISTS idx_tasks_batch ON tasks(batch_id);")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS nodes (
                    id TEXT PRIMARY KEY,
                    hostname TEXT NOT NULL,
                    capabilities TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'ONLINE',
                    last_heartbeat INTEGER NOT NULL,
                    agy_version TEXT,
                    agy_auth TEXT,
                    quota_5h_gemini REAL DEFAULT 1.0,
                    quota_weekly_gemini REAL DEFAULT 1.0,
                    quota_5h_3p REAL DEFAULT 1.0,
                    quota_weekly_3p REAL DEFAULT 1.0,
                    quota_data TEXT DEFAULT '{}',
                    quota_updated_at INTEGER DEFAULT 0,
                    power_state TEXT DEFAULT '{}',
                    ip TEXT DEFAULT ''
                );
            """)

            cur.execute("PRAGMA table_info(nodes)")
            existing_node_cols = {row[1] for row in cur.fetchall()}
            if "power_state" not in existing_node_cols:
                conn.execute("ALTER TABLE nodes ADD COLUMN power_state TEXT DEFAULT '{}'")
            if "ip" not in existing_node_cols:
                conn.execute("ALTER TABLE nodes ADD COLUMN ip TEXT DEFAULT ''")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    conv_id TEXT NOT NULL DEFAULT 'main',
                    sender TEXT NOT NULL,
                    mentions TEXT DEFAULT '[]',
                    content TEXT NOT NULL,
                    artifacts TEXT DEFAULT '[]',
                    reply_to TEXT,
                    meta TEXT DEFAULT '{}',
                    created_at INTEGER NOT NULL
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conv_id);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_time ON messages(created_at);")

            cur = conn.cursor()
            cur.execute("PRAGMA table_info(messages)")
            existing_msg_cols = {row[1] for row in cur.fetchall()}
            if "meta" not in existing_msg_cols:
                conn.execute("ALTER TABLE messages ADD COLUMN meta TEXT DEFAULT '{}'")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS artifact_leases (
                    name TEXT PRIMARY KEY,
                    state TEXT NOT NULL DEFAULT 'DRAFTING',
                    locked_by TEXT,
                    lease_ttl_sec INTEGER DEFAULT 120,
                    locked_at INTEGER,
                    expires_at INTEGER,
                    meta TEXT DEFAULT '{}',
                    updated_at INTEGER NOT NULL
                );
            """)

            conn.execute("""
                CREATE TABLE IF NOT EXISTS projects (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT DEFAULT '',
                    folders TEXT DEFAULT '[]',
                    default_channel TEXT DEFAULT 'main',
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
            """)

            conn.execute("""
                CREATE TABLE IF NOT EXISTS conversations (
                    id TEXT PRIMARY KEY,
                    project_id TEXT NOT NULL DEFAULT 'knot',
                    title TEXT NOT NULL,
                    description TEXT DEFAULT '',
                    created_by TEXT NOT NULL DEFAULT 'human',
                    is_archived INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_conversations_proj ON conversations(project_id);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at);")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS node_conversation_sessions (
                    conv_id TEXT NOT NULL,
                    node_id TEXT NOT NULL,
                    agy_session_id TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (conv_id, node_id)
                );
            """)

            cur.execute("PRAGMA table_info(conversations)")
            existing_conv_cols = {row[1] for row in cur.fetchall()}
            if "selected_model" not in existing_conv_cols:
                conn.execute("ALTER TABLE conversations ADD COLUMN selected_model TEXT DEFAULT ''")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS conversation_node_models (
                    conv_id TEXT NOT NULL,
                    node_id TEXT NOT NULL,
                    model TEXT NOT NULL,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (conv_id, node_id)
                );
            """)

            cur.execute("PRAGMA table_info(nodes)")
            existing_node_cols = {row[1] for row in cur.fetchall()}
            node_migrations = {
                "quota_5h_gemini": "REAL DEFAULT 1.0",
                "quota_weekly_gemini": "REAL DEFAULT 1.0",
                "quota_5h_3p": "REAL DEFAULT 1.0",
                "quota_weekly_3p": "REAL DEFAULT 1.0",
                "quota_data": "TEXT DEFAULT '{}'",
                "quota_updated_at": "INTEGER DEFAULT 0"
            }
            for col_name, col_def in node_migrations.items():
                if col_name not in existing_node_cols:
                    conn.execute(f"ALTER TABLE nodes ADD COLUMN {col_name} {col_def}")

            conn.execute("""
                CREATE TABLE IF NOT EXISTS node_models (
                    node_id TEXT PRIMARY KEY,
                    model TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                );
            """)

            conn.execute("""
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at INTEGER NOT NULL
                );
            """)

            conn.execute("""
                CREATE TABLE IF NOT EXISTS council_threads (
                    id TEXT PRIMARY KEY,
                    run_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    category TEXT DEFAULT 'general',
                    url TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_council_threads_run ON council_threads(run_id);")
            conn.execute("""
                CREATE TABLE IF NOT EXISTS council_messages (
                    id TEXT PRIMARY KEY,
                    thread_id TEXT NOT NULL,
                    run_id TEXT NOT NULL,
                    node_id TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'PROGRESS',
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_council_msgs_thread ON council_messages(thread_id);")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_council_msgs_time ON council_messages(created_at);")

            self.sync_native_antigravity_projects(conn)

        conn.close()

    # -------------------------------------------------------------
    # Settings & Model Management
    # -------------------------------------------------------------

    def get_setting(self, key: str, default: str = "") -> str:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT value FROM settings WHERE key = ?", (key,))
        row = cur.fetchone()
        return row["value"] if row else default

    def set_setting(self, key: str, value: str):
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            conn.execute("""
                INSERT INTO settings (key, value, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET
                    value = excluded.value,
                    updated_at = excluded.updated_at
            """, (key, value, now))

    def get_node_model(self, node_id: str) -> str:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT model FROM node_models WHERE node_id = ?", (node_id,))
        row = cur.fetchone()
        if row and row["model"]:
            return row["model"]
        return self.get_setting("default_swarm_model", DEFAULT_SWARM_MODEL)

    def set_node_model(self, node_id: str, model: str):
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            conn.execute("""
                INSERT INTO node_models (node_id, model, updated_at)
                VALUES (?, ?, ?)
                ON CONFLICT(node_id) DO UPDATE SET
                    model = excluded.model,
                    updated_at = excluded.updated_at
            """, (node_id, model, now))

    def get_all_node_models(self) -> dict[str, str]:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT node_id, model FROM node_models")
        return {row["node_id"]: row["model"] for row in cur.fetchall()}

    def set_all_node_models(self, model: str):
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            self.set_setting("default_swarm_model", model)
            cur = conn.cursor()
            cur.execute("SELECT id FROM nodes")
            for row in cur.fetchall():
                conn.execute("""
                    INSERT INTO node_models (node_id, model, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(node_id) DO UPDATE SET
                        model = excluded.model,
                        updated_at = excluded.updated_at
                """, (row["id"], model, now))

    # -------------------------------------------------------------
    # Task Operations & DAG Resolution
    # -------------------------------------------------------------

    def post_task(self, title: str, prompt: str, target_plane: str = "any",
                  lease_ttl: int = DEFAULT_LEASE_TTL, batch_id: str | None = None,
                  parent_id: str | None = None, dependencies: list[str] | None = None,
                  meta: dict | None = None) -> dict:
        task_id = str(uuid.uuid4())
        now = int(time.time())
        deps_list = dependencies or []
        deps_json = json.dumps(deps_list)
        meta_json = json.dumps(meta or {})

        # Evaluate initial DAG state: if dependencies are provided, verify if all are completed
        initial_status = "QUEUED"
        if deps_list:
            conn = self.get_connection()
            cur = conn.cursor()
            q_marks = ",".join("?" for _ in deps_list)
            cur.execute(f"SELECT COUNT(*) as c FROM tasks WHERE id IN ({q_marks}) AND status = 'COMPLETED'", deps_list)
            row = cur.fetchone()
            if not row or row["c"] < len(deps_list):
                initial_status = "BLOCKED_ON_DEPS"

        conn = self.get_connection()
        with conn:
            conn.execute("""
                INSERT INTO tasks (
                    id, title, prompt, target_plane, status, lease_ttl_sec,
                    batch_id, parent_id, dependencies, meta, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (task_id, title, prompt, target_plane, initial_status, lease_ttl,
                  batch_id, parent_id, deps_json, meta_json, now, now))

        task = self.get_task(task_id)
        broadcast_event("task_created", task)
        return task

    def post_fanout(self, tasks: list[dict], barrier_task: dict | None = None, batch_id: str | None = None) -> dict:
        """
        Divide-and-Conquer: Posts a batch of parallel subtasks and an optional barrier task
        that is held in BLOCKED_ON_DEPS until all subtasks finish.
        """
        batch_id = batch_id or str(uuid.uuid4())
        created_subtasks = []
        subtask_ids = []

        for tspec in tasks:
            title = tspec.get("title") or "Fan-out Subtask"
            prompt = tspec.get("prompt", "")
            plane = tspec.get("target_plane", "any")
            ttl = int(tspec.get("lease_ttl", DEFAULT_LEASE_TTL))
            meta = tspec.get("meta", {})
            st = self.post_task(
                title=title,
                prompt=prompt,
                target_plane=plane,
                lease_ttl=ttl,
                batch_id=batch_id,
                meta=meta
            )
            created_subtasks.append(st)
            subtask_ids.append(st["id"])

        created_barrier = None
        if barrier_task:
            b_title = barrier_task.get("title") or "Barrier Reducer Task"
            b_prompt = barrier_task.get("prompt", "Synthesize and verify subtask results.")
            b_plane = barrier_task.get("target_plane", "any")
            b_ttl = int(barrier_task.get("lease_ttl", DEFAULT_LEASE_TTL))
            b_meta = barrier_task.get("meta", {})
            created_barrier = self.post_task(
                title=b_title,
                prompt=b_prompt,
                target_plane=b_plane,
                lease_ttl=b_ttl,
                batch_id=batch_id,
                dependencies=subtask_ids,
                meta=b_meta
            )

        return {
            "batch_id": batch_id,
            "subtasks": created_subtasks,
            "barrier_task": created_barrier
        }

    def get_task(self, task_id: str) -> dict | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM tasks WHERE id = ? OR id LIKE ? ORDER BY created_at DESC LIMIT 1", (task_id, f"{task_id}%"))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        try:
            d["dependencies"] = json.loads(d.get("dependencies") or "[]")
        except Exception:
            d["dependencies"] = []
        try:
            d["meta"] = json.loads(d.get("meta") or "{}")
        except Exception:
            d["meta"] = {}
        return d

    def list_tasks(self, status: str | None = None, batch_id: str | None = None, limit: int = 50) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        conditions = []
        params = []
        if status:
            conditions.append("status = ?")
            params.append(status)
        if batch_id:
            conditions.append("batch_id = ?")
            params.append(batch_id)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
        query = f"SELECT * FROM tasks {where} ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cur.execute(query, params)
        rows = []
        for r in cur.fetchall():
            d = dict(r)
            try:
                d["dependencies"] = json.loads(d.get("dependencies") or "[]")
            except Exception:
                d["dependencies"] = []
            try:
                d["meta"] = json.loads(d.get("meta") or "{}")
            except Exception:
                d["meta"] = {}
            rows.append(d)
        return rows

    def get_batch_status(self, batch_id: str) -> dict:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM tasks WHERE batch_id = ? ORDER BY created_at ASC", (batch_id,))
        rows = []
        for r in cur.fetchall():
            d = dict(r)
            try:
                d["dependencies"] = json.loads(d.get("dependencies") or "[]")
            except Exception:
                d["dependencies"] = []
            try:
                d["meta"] = json.loads(d.get("meta") or "{}")
            except Exception:
                d["meta"] = {}
            rows.append(d)

        total = len(rows)
        completed = sum(1 for r in rows if r["status"] == "COMPLETED")
        running = sum(1 for r in rows if r["status"] in ("CLAIMED", "RUNNING"))
        queued = sum(1 for r in rows if r["status"] == "QUEUED")
        blocked = sum(1 for r in rows if r["status"] == "BLOCKED_ON_DEPS")
        failed = sum(1 for r in rows if r["status"] in ("FAILED", "ERROR", "BLOCKED_FAILED", "TIMEOUT"))
        is_done = (completed + failed == total) if total > 0 else False

        return {
            "batch_id": batch_id,
            "total_tasks": total,
            "completed": completed,
            "running": running,
            "queued": queued,
            "blocked_on_deps": blocked,
            "failed": failed,
            "is_done": is_done,
            "tasks": rows
        }

    def claim_task(self, node_id: str, capabilities: list[str]) -> dict | None:
        conn = self.get_connection()
        now = int(time.time())

        # Quota-aware load balancing:
        effective_caps = list(capabilities)
        cur = conn.cursor()
        cur.execute("SELECT quota_5h_gemini FROM nodes WHERE id = ?", (node_id,))
        node_row = cur.fetchone()
        my_quota = node_row["quota_5h_gemini"] if node_row else None
        if my_quota is not None and my_quota < 0.15:
            cur.execute("""
                SELECT COUNT(*) as c FROM nodes
                WHERE id != ? AND (status = 'ONLINE' OR last_heartbeat > ?) AND quota_5h_gemini >= ? + 0.10
            """, (node_id, now - 30, my_quota))
            healthier = cur.fetchone()
            if healthier and healthier["c"] > 0:
                effective_caps = [c for c in effective_caps if c not in ("any", "general")]

        # Atomically find and claim the oldest QUEUED task matching node capabilities
        with conn:
            cur = conn.cursor()
            placeholders = [node_id] + effective_caps
            if "any" in effective_caps and "any" not in placeholders:
                placeholders.append("any")
            placeholders = list(dict.fromkeys(placeholders))
            q_marks = ",".join("?" for _ in placeholders)
            query = f"""
                SELECT id, lease_ttl_sec FROM tasks
                WHERE status = 'QUEUED' AND target_plane IN ({q_marks})
                ORDER BY created_at ASC LIMIT 1
            """
            cur.execute(query, placeholders)
            row = cur.fetchone()
            if not row:
                return None

            task_id = row["id"]
            lease_ttl = row["lease_ttl_sec"] or DEFAULT_LEASE_TTL
            conn.execute("""
                UPDATE tasks
                SET status = 'CLAIMED', claimed_by = ?, claimed_at = ?, heartbeat_at = ?, updated_at = ?
                WHERE id = ? AND status = 'QUEUED'
            """, (node_id, now, now, now, task_id))

        task = self.get_task(task_id)
        if task and task.get("claimed_by") == node_id:
            broadcast_event("task_claimed", task)
            return task
        return None

    def task_heartbeat(self, task_id: str, node_id: str) -> bool:
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                UPDATE tasks
                SET heartbeat_at = ?, status = 'RUNNING', updated_at = ?
                WHERE id = ? AND claimed_by = ? AND status IN ('CLAIMED', 'RUNNING')
            """, (now, now, task_id, node_id))
            return cur.rowcount > 0

    def complete_task(self, task_id: str, node_id: str, status: str, result: str,
                      session_id: str = "", duration_seconds: float = 0.0, tokens_used: int = 0) -> dict | None:
        now = int(time.time())
        if status in ("SUCCESS", "COMPLETED"):
            status = "COMPLETED"
        conn = self.get_connection()
        with conn:
            conn.execute("""
                UPDATE tasks
                SET status = ?, result = ?, session_id = ?, duration_seconds = ?, tokens_used = ?, updated_at = ?
                WHERE id = ? AND claimed_by = ?
            """, (status, result, session_id, duration_seconds, tokens_used, now, task_id, node_id))

        task = self.get_task(task_id)
        if task:
            broadcast_event("task_finished", task)

        # Trigger DAG dependency resolution or failure propagation
        if status == "COMPLETED":
            self._resolve_dependencies(task_id)
        elif status in ("FAILED", "ERROR", "TIMEOUT"):
            self._fail_dependent_tasks(task_id, status)

        return task

    def _fail_dependent_tasks(self, failed_task_id: str, fail_status: str):
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT id, dependencies FROM tasks WHERE status = 'BLOCKED_ON_DEPS'")
            for row in cur.fetchall():
                try:
                    deps = json.loads(row["dependencies"] or "[]")
                except Exception:
                    deps = []
                if failed_task_id in deps:
                    err_msg = f"Prerequisite task {failed_task_id[:8]} failed with status {fail_status}."
                    conn.execute("""
                        UPDATE tasks
                        SET status = 'BLOCKED_FAILED', result = ?, updated_at = ?
                        WHERE id = ?
                    """, (err_msg, now, row["id"]))
                    t = self.get_task(row["id"])
                    if t:
                        broadcast_event("task_blocked_failed", t)

    def _resolve_dependencies(self, completed_task_id: str):
        """
        Evaluates tasks in BLOCKED_ON_DEPS. If all prerequisite tasks have reached COMPLETED,
        injects a markdown summary table into the reducer prompt and unblocks the task to QUEUED.
        """
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM tasks WHERE status = 'BLOCKED_ON_DEPS'")
            blocked_tasks = [dict(r) for r in cur.fetchall()]

            for bt in blocked_tasks:
                try:
                    dep_ids = json.loads(bt.get("dependencies") or "[]")
                except Exception:
                    dep_ids = []

                if not dep_ids:
                    continue

                q_marks = ",".join("?" for _ in dep_ids)
                cur.execute(f"SELECT id, title, target_plane, status, result FROM tasks WHERE id IN ({q_marks})", dep_ids)
                dep_rows = [dict(r) for r in cur.fetchall()]

                # Check if any prerequisite failed
                failed = [r for r in dep_rows if r["status"] in ("FAILED", "ERROR", "BLOCKED_FAILED", "TIMEOUT")]
                if failed:
                    f_id = failed[0]["id"]
                    f_st = failed[0]["status"]
                    err_msg = f"Prerequisite task {f_id[:8]} failed ({f_st})."
                    conn.execute("""
                        UPDATE tasks SET status = 'BLOCKED_FAILED', result = ?, updated_at = ? WHERE id = ?
                    """, (err_msg, now, bt["id"]))
                    t = self.get_task(bt["id"])
                    if t:
                        broadcast_event("task_blocked_failed", t)
                    continue

                # Check if all prerequisites completed
                completed = [r for r in dep_rows if r["status"] == "COMPLETED"]
                if len(completed) == len(dep_ids) and len(dep_ids) > 0:
                    # Construct Markdown summary matrix & detailed traces
                    matrix = [
                        "\n\n---",
                        "### [Prerequisite Subtasks Matrix]",
                        "| Subtask ID | Title | Plane | Status | Output Summary |",
                        "| :--- | :--- | :--- | :--- | :--- |"
                    ]
                    for dr in dep_rows:
                        raw_res = (dr.get("result") or "").strip()
                        summary = raw_res.replace("\n", " ")
                        if len(summary) > 100:
                            summary = summary[:97] + "..."
                        summary = summary.replace("|", "\\|")
                        matrix.append(f"| `{dr['id'][:8]}` | {dr.get('title', 'Subtask')} | `{dr.get('target_plane', 'any')}` | {dr.get('status')} | {summary} |")

                    matrix.append("\n#### Detailed Subtask Traces:")
                    for dr in dep_rows:
                        matrix.append(
                            f"\n<details><summary>Subtask {dr['id'][:8]}: {dr.get('title')} ({dr.get('target_plane')})</summary>\n\n```\n{dr.get('result') or '(No output)'}\n```\n</details>"
                        )

                    new_prompt = bt["prompt"] + "\n" + "\n".join(matrix)
                    conn.execute("""
                        UPDATE tasks SET status = 'QUEUED', prompt = ?, updated_at = ? WHERE id = ?
                    """, (new_prompt, now, bt["id"]))
                    unblocked = self.get_task(bt["id"])
                    if unblocked:
                        broadcast_event("task_unblocked", unblocked)

    # -------------------------------------------------------------
    # Multi-Project & Native Antigravity Workspaces
    # -------------------------------------------------------------

    @staticmethod
    def normalize_home_path(path_or_uri: str, target_home: str | None = None) -> str:
        """
        Normalizes paths between different user home directories.
        Preserves file:// prefix if present.
        """
        if not path_or_uri:
            return path_or_uri
        home = target_home or os.path.expanduser("~")
        prefix = ""
        target = path_or_uri
        if target.startswith("file://"):
            prefix = "file://"
            target = target[7:]

        # Replace /home/<username> with target home
        if target.startswith("/home/"):
            parts = target.split("/", 3)
            if len(parts) >= 3:
                rel = parts[3] if len(parts) > 3 else ""
                target = os.path.join(home, rel) if rel else home
        elif target.startswith("~/"):
            target = os.path.join(home, target[2:])

        return f"{prefix}{target}"

    def sync_native_antigravity_projects(self, conn=None):
        """
        Scans native Antigravity project definitions in ~/.gemini/config/projects/*.json
        and synchronizes them into the Knot SQLite projects registry.
        """
        close_at_end = False
        if conn is None:
            conn = self.get_connection()
            close_at_end = True

        projects_dir = os.path.expanduser("~/.gemini/config/projects")
        now = int(time.time())
        knot_root = KNOT_ROOT
        knot_folder_uri = f"file://{knot_root}/"

        if os.path.isdir(projects_dir):
            for f in glob.glob(os.path.join(projects_dir, "*.json")):
                try:
                    with open(f, "r", encoding="utf-8") as fp:
                        pdata = json.load(fp)
                    pid = pdata.get("id") or os.path.basename(f)[:-5]
                    pname = pdata.get("name") or pid
                    if pid in ("default-cli-project", "outside-of-project"):
                        continue

                    resources = pdata.get("projectResources", {}).get("resources", [])
                    folders = []
                    for r in resources:
                        furi = r.get("gitFolder", {}).get("folderUri") or r.get("folderUri")
                        if furi:
                            norm_furi = self.normalize_home_path(furi)
                            if norm_furi not in folders:
                                folders.append(norm_furi)

                    folders_json = json.dumps(folders)
                    with conn:
                        conn.execute("""
                            INSERT INTO projects (id, name, description, folders, default_channel, created_at, updated_at)
                            VALUES (?, ?, ?, ?, 'main', ?, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                name = excluded.name,
                                folders = excluded.folders,
                                updated_at = excluded.updated_at
                        """, (pid, pname, f"Native Antigravity project ({len(folders)} folders)", folders_json, now, now))

                        main_conv_id = f"{pid}-main" if pid != "1da6ae24-e267-49d2-8aac-44bdf83d7d0e" and pid != "knot" else "main"
                        conn.execute("""
                            INSERT OR IGNORE INTO conversations (id, project_id, title, description, created_by, created_at, updated_at)
                            VALUES (?, ?, 'Main Swarm', 'Primary swarm coordination channel', 'system', ?, ?)
                        """, (main_conv_id, pid, now, now))
                except Exception as e:
                    sys.stderr.write(f"Notice: [hub] Failed to register project conversation {pid}: {e}\n")

        with conn:
            cur = conn.cursor()
            cur.execute("SELECT id FROM projects WHERE id = 'knot' OR name = 'knot'")
            if not cur.fetchone():
                conn.execute("""
                    INSERT OR IGNORE INTO projects (id, name, description, folders, default_channel, created_at, updated_at)
                    VALUES ('knot', 'knot', 'Knot Swarm Core repository', ?, 'main', ?, ?)
                """, (json.dumps([knot_folder_uri]), now, now))

            conn.execute("""
                INSERT OR IGNORE INTO conversations (id, project_id, title, description, created_by, created_at, updated_at)
                VALUES ('main', 'knot', 'Main Swarm', 'Primary swarm coordination channel', 'system', ?, ?)
            """, (now, now))

            conn.execute("""
                INSERT OR IGNORE INTO conversations (id, project_id, title, description, created_by, created_at, updated_at)
                SELECT DISTINCT conv_id, 'knot', '#' || conv_id, 'Migrated conversation', 'system', MIN(created_at), MAX(created_at)
                FROM messages GROUP BY conv_id
            """)

        if close_at_end:
            conn.close()

    def list_projects(self) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM projects ORDER BY updated_at DESC")
        rows = [dict(r) for r in cur.fetchall()]
        for r in rows:
            try:
                r["folders"] = json.loads(r.get("folders") or "[]")
            except Exception:
                r["folders"] = []
        return rows

    def get_project(self, project_id: str) -> dict | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM projects WHERE id = ? OR name = ?", (project_id, project_id))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        try:
            d["folders"] = json.loads(d.get("folders") or "[]")
        except Exception:
            d["folders"] = []
        return d

    def create_project(self, project_id: str, name: str, description: str = "",
                       folders: list[str] | None = None) -> dict:
        now = int(time.time())
        folders_list = folders or []
        folders_json = json.dumps(folders_list)
        conn = self.get_connection()
        with conn:
            conn.execute("""
                INSERT INTO projects (id, name, description, folders, default_channel, created_at, updated_at)
                VALUES (?, ?, ?, ?, 'main', ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    description = excluded.description,
                    folders = excluded.folders,
                    updated_at = excluded.updated_at
            """, (project_id, name, description, folders_json, now, now))

            main_conv_id = f"{project_id}-main" if project_id != "knot" else "main"
            conn.execute("""
                INSERT OR IGNORE INTO conversations (id, project_id, title, description, created_by, created_at, updated_at)
                VALUES (?, ?, 'Main Swarm', 'Primary swarm coordination channel', 'system', ?, ?)
            """, (main_conv_id, project_id, now, now))

        projects_dir = os.path.expanduser("~/.gemini/config/projects")
        if os.path.isdir(projects_dir):
            target_json = os.path.join(projects_dir, f"{project_id}.json")
            resources = []
            for furi in folders_list:
                norm_furi = self.normalize_home_path(furi)
                resources.append({"gitFolder": {"folderUri": norm_furi, "defaultBranch": "main"}})
            native_spec = {
                "id": project_id,
                "name": name,
                "projectResources": {"resources": resources},
                "settings": {},
                "isWorkspaceOnly": False
            }
            try:
                with open(target_json, "w", encoding="utf-8") as fp:
                    json.dump(native_spec, fp, indent=2)
            except Exception as e:
                sys.stderr.write(f"Notice: [hub] Failed to write native project spec {target_json}: {e}\n")

        proj = self.get_project(project_id)
        if proj:
            broadcast_event("project_created", proj)
        return proj or {}

    # -------------------------------------------------------------
    # Multi-Group Conversations & Channels
    # -------------------------------------------------------------

    def list_conversations(self, project_id: str | None = None, include_archived: bool = False) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        query = "SELECT c.*, p.name as project_name FROM conversations c LEFT JOIN projects p ON c.project_id = p.id"
        params = []
        conditions = []
        if project_id:
            conditions.append("(c.project_id = ? OR p.name = ?)")
            params.extend([project_id, project_id])
        if not include_archived:
            conditions.append("c.is_archived = 0")

        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        query += " ORDER BY c.updated_at DESC"

        cur.execute(query, params)
        convs = [dict(r) for r in cur.fetchall()]

        for c in convs:
            cid = c["id"]
            cur.execute("SELECT COUNT(*) as cnt FROM messages WHERE conv_id = ?", (cid,))
            c["message_count"] = cur.fetchone()["cnt"]

            cur.execute("""
                SELECT id, sender, content, created_at FROM messages
                WHERE conv_id = ? ORDER BY created_at DESC LIMIT 1
            """, (cid,))
            last_m = cur.fetchone()
            c["last_message"] = dict(last_m) if last_m else None

            cur.execute("SELECT node_id, agy_session_id FROM node_conversation_sessions WHERE conv_id = ?", (cid,))
            c["node_sessions"] = {row["node_id"]: row["agy_session_id"] for row in cur.fetchall()}

            cur.execute("SELECT node_id, model FROM conversation_node_models WHERE conv_id = ?", (cid,))
            c["node_models"] = {row["node_id"]: row["model"] for row in cur.fetchall()}

        return convs

    def get_conversation(self, conv_id: str) -> dict | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("""
            SELECT c.*, p.name as project_name FROM conversations c
            LEFT JOIN projects p ON c.project_id = p.id
            WHERE c.id = ?
        """, (conv_id,))
        row = cur.fetchone()
        if not row:
            return None
        c = dict(row)
        cur.execute("SELECT COUNT(*) as cnt FROM messages WHERE conv_id = ?", (conv_id,))
        c["message_count"] = cur.fetchone()["cnt"]

        cur.execute("""
            SELECT id, sender, content, created_at FROM messages
            WHERE conv_id = ? ORDER BY created_at DESC LIMIT 1
        """, (conv_id,))
        last_m = cur.fetchone()
        c["last_message"] = dict(last_m) if last_m else None

        cur.execute("SELECT node_id, agy_session_id FROM node_conversation_sessions WHERE conv_id = ?", (conv_id,))
        c["node_sessions"] = {r["node_id"]: r["agy_session_id"] for r in cur.fetchall()}

        cur.execute("SELECT node_id, model FROM conversation_node_models WHERE conv_id = ?", (conv_id,))
        c["node_models"] = {r["node_id"]: r["model"] for r in cur.fetchall()}
        return c

    def create_conversation(self, conv_id: str, title: str, project_id: str = "knot",
                            description: str = "", created_by: str = "human") -> dict:
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT id FROM projects WHERE id = ? OR name = ?", (project_id, project_id))
            prow = cur.fetchone()
            resolved_proj_id = prow["id"] if prow else project_id
            if not prow:
                conn.execute("""
                    INSERT OR IGNORE INTO projects (id, name, description, folders, default_channel, created_at, updated_at)
                    VALUES (?, ?, 'Auto-created project', '[]', 'main', ?, ?)
                """, (resolved_proj_id, resolved_proj_id, now, now))

            conn.execute("""
                INSERT INTO conversations (id, project_id, title, description, created_by, is_archived, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    description = excluded.description,
                    updated_at = excluded.updated_at
            """, (conv_id, resolved_proj_id, title, description, created_by, now, now))

        conv = self.get_conversation(conv_id)
        if conv:
            broadcast_event("conversation_created", conv)
        return conv or {}

    def get_node_session(self, conv_id: str, node_id: str) -> str | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT agy_session_id FROM node_conversation_sessions WHERE conv_id = ? AND node_id = ?", (conv_id, node_id))
        row = cur.fetchone()
        return row["agy_session_id"] if row else None

    def set_node_session(self, conv_id: str, node_id: str, agy_session_id: str):
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            conn.execute("""
                INSERT INTO node_conversation_sessions (conv_id, node_id, agy_session_id, updated_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(conv_id, node_id) DO UPDATE SET
                    agy_session_id = excluded.agy_session_id,
                    updated_at = excluded.updated_at
            """, (conv_id, node_id, agy_session_id, now))

    def get_conversation_models(self, conv_id: str) -> dict:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT selected_model FROM conversations WHERE id = ?", (conv_id,))
        row = cur.fetchone()
        default_model = (row["selected_model"] if row and row["selected_model"] else "")

        cur.execute("SELECT node_id, model FROM conversation_node_models WHERE conv_id = ?", (conv_id,))
        node_models = {r["node_id"]: r["model"] for r in cur.fetchall()}
        return {
            "conv_id": conv_id,
            "default_model": default_model,
            "node_models": node_models
        }

    def set_conversation_model(self, conv_id: str, model: str, node_id: str | None = None) -> dict:
        conn = self.get_connection()
        now = int(time.time())
        with conn:
            if node_id:
                if model:
                    conn.execute("""
                        INSERT INTO conversation_node_models (conv_id, node_id, model, updated_at)
                        VALUES (?, ?, ?, ?)
                        ON CONFLICT(conv_id, node_id) DO UPDATE SET model = excluded.model, updated_at = excluded.updated_at
                    """, (conv_id, node_id, model, now))
                else:
                    conn.execute("DELETE FROM conversation_node_models WHERE conv_id = ? AND node_id = ?", (conv_id, node_id))
            else:
                conn.execute("UPDATE conversations SET selected_model = ?, updated_at = ? WHERE id = ?", (model, now, conv_id))

        res = self.get_conversation_models(conv_id)
        broadcast_event("conversation_model_updated", res)
        return res

    # -------------------------------------------------------------
    # Swarm Konversations Group Chat Ledger
    # -------------------------------------------------------------

    def post_chat_message(self, sender: str, content: str, conv_id: str = "main",
                          mentions: list[str] | None = None, artifacts: list[str] | None = None,
                          reply_to: str | None = None, meta: dict | None = None) -> dict:
        msg_id = str(uuid.uuid4())
        now = int(time.time())

        # Auto-extract @mentions and merge with any explicitly passed mentions
        extracted_mentions = list(set(re.findall(r'@([a-zA-Z0-9_\-]+)', content)))
        if mentions:
            mentions = list(set([m.lstrip('@') for m in mentions] + extracted_mentions))
        else:
            mentions = extracted_mentions

        mentions_json = json.dumps(mentions)
        artifacts_json = json.dumps(artifacts or [])
        meta_json = json.dumps(meta or {})

        conn = self.get_connection()
        with conn:
            # Ensure conversation exists; if not, auto-create under 'knot' project
            conn.execute("""
                INSERT OR IGNORE INTO conversations (id, project_id, title, description, created_by, created_at, updated_at)
                VALUES (?, 'knot', ?, 'Auto-created group channel', ?, ?, ?)
            """, (conv_id, f"#{conv_id}", sender, now, now))

            conn.execute("UPDATE conversations SET updated_at = ? WHERE id = ?", (now, conv_id))

            conn.execute("""
                INSERT INTO messages (id, conv_id, sender, mentions, content, artifacts, reply_to, meta, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (msg_id, conv_id, sender, mentions_json, content, artifacts_json, reply_to, meta_json, now))

        msg = self.get_chat_message(msg_id)
        broadcast_event("chat_message", msg)
        return msg

    def get_chat_message(self, msg_id: str) -> dict | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM messages WHERE id = ?", (msg_id,))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        try:
            d["mentions"] = json.loads(d.get("mentions") or "[]")
        except Exception:
            d["mentions"] = []
        try:
            d["artifacts"] = json.loads(d.get("artifacts") or "[]")
        except Exception:
            d["artifacts"] = []
        try:
            d["meta"] = json.loads(d.get("meta") or "{}")
        except Exception:
            d["meta"] = {}
        return d

    def list_chat_messages(self, conv_id: str = "main", limit: int = 50, before_ts: int | None = None) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        if conv_id == "all":
            if before_ts:
                cur.execute("""
                    SELECT * FROM messages
                    WHERE created_at < ?
                    ORDER BY created_at DESC LIMIT ?
                """, (before_ts, limit))
            else:
                cur.execute("""
                    SELECT * FROM messages
                    ORDER BY created_at DESC LIMIT ?
                """, (limit,))
        else:
            if before_ts:
                cur.execute("""
                    SELECT * FROM messages
                    WHERE conv_id = ? AND created_at < ?
                    ORDER BY created_at DESC LIMIT ?
                """, (conv_id, before_ts, limit))
            else:
                cur.execute("""
                    SELECT * FROM messages
                    WHERE conv_id = ?
                    ORDER BY created_at DESC LIMIT ?
                """, (conv_id, limit))

        rows = [dict(r) for r in cur.fetchall()]
        rows.reverse()  # Return in chronological order
        for r in rows:
            try:
                r["mentions"] = json.loads(r.get("mentions") or "[]")
            except Exception:
                r["mentions"] = []
            try:
                r["artifacts"] = json.loads(r.get("artifacts") or "[]")
            except Exception:
                r["artifacts"] = []
        return rows

    # -------------------------------------------------------------
    # Atomic 3-State Artifact Leases
    # -------------------------------------------------------------

    def lock_artifact(self, name: str, locked_by: str, ttl_sec: int = DEFAULT_ARTIFACT_LEASE_TTL,
                      state: str = "LOCKED_SURGERY") -> dict:
        now = int(time.time())
        expires_at = now + ttl_sec
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM artifact_leases WHERE name = ?", (name,))
            row = cur.fetchone()
            if row:
                cur_locked_by = row["locked_by"]
                cur_expires = row["expires_at"] or 0
                if cur_locked_by and cur_locked_by != locked_by and now < cur_expires:
                    return {
                        "ok": False,
                        "error": f"Artifact '{name}' is currently locked by '{cur_locked_by}' until {cur_expires} ({cur_expires - now}s remaining).",
                        "lease": dict(row)
                    }
                conn.execute("""
                    UPDATE artifact_leases
                    SET state = ?, locked_by = ?, lease_ttl_sec = ?, locked_at = ?, expires_at = ?, updated_at = ?
                    WHERE name = ?
                """, (state, locked_by, ttl_sec, now, expires_at, now, name))
            else:
                conn.execute("""
                    INSERT INTO artifact_leases (name, state, locked_by, lease_ttl_sec, locked_at, expires_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                """, (name, state, locked_by, ttl_sec, now, expires_at, now))

        lease = self.get_artifact_lease(name)
        broadcast_event("artifact_locked", lease)
        return {"ok": True, "lease": lease}

    def release_artifact(self, name: str, node_id: str, new_state: str = "VERIFIED_COMMITTED") -> dict:
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("SELECT * FROM artifact_leases WHERE name = ?", (name,))
            row = cur.fetchone()
            if not row:
                return {"ok": False, "error": f"Artifact lease '{name}' not found."}

            cur_locked_by = row["locked_by"]
            cur_expires = row["expires_at"] or 0
            if cur_locked_by and cur_locked_by != node_id and now < cur_expires:
                return {"ok": False, "error": f"Cannot release: locked by '{cur_locked_by}', not '{node_id}'"}

            conn.execute("""
                UPDATE artifact_leases
                SET state = ?, locked_by = NULL, locked_at = NULL, expires_at = NULL, updated_at = ?
                WHERE name = ?
            """, (new_state, now, name))

        lease = self.get_artifact_lease(name)
        broadcast_event("artifact_released", lease)
        return {"ok": True, "lease": lease}

    def get_artifact_lease(self, name: str) -> dict | None:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM artifact_leases WHERE name = ?", (name,))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        try:
            d["meta"] = json.loads(d.get("meta") or "{}")
        except Exception:
            d["meta"] = {}
        return d

    def list_artifact_leases(self) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM artifact_leases ORDER BY updated_at DESC")
        rows = [dict(r) for r in cur.fetchall()]
        for r in rows:
            try:
                r["meta"] = json.loads(r.get("meta") or "{}")
            except Exception:
                r["meta"] = {}
        return rows

    def reap_expired_artifact_leases(self):
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT name, locked_by, state, expires_at FROM artifact_leases
                WHERE locked_by IS NOT NULL AND expires_at < ?
            """, (now,))
            expired = cur.fetchall()
            for exp in expired:
                name = exp["name"]
                locked_by = exp["locked_by"]
                conn.execute("""
                    UPDATE artifact_leases
                    SET state = 'DRAFTING', locked_by = NULL, locked_at = NULL, expires_at = NULL, updated_at = ?
                    WHERE name = ?
                """, (now, name))
                broadcast_event("artifact_lease_expired", {"name": name, "expired_from": locked_by})

    # -------------------------------------------------------------
    # Swarm Council Registry & Message Board
    # -------------------------------------------------------------

    def create_council_thread(self, thread_id: str, run_id: str, title: str, body: str, category: str = "general", url: str = "") -> dict:
        conn = self.get_connection()
        now_iso = datetime.now(timezone.utc).isoformat()
        if not url:
            url = f"knot://mesh/council/{thread_id}"
        with conn:
            conn.execute(
                "INSERT OR REPLACE INTO council_threads (id, run_id, title, body, category, url, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (thread_id, run_id or thread_id, title, body, category, url, now_iso)
            )
        return {
            "id": thread_id,
            "number": 1,
            "url": url,
            "title": title
        }

    def post_council_message(self, msg_id: str, thread_id: str, run_id: str, node_id: str, status: str, body: str, created_at: str = "") -> dict:
        conn = self.get_connection()
        now_iso = created_at or datetime.now(timezone.utc).isoformat()
        url = f"knot://mesh/council/{thread_id}#{msg_id}"
        with conn:
            conn.execute(
                "INSERT INTO council_messages (id, thread_id, run_id, node_id, status, body, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
                (msg_id, thread_id, run_id, node_id, status, body, now_iso)
            )
        return {
            "id": msg_id,
            "url": url,
            "createdAt": now_iso
        }

    def get_council_thread(self, thread_id: str) -> dict:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, run_id, title, body, url, created_at FROM council_threads WHERE id = ? OR run_id = ?",
            (thread_id, thread_id)
        )
        t_row = cur.fetchone()
        if not t_row:
            tid, trun, ttitle, tbody, turl, ttime = (
                thread_id,
                thread_id,
                f"Mesh Council Mission: {thread_id}",
                "Mesh registry mission thread",
                f"knot://mesh/council/{thread_id}",
                datetime.now(timezone.utc).isoformat()
            )
        else:
            tid, trun, ttitle, tbody, turl, ttime = t_row["id"], t_row["run_id"], t_row["title"], t_row["body"], t_row["url"], t_row["created_at"]

        cur.execute(
            "SELECT id, run_id, node_id, status, body, created_at FROM council_messages WHERE thread_id = ? OR run_id = ? ORDER BY created_at ASC",
            (tid, tid)
        )
        m_rows = cur.fetchall()
        comments_nodes = []
        for r in m_rows:
            mid, mrun, mnode, mstat, mbody, mtime = r["id"], r["run_id"], r["node_id"], r["status"], r["body"], r["created_at"]
            header = f"<!-- KNOT-NODE: {mnode} | RUN: {mrun} | STATUS: {mstat} -->\n"
            full_body = header + mbody if not mbody.startswith("<!-- KNOT-NODE:") else mbody
            comments_nodes.append({
                "id": mid,
                "createdAt": mtime,
                "author": {"login": mnode},
                "body": full_body
            })
        return {
            "id": tid,
            "number": 1,
            "title": ttitle,
            "url": turl,
            "body": tbody,
            "createdAt": ttime,
            "comments": {
                "totalCount": len(comments_nodes),
                "nodes": comments_nodes
            }
        }

    def get_council_delta(self, thread_id: str, last_count: int = 0) -> dict:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, run_id, node_id, status, body, created_at FROM council_messages WHERE thread_id = ? ORDER BY created_at ASC",
            (thread_id,)
        )
        rows = cur.fetchall()
        total = len(rows)
        if total <= last_count:
            return {"totalCount": total, "new_comments": []}
        new_rows = rows[last_count:]
        new_comments = []
        for r in new_rows:
            mid, mrun, mnode, mstat, mbody, mtime = r["id"], r["run_id"], r["node_id"], r["status"], r["body"], r["created_at"]
            header = f"<!-- KNOT-NODE: {mnode} | RUN: {mrun} | STATUS: {mstat} -->\n"
            full_body = header + mbody if not mbody.startswith("<!-- KNOT-NODE:") else mbody
            new_comments.append({
                "id": mid,
                "createdAt": mtime,
                "author": {"login": mnode},
                "body": full_body
            })
        return {"totalCount": total, "new_comments": new_comments}

    def list_council_threads(self) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute(
            "SELECT id, run_id, title, url, created_at, (SELECT COUNT(*) FROM council_messages WHERE thread_id = council_threads.id) as msg_count FROM council_threads ORDER BY created_at DESC"
        )
        rows = cur.fetchall()
        threads = []
        for r in rows:
            threads.append({
                "id": r["id"],
                "run_id": r["run_id"],
                "title": r["title"],
                "url": r["url"],
                "created_at": r["created_at"],
                "messages": r["msg_count"]
            })
        return threads

    # -------------------------------------------------------------
    # Node Heartbeat & Telemetry
    # -------------------------------------------------------------

    def register_node_heartbeat(self, node_id: str, hostname: str, capabilities: list[str],
                                agy_ver: str = "", agy_auth: str = "", quota: dict | None = None,
                                power: dict | None = None, ip: str = "") -> dict:
        node_id = get_canonical_node_id(node_id)
        now = int(time.time())
        cap_json = json.dumps(capabilities)
        conn = self.get_connection()

        has_quota_metrics = bool(quota and any(k in quota for k in (
            "gemini_5h_fraction", "gemini_weekly_fraction",
            "third_party_5h_fraction", "third_party_weekly_fraction"
        )))
        q_5h_gem = quota.get("gemini_5h_fraction") if (quota and has_quota_metrics) else None
        q_wk_gem = quota.get("gemini_weekly_fraction") if (quota and has_quota_metrics) else None
        q_5h_3p = quota.get("third_party_5h_fraction") if (quota and has_quota_metrics) else None
        q_wk_3p = quota.get("third_party_weekly_fraction") if (quota and has_quota_metrics) else None
        q_ts = now if has_quota_metrics else None

        if quota:
            # Preserve existing reset timestamps and fractions when receiving account-only heartbeats
            cur = conn.cursor()
            cur.execute("SELECT quota_data, quota_updated_at FROM nodes WHERE id = ?", (node_id,))
            row = cur.fetchone()
            if row and row[0]:
                try:
                    existing_qd = json.loads(row[0])
                    if isinstance(existing_qd, dict):
                        # Merge reset timestamps if missing in incoming quota
                        for rk in ["gemini_5h_reset", "gemini_weekly_reset", "third_party_5h_reset", "third_party_weekly_reset"]:
                            if rk in existing_qd and (rk not in quota or not quota[rk]):
                                quota[rk] = existing_qd[rk]
                        for fk in ["gemini_5h_fraction", "gemini_weekly_fraction", "third_party_5h_fraction", "third_party_weekly_fraction"]:
                            if fk in existing_qd and (fk not in quota or quota[fk] is None):
                                quota[fk] = existing_qd[fk]
                except Exception as _qe:
                    logger.debug("Failed merging existing quota_data: %s", _qe)

        q_data = json.dumps(quota) if quota else None
        p_data = json.dumps(power) if power else None

        with conn:
            conn.execute("""
                INSERT INTO nodes (
                    id, hostname, capabilities, status, last_heartbeat, agy_version, agy_auth,
                    quota_5h_gemini, quota_weekly_gemini, quota_5h_3p, quota_weekly_3p, quota_data, quota_updated_at,
                    power_state, ip
                )
                VALUES (?, ?, ?, 'ONLINE', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    hostname = excluded.hostname,
                    capabilities = excluded.capabilities,
                    status = 'ONLINE',
                    last_heartbeat = excluded.last_heartbeat,
                    agy_version = excluded.agy_version,
                    agy_auth = excluded.agy_auth,
                    quota_5h_gemini = COALESCE(excluded.quota_5h_gemini, nodes.quota_5h_gemini),
                    quota_weekly_gemini = COALESCE(excluded.quota_weekly_gemini, nodes.quota_weekly_gemini),
                    quota_5h_3p = COALESCE(excluded.quota_5h_3p, nodes.quota_5h_3p),
                    quota_weekly_3p = COALESCE(excluded.quota_weekly_3p, nodes.quota_weekly_3p),
                    quota_data = COALESCE(excluded.quota_data, nodes.quota_data),
                    quota_updated_at = COALESCE(excluded.quota_updated_at, nodes.quota_updated_at),
                    power_state = COALESCE(excluded.power_state, nodes.power_state),
                    ip = CASE WHEN excluded.ip != '' AND excluded.ip != '127.0.0.1' THEN excluded.ip ELSE nodes.ip END
            """, (node_id, hostname, cap_json, now, agy_ver, agy_auth,
                  q_5h_gem, q_wk_gem, q_5h_3p, q_wk_3p, q_data, q_ts, p_data, ip))
        selected_model = self.get_node_model(node_id)
        broadcast_event("node_heartbeat", {"node_id": node_id, "selected_model": selected_model})
        return {"id": node_id, "status": "ONLINE", "last_heartbeat": now, "selected_model": selected_model}

    def list_nodes(self) -> list[dict]:
        conn = self.get_connection()
        cur = conn.cursor()
        cur.execute("SELECT * FROM nodes ORDER BY last_heartbeat DESC")
        rows = cur.fetchall()
        now = int(time.time())
        result_map = {}
        for r in rows:
            d = dict(r)
            can_id = get_canonical_node_id(d.get("id", ""))
            if can_id in result_map:
                continue
            d["id"] = can_id
            d["capabilities"] = json.loads(d.get("capabilities") or "[]")
            d["selected_model"] = self.get_node_model(can_id)

            manifest = get_node_manifest(can_id)
            manifest_ip = manifest.get("ip_hint") or ""
            if not manifest_ip and "interfaces" in manifest and isinstance(manifest["interfaces"], dict):
                for iface in manifest["interfaces"].values():
                    if isinstance(iface, dict) and iface.get("ip"):
                        manifest_ip = iface["ip"]
                        break

            # Resolve real LAN IP
            current_ip = d.get("ip") or ""
            if current_ip and current_ip != "127.0.0.1":
                d["ip"] = current_ip
            else:
                d["ip"] = manifest_ip or "127.0.0.1"

            d["user"] = manifest.get("user") or d.get("user") or "user"
            d["port"] = manifest.get("port") or 22
            if manifest.get("hostname") and not d.get("hostname"):
                d["hostname"] = manifest["hostname"]

            if d.get("quota_data"):
                try:
                    d["quota_data"] = json.loads(d["quota_data"])
                except Exception as e:
                    sys.stderr.write(f"Notice: [hub] Failed to parse quota_data JSON: {e}\n")
            if isinstance(d.get("quota_data"), dict):
                qd = d["quota_data"]
                if "gemini_5h_reset" in qd:
                    qd["gemini_5h_reset_in"] = format_reset_countdown(qd.get("gemini_5h_reset"))
                if "gemini_weekly_reset" in qd:
                    qd["gemini_weekly_reset_in"] = format_reset_countdown(qd.get("gemini_weekly_reset"))
                if "third_party_5h_reset" in qd:
                    qd["third_party_5h_reset_in"] = format_reset_countdown(qd.get("third_party_5h_reset"))
                if "third_party_weekly_reset" in qd:
                    qd["third_party_weekly_reset_in"] = format_reset_countdown(qd.get("third_party_weekly_reset"))
                if "account" in qd:
                    d["account"] = qd["account"]
            d["power"] = {}
            if d.get("power_state"):
                try:
                    d["power"] = json.loads(d["power_state"])
                except Exception as e:
                    sys.stderr.write(f"Notice: [hub] Failed to parse power_state JSON: {e}\n")
            d["activity"] = self._node_activities.get(can_id, {})
            if isinstance(d["power"], dict) and d["activity"]:
                d["power"]["activity"] = d["activity"]
            if now - d.get("last_heartbeat", 0) > 30:
                d["status"] = "OFFLINE"
            result_map[can_id] = d

        # Sort in canonical swarm hierarchy
        canonical_order = ["desktop", "laptop", "rog-ally", "steamdeck"]
        sorted_nodes = []
        for cid in canonical_order:
            if cid in result_map:
                sorted_nodes.append(result_map.pop(cid))
        for remaining in sorted(result_map.keys()):
            sorted_nodes.append(result_map[remaining])
        return sorted_nodes

    def get_swarm_activity(self, idle_timeout_sec: int = 1800) -> dict:
        """
        Calculates wholesale swarm activity across tasks, messages, and manual wake holds.
        Used to enforce sleep/idle inhibition across nodes when plugged into AC power.
        """
        now = int(time.time())
        conn = self.get_connection()
        cur = conn.cursor()

        # 1. Any active tasks currently queued, claimed, or running
        cur.execute("SELECT COUNT(*) as c FROM tasks WHERE status IN ('QUEUED', 'CLAIMED', 'RUNNING')")
        active_tasks = cur.fetchone()["c"]

        # 2. Most recent task activity timestamp
        cur.execute("SELECT MAX(updated_at) as m FROM tasks")
        row = cur.fetchone()
        last_task_ts = row["m"] if row and row["m"] else 0

        # 3. Most recent chat message timestamp
        cur.execute("SELECT MAX(created_at) as m FROM messages")
        row = cur.fetchone()
        last_msg_ts = row["m"] if row and row["m"] else 0

        # 4. Manual wake hold
        manual_hold_until = getattr(self, "_manual_wake_until", 0)
        manual_hold_remaining = max(0, int(manual_hold_until - now))

        latest_activity_ts = max(last_task_ts, last_msg_ts)
        sec_since_activity = (now - latest_activity_ts) if latest_activity_ts > 0 else 999999

        is_active = False
        reasons = []

        if active_tasks > 0:
            is_active = True
            reasons.append(f"tasks_running ({active_tasks} active)")

        if manual_hold_remaining > 0:
            is_active = True
            reasons.append(f"manual_hold ({manual_hold_remaining}s remaining)")

        if sec_since_activity < idle_timeout_sec:
            is_active = True
            reasons.append(f"recent_activity ({sec_since_activity}s ago)")

        return {
            "active": is_active,
            "reasons": reasons,
            "active_tasks_count": active_tasks,
            "last_activity_sec_ago": sec_since_activity,
            "idle_timeout_sec": idle_timeout_sec,
            "manual_hold_sec_remaining": manual_hold_remaining
        }

    def reap_expired_leases(self):
        now = int(time.time())
        conn = self.get_connection()
        with conn:
            cur = conn.cursor()
            cur.execute("""
                SELECT id, claimed_by, heartbeat_at, lease_ttl_sec
                FROM tasks
                WHERE status IN ('CLAIMED', 'RUNNING')
            """)
            rows = cur.fetchall()
            for r in rows:
                heartbeat = r["heartbeat_at"] or 0
                ttl = r["lease_ttl_sec"] or DEFAULT_LEASE_TTL
                if now - heartbeat > ttl:
                    task_id = r["id"]
                    claimed_by = r["claimed_by"]
                    conn.execute("""
                        UPDATE tasks
                        SET status = 'QUEUED', claimed_by = NULL, claimed_at = NULL,
                            heartbeat_at = NULL, retry_count = retry_count + 1, updated_at = ?
                        WHERE id = ?
                    """, (now, task_id))
                    eviction_info = {"id": task_id, "expired_from": claimed_by, "reason": "lease_timeout"}
                    print(f"[*] Lease expired for task {task_id} on node {claimed_by}; requeued.")
                    broadcast_event("lease_expired", eviction_info)


class HubRequestHandler(BaseHTTPRequestHandler):
    db: Database = None

    def _send_json(self, data: dict | list, status_code: int = 200):
        body = json.dumps(data, indent=2).encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html_content: str, status_code: int = 200):
        body = html_content.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_image(self, data: bytes, content_type: str = "image/jpeg", status_code: int = 200):
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(data)

    def _send_error(self, message: str, status_code: int = 400):
        self._send_json({"error": message, "status": "ERROR"}, status_code)

    def _send_text(self, text: str, content_type: str = "text/plain; charset=utf-8", status_code: int = 200):
        body = text.encode("utf-8")
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _send_bytes(self, data: bytes, content_type: str, status_code: int = 200, headers: dict = None):
        self.send_response(status_code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        if headers:
            for k, v in headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def _serve_static(self, path: str):
        if not os.path.isdir(WEB_DIST_DIR):
            self._send_html(
                "<!DOCTYPE html><html><head><title>Knot Cockpit</title></head>"
                "<body style='background:#16161e;color:#c0caf5;font-family:monospace;padding:2rem;'>"
                "<h2>Knot Cockpit Static Assets Not Built</h2>"
                "<p>Run: <code>cd web && pnpm build</code></p>"
                "<p>Or run development server: <code>cd web && pnpm dev</code> (http://localhost:5173)</p>"
                "</body></html>",
                status_code=200
            )
            return

        clean_path = path.lstrip("/")
        if not clean_path or clean_path in ("kafe", "cockpit", "chat", "dag", "artifacts", "projects"):
            target = os.path.join(WEB_DIST_DIR, "index.html")
        else:
            target = os.path.abspath(os.path.join(WEB_DIST_DIR, clean_path))
            if not target.startswith(WEB_DIST_DIR):
                self._send_error("Forbidden", 403)
                return
            if not os.path.isfile(target):
                # SPA fallback for client-side routing
                target = os.path.join(WEB_DIST_DIR, "index.html")

        if not os.path.isfile(target):
            self._send_error("File not found", 404)
            return

        mime_type, _ = mimetypes.guess_type(target)
        if not mime_type:
            mime_type = "application/octet-stream"

        try:
            with open(target, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header("Content-Type", f"{mime_type}; charset=utf-8" if mime_type.startswith("text/") else mime_type)
            self.send_header("Content-Length", str(len(content)))
            if "/assets/" in target or target.endswith((".js", ".css", ".svg", ".png", ".woff2")):
                self.send_header("Cache-Control", "public, max-age=31536000, immutable")
            else:
                self.send_header("Cache-Control", "no-cache")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self._send_error(f"Failed to serve file: {e}", 500)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path == "/health":
            nodes = self.db.list_nodes()
            online_nodes = [n for n in nodes if n["status"] == "ONLINE"]
            tasks = self.db.list_tasks(limit=100)
            queued = sum(1 for t in tasks if t["status"] == "QUEUED")
            running = sum(1 for t in tasks if t["status"] in ("CLAIMED", "RUNNING"))
            blocked = sum(1 for t in tasks if t["status"] == "BLOCKED_ON_DEPS")
            self._send_json({
                "status": "OK",
                "service": "knot-hub",
                "timestamp": int(time.time()),
                "mesh_nodes": len(nodes),
                "online_nodes": len(online_nodes),
                "tasks_queued": queued,
                "tasks_active": running,
                "tasks_blocked_dag": blocked,
                "total_tasks_tracked": len(tasks)
            })

        elif path == "/dist/knot-mesh.tar.gz":
            bundle_data = get_distribution_bundle()
            self._send_bytes(
                bundle_data,
                content_type="application/gzip",
                status_code=200,
                headers={"Content-Disposition": 'attachment; filename="knot-mesh.tar.gz"'}
            )

        elif path == "/dist/deskflow.pem":
            pem_path = os.path.expanduser("~/.config/Deskflow/tls/deskflow.pem")
            if os.path.exists(pem_path):
                try:
                    with open(pem_path, "rb") as f:
                        pem_data = f.read()
                    self._send_bytes(
                        pem_data,
                        content_type="application/x-pem-file",
                        status_code=200,
                        headers={"Content-Disposition": 'attachment; filename="deskflow.pem"'}
                    )
                    return
                except Exception as pe:
                    sys.stderr.write(f"Error reading deskflow.pem: {pe}\n")
            self._send_error("Deskflow certificate not found on Anchor", 404)

        elif path.startswith("/join/"):
            raw_token = path.replace("/join/", "", 1).strip()
            if not raw_token:
                self._send_error("Pairing token required", 400)
                return

            pin = raw_token.split(".")[0].strip()
            with enrollment_coordinator.lock:
                session = enrollment_coordinator.sessions.get(pin)

            now = time.time()
            if not session or now > session["expires_at"]:
                ua = self.headers.get("User-Agent", "").lower()
                accept = self.headers.get("Accept", "").lower()
                is_terminal = any(t in ua for t in ("curl", "wget", "httpie")) or "application/x-sh" in accept
                if is_terminal:
                    self._send_text(
                        "#!/usr/bin/env bash\n"
                        "echo -e '\\033[1;31m[✗] Error: Invalid or expired Knot pairing token.\\033[0m' >&2\n"
                        "echo -e 'Please generate a new invitation on the Anchor using: knot-installer invite' >&2\n"
                        "exit 1\n",
                        content_type="application/x-sh",
                        status_code=404
                    )
                else:
                    self._send_html(
                        "<!DOCTYPE html><html><head><title>Invalid Token — Knot Swarm</title>"
                        "<style>body{background:#0b0f19;color:#f3f4f6;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;}"
                        ".box{background:#111827;border:1px solid #1f293d;border-radius:12px;padding:32px;max-width:480px;text-align:center;box-shadow:0 10px 25px rgba(0,0,0,0.5);}"
                        "h2{color:#f87171;margin-bottom:12px;}code{background:#030712;padding:4px 8px;border-radius:6px;color:#38bdf8;font-family:monospace;}"
                        "</style></head><body><div class='box'><h2>Invalid or Expired Pairing Token</h2>"
                        "<p>This invitation token does not exist or has expired.</p>"
                        "<p style='margin-top:16px;'>Generate a fresh invite on the Swarm Anchor:<br><br><code>knot-installer invite</code></p>"
                        "</div></body></html>",
                        status_code=404
                    )
                return

            host_hdr = self.headers.get("Host", "").strip()
            if host_hdr:
                if ":" in host_hdr:
                    req_host, req_port_str = host_hdr.split(":", 1)
                else:
                    req_host = host_hdr
                    req_port_str = str(DEFAULT_PORT)
            else:
                req_host = session.get("anchor_ip") or "127.0.0.1"
                req_port_str = str(DEFAULT_PORT)

            token_val = session["token"]
            pin_val = session["pin"]
            fp_short = session["fingerprint_short"]
            swarm_id, swarm_name = get_active_swarm_info()

            ua = self.headers.get("User-Agent", "").lower()
            accept = self.headers.get("Accept", "").lower()
            is_terminal = any(t in ua for t in ("curl", "wget", "httpie")) or "application/x-sh" in accept

            if not is_terminal and ("text/html" in accept or any(b in ua for b in ("mozilla", "chrome", "safari", "webkit"))):
                html = render_onboarding_html(
                    swarm_name=swarm_name,
                    anchor_host=req_host,
                    anchor_port=req_port_str,
                    token=token_val,
                    pin=pin_val,
                    fp_short=fp_short
                )
                self._send_html(html, 200)
            else:
                script = render_bootstrap_script(
                    swarm_name=swarm_name,
                    anchor_host=req_host,
                    anchor_port=req_port_str,
                    token=token_val,
                    pin=pin_val,
                    fp_short=fp_short
                )
                self._send_text(script, content_type="application/x-sh", status_code=200)

        elif path in ("/tasks", "/tasks/list"):
            status_filter = query.get("status", [None])[0]
            batch_filter = query.get("batch_id", [None])[0]
            limit = int(query.get("limit", [50])[0])
            tasks = self.db.list_tasks(status=status_filter, batch_id=batch_filter, limit=limit)
            self._send_json(tasks)

        elif path.startswith("/tasks/batch/"):
            batch_id = path.replace("/tasks/batch/", "").strip()
            self._send_json(self.db.get_batch_status(batch_id))

        elif path.startswith("/tasks/"):
            task_id = path.replace("/tasks/", "").strip()
            task = self.db.get_task(task_id)
            if task:
                self._send_json(task)
            else:
                self._send_error("Task not found", 404)

        elif path == "/nodes":
            self._send_json(self.db.list_nodes())

        elif path.startswith("/nodes/") and path.endswith("/screen"):
            parts = [p for p in path.split("/") if p]
            if len(parts) == 3 and parts[0] == "nodes" and parts[2] == "screen":
                node_id = parts[1]
                force = "force" in query or query.get("force", ["0"])[0] in ("1", "true")
                quality = query.get("quality", ["low"])[0]
                img_data, ctype = capture_node_screen(node_id, force=force, quality=quality)
                if img_data:
                    self._send_image(img_data, ctype)
                else:
                    self._send_error("Screen unavailable", 404)
            else:
                self._send_error("Invalid screen request path", 400)

        elif path == "/swarm/models":
            default_model = self.db.get_setting("default_swarm_model", DEFAULT_SWARM_MODEL)
            node_models = self.db.get_all_node_models()
            self._send_json({
                "available_models": get_available_models(),
                "default_model": default_model,
                "node_models": node_models
            })

        elif path == "/topology":
            active_swarm, swarm_name = get_active_swarm_info()
            user_home = os.path.expanduser("~")
            topo_path = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/topology.json")
            nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")

            topo = {
                "swarm_id": active_swarm,
                "swarm_name": swarm_name,
                "anchor": "desktop",
                "screens": [],
                "layout": {},
                "locked": False,
                "nodes": {}
            }
            if os.path.exists(topo_path):
                try:
                    with open(topo_path, "r") as tf:
                        loaded = json.load(tf)
                        topo.update(loaded)
                except Exception as e:
                    logger.warning("Error reading topology %s: %s", topo_path, e)

            # Enrich node metadata from manifests and database
            db_nodes = {n["id"]: n for n in self.db.list_nodes()}
            if os.path.isdir(nodes_dir):
                for fname in sorted(os.listdir(nodes_dir)):
                    if fname.endswith(".json"):
                        fpath = os.path.join(nodes_dir, fname)
                        try:
                            with open(fpath, "r") as mf:
                                mdata = json.load(mf)
                                nid = mdata.get("id") or fname[:-5]
                                db_n = db_nodes.get(nid, {})
                                thumb_path = os.path.join(SCREEN_CACHE_DIR, f"{nid}.jpg")
                                topo["nodes"][nid] = {
                                    "id": nid,
                                    "hostname": mdata.get("hostname", nid),
                                    "role": mdata.get("role", "strand"),
                                    "display": mdata.get("display", {}),
                                    "user": mdata.get("user", ""),
                                    "status": db_n.get("status", "unknown"),
                                    "ip_hint": mdata.get("ip_hint", db_n.get("ip_hint", "")),
                                    "has_thumbnail": os.path.exists(thumb_path)
                                }
                        except Exception as e:
                            logger.warning("Error reading node manifest %s: %s", fpath, e)

            # Ensure anchor node is represented
            if topo.get("anchor") and topo["anchor"] not in topo["nodes"]:
                topo["nodes"][topo["anchor"]] = {
                    "id": topo["anchor"],
                    "hostname": socket.gethostname(),
                    "role": "anchor",
                    "display": {},
                    "status": "online",
                    "has_thumbnail": os.path.exists(os.path.join(SCREEN_CACHE_DIR, f"{topo['anchor']}.jpg"))
                }

            # Enrich anchor display outputs if missing
            anchor_nid = topo.get("anchor")
            if anchor_nid and anchor_nid in topo["nodes"]:
                disp = topo["nodes"][anchor_nid].get("display", {})
                if not disp.get("outputs"):
                    try:
                        disp_script = os.path.join(REPO_ROOT, "core/installer/display.sh")
                        if os.path.exists(disp_script):
                            res = subprocess.run([disp_script, "--json"], capture_output=True, text=True, timeout=2)
                            if res.returncode == 0:
                                parsed_disp = json.loads(res.stdout)
                                topo["nodes"][anchor_nid]["display"] = parsed_disp
                    except Exception as de:
                        logger.debug("Could not auto-populate anchor display: %s", de)

            self._send_json(topo)

        elif path == "/quota":
            nodes = self.db.list_nodes()
            result = []
            for n in nodes:
                q_data = n.get("quota_data") or {}
                result.append({
                    "node_id": n["id"],
                    "account": n.get("account") or q_data.get("account"),
                    "groups": {
                        "gemini": {
                            "five_hour": {
                                "current": n.get("quota_5h_gemini") if n.get("quota_5h_gemini") is not None else 1.0,
                                "limit": 1.0,
                                "pct": int((n.get("quota_5h_gemini") if n.get("quota_5h_gemini") is not None else 1.0) * 100),
                                "status": "OK" if (n.get("quota_5h_gemini") or 1.0) > 0.3 else "LOW",
                                "next_reset_in": q_data.get("gemini_5h_reset_in") or format_reset_countdown(q_data.get("gemini_5h_reset"))
                            },
                            "weekly": {
                                "current": n.get("quota_weekly_gemini") if n.get("quota_weekly_gemini") is not None else 1.0,
                                "limit": 1.0,
                                "pct": int((n.get("quota_weekly_gemini") if n.get("quota_weekly_gemini") is not None else 1.0) * 100),
                                "status": "OK" if (n.get("quota_weekly_gemini") or 1.0) > 0.3 else "LOW",
                                "next_reset_in": q_data.get("gemini_weekly_reset_in") or format_reset_countdown(q_data.get("gemini_weekly_reset"))
                            }
                        }
                    }
                })
            self._send_json(result)

        elif path == "/projects":
            self._send_json(self.db.list_projects())

        elif path.startswith("/projects/"):
            pid = path.replace("/projects/", "").strip()
            p = self.db.get_project(pid)
            if p:
                self._send_json(p)
            else:
                self._send_error("Project not found", 404)

        elif path == "/chat/conversations":
            proj_id = query.get("project_id", [None])[0]
            self._send_json(self.db.list_conversations(project_id=proj_id))

        elif path.startswith("/chat/conversations/") and path.endswith("/models"):
            cid = path.replace("/chat/conversations/", "").replace("/models", "").strip()
            self._send_json(self.db.get_conversation_models(cid))

        elif path.startswith("/chat/conversations/"):
            cid = path.replace("/chat/conversations/", "").strip()
            c = self.db.get_conversation(cid)
            if c:
                self._send_json(c)
            else:
                self._send_error("Conversation not found", 404)

        elif path == "/chat/session":
            conv_id = query.get("conv_id", [""])[0]
            node_id = query.get("node_id", [""])[0]
            session_id = self.db.get_node_session(conv_id, node_id)
            self._send_json({"conv_id": conv_id, "node_id": node_id, "agy_session_id": session_id})

        elif path == "/chat/messages":
            conv_id = query.get("conv_id", ["main"])[0]
            limit = int(query.get("limit", [50])[0])
            before_ts = int(query.get("before_ts", [0])[0]) or None
            self._send_json(self.db.list_chat_messages(conv_id=conv_id, limit=limit, before_ts=before_ts))

        elif path == "/council/threads":
            self._send_json(self.db.list_council_threads())

        elif path.startswith("/council/threads/") and "/delta" in path:
            tid = path.replace("/council/threads/", "").split("/delta")[0].strip()
            last_count = int(query.get("last_count", [0])[0])
            self._send_json(self.db.get_council_delta(tid, last_count=last_count))

        elif path.startswith("/council/threads/"):
            tid = path.replace("/council/threads/", "").strip()
            self._send_json(self.db.get_council_thread(tid))

        elif path == "/artifacts/leases":
            self._send_json(self.db.list_artifact_leases())

        elif path.startswith("/artifacts/lease/"):
            name = path.replace("/artifacts/lease/", "").strip()
            lease = self.db.get_artifact_lease(name)
            if lease:
                self._send_json(lease)
            else:
                self._send_error("Artifact lease not found", 404)

        elif path == "/swarm/activity":
            timeout = int(query.get("timeout", [1800])[0])
            self._send_json(self.db.get_swarm_activity(idle_timeout_sec=timeout))

        elif path == "/nodes/activity":
            self._send_json(self.db.get_all_node_activities())

        elif path == "/power/status":
            nodes = self.db.list_nodes()
            activity = self.db.get_swarm_activity()
            self._send_json({
                "swarm_active": activity["active"],
                "activity": activity,
                "nodes": [
                    {
                        "id": n["id"],
                        "hostname": n.get("hostname", n["id"]),
                        "status": n["status"],
                        "last_heartbeat": n["last_heartbeat"],
                        "power": n.get("power", {})
                    }
                    for n in nodes
                ]
            })

        elif path in ("/stream", "/events"):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            import queue
            q = queue.Queue(maxsize=100)
            with _subscribers_lock:
                _subscribers.add(q)

            init_msg = f"event: connected\ndata: {json.dumps({'time': int(time.time())})}\n\n".encode("utf-8")
            try:
                self.wfile.write(init_msg)
                self.wfile.flush()
                while True:
                    try:
                        msg = q.get(timeout=15.0)
                        self.wfile.write(msg)
                        self.wfile.flush()
                    except queue.Empty:
                        self.wfile.write(b": heartbeat\n\n")
                        self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError) as e:
                sys.stderr.write(f"Notice: [hub] SSE subscriber disconnected: {e}\n")
            finally:
                with _subscribers_lock:
                    _subscribers.discard(q)

        else:
            self._serve_static(path)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path

        content_type = self.headers.get("Content-Type", "")
        content_length = int(self.headers.get("Content-Length", 0))
        post_data = self.rfile.read(content_length) if content_length > 0 else b"{}"

        if content_type.startswith("image/") or content_type.startswith("application/octet-stream"):
            body = {"raw_bytes": post_data}
        else:
            try:
                body = json.loads(post_data.decode("utf-8")) if post_data else {}
            except Exception:
                self._send_error("Invalid JSON body", 400)
                return

        if path == "/swarm/enroll/invite":
            expires_in = int(body.get("expires_in", 600))
            anchor_ip = body.get("anchor_ip", "").strip()
            session = enrollment_coordinator.create_invite(expires_in=expires_in, anchor_ip=anchor_ip)
            self._send_json({
                "pin": session["pin"],
                "token": session["token"],
                "fingerprint": session["fingerprint"],
                "fingerprint_short": session["fingerprint_short"],
                "expires_in": expires_in
            }, 201)

        elif path == "/swarm/enroll/rendezvous/wait":
            pin = body.get("pin", "").strip()
            if not pin:
                self._send_error("Field 'pin' is required", 400)
                return
            timeout = float(body.get("timeout", 120.0))
            strand_req = enrollment_coordinator.wait_rendezvous(pin, timeout=timeout)
            if strand_req:
                self._send_json({"status": "connected", "strand": strand_req}, 200)
            else:
                self._send_json({"status": "timeout"}, 408)

        elif path == "/swarm/enroll/join":
            pin = body.get("pin", "").strip()
            if not pin:
                self._send_error("Field 'pin' is required", 400)
                return
            body["ip_hint"] = body.get("ip_hint") or self.client_address[0]
            ok, msg, result = enrollment_coordinator.join_request(pin, body)
            if ok:
                self._send_json(result, 200)
            else:
                self._send_error(msg, 403)

        elif path == "/swarm/enroll/approve":
            pin = body.get("pin", "").strip()
            placement = body.get("placement", "left").strip()
            if not pin:
                self._send_error("Field 'pin' is required", 400)
                return

            active_swarm, _ = get_active_swarm_info()

            user_home = os.path.expanduser("~")
            topo_path = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/topology.json")
            anchor_id = "desktop"
            if os.path.exists(topo_path):
                try:
                    with open(topo_path, "r") as tf:
                        tdata = json.load(tf)
                        anchor_id = tdata.get("anchor", "desktop")
                except Exception as e:
                    logger.warning("Error reading topology %s: %s", topo_path, e)

            anchor_pubkey = ""
            pub_path = os.path.join(user_home, ".ssh/id_ed25519.pub")
            if os.path.exists(pub_path):
                try:
                    with open(pub_path, "r") as pf:
                        anchor_pubkey = pf.read().strip()
                except Exception as exc:
                    sys.stderr.write(f"[Knot Hub] Failed to read SSH public key at {pub_path}: {exc}\n")

            anchor_meta = {
                "swarm_id": active_swarm,
                "anchor_id": anchor_id,
                "anchor_hostname": socket.gethostname(),
                "anchor_pubkey": anchor_pubkey,
                "hub_port": DEFAULT_PORT,
            }

            with enrollment_coordinator.lock:
                session = enrollment_coordinator.sessions.get(pin)
                if session and session.get("strand_request"):
                    sreq = session["strand_request"]
                    node_id = sreq.get("node_id") or sreq.get("hostname") or "strand"
                    nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")
                    os.makedirs(nodes_dir, exist_ok=True)
                    manifest_path = os.path.join(nodes_dir, f"{node_id}.json")
                    manifest_data = {
                        "id": node_id,
                        "hostname": sreq.get("hostname", node_id),
                        "role": sreq.get("role", "strand"),
                        "user": sreq.get("user", os.environ.get("USER", "knot")),
                        "ip_hint": sreq.get("ip_hint", ""),
                        "port": sreq.get("port", 22),
                        "pubkey": sreq.get("pubkey", ""),
                        "display": sreq.get("display", {}),
                        "capabilities": sreq.get("capabilities", ["strand"])
                    }
                    try:
                        with open(manifest_path, "w") as mf:
                            json.dump(manifest_data, mf, indent=2)
                    except Exception as me:
                        sys.stderr.write(f"[knot-hub] Error writing strand manifest: {me}\n")

                    strand_pubkey = manifest_data.get("pubkey", "").strip()
                    if strand_pubkey:
                        install_authorized_key(strand_pubkey)

                    # Dynamic Topology & Deskflow Recompilation
                    if placement in ("left", "right", "above", "below", "up", "down") and os.path.exists(topo_path):
                        try:
                            norm_p = "up" if placement == "above" else ("down" if placement == "below" else placement)
                            opp_map = {"left": "right", "right": "left", "up": "down", "down": "up"}
                            opp_p = opp_map.get(norm_p, "right")

                            with open(topo_path, "r") as tf:
                                topo_data = json.load(tf)

                            if "screens" not in topo_data:
                                topo_data["screens"] = [anchor_id]
                            if node_id not in topo_data["screens"]:
                                topo_data["screens"].append(node_id)
                            if "layout" not in topo_data:
                                topo_data["layout"] = {}
                            if anchor_id not in topo_data["layout"]:
                                topo_data["layout"][anchor_id] = {}
                            topo_data["layout"][anchor_id][norm_p] = {"node": node_id, "span": [0, 100]}
                            if node_id not in topo_data["layout"]:
                                topo_data["layout"][node_id] = {}
                            topo_data["layout"][node_id][opp_p] = {"node": anchor_id, "span": [0, 100]}

                            with open(topo_path, "w") as tf:
                                json.dump(topo_data, tf, indent=2)

                            recompile_and_restart_deskflow(topo_path, nodes_dir, mode="unlocked")
                        except Exception as te:
                            sys.stderr.write(f"[knot-hub] Error auto-updating topology/deskflow: {te}\n")

                    # Synchronize Anchor ~/.ssh/config so newly enrolled node is immediately reachable
                    sync_ssh_config()

            ok, msg = enrollment_coordinator.approve_enrollment(pin, placement, anchor_meta)
            if ok:
                self._send_json({"status": "approved", "placement": placement}, 200)
            else:
                self._send_error(msg, 400)

        # -----------------------------------------------------------------
        # Tuplespace Task Dispatch & Management (A2A Cognitive Swarm Layer)
        # -----------------------------------------------------------------
        elif path == "/tasks/post":
            title = body.get("title", "").strip() or "Autonomous Swarm Task"
            prompt = body.get("prompt", "").strip()
            if not prompt:
                self._send_error("Field 'prompt' is required", 400)
                return

            target_plane = body.get("target_plane", "any").strip()
            lease_ttl = int(body.get("lease_ttl", DEFAULT_LEASE_TTL))
            batch_id = body.get("batch_id")
            parent_id = body.get("parent_id")
            dependencies = body.get("dependencies", [])
            meta = body.get("meta", {})

            task = self.db.post_task(
                title=title,
                prompt=prompt,
                target_plane=target_plane,
                lease_ttl=lease_ttl,
                batch_id=batch_id,
                parent_id=parent_id,
                dependencies=dependencies,
                meta=meta
            )
            self._send_json(task, 201)

        elif path == "/tasks/fanout":
            tasks = body.get("tasks", [])
            barrier_task = body.get("barrier_task", None)
            batch_id = body.get("batch_id", None)
            if not tasks:
                self._send_error("Field 'tasks' array is required and cannot be empty", 400)
                return

            res = self.db.post_fanout(tasks=tasks, barrier_task=barrier_task, batch_id=batch_id)
            self._send_json(res, 201)

        elif path == "/tasks/claim":
            node_id = body.get("node_id", "").strip()
            capabilities = body.get("capabilities", [])
            if not node_id:
                self._send_error("Field 'node_id' is required", 400)
                return

            task = self.db.claim_task(node_id, capabilities)
            if task:
                self._send_json(task, 200)
            else:
                self._send_json({"message": "no matching queued tasks", "task": None}, 200)

        elif path == "/tasks/heartbeat":
            task_id = body.get("task_id", "").strip()
            node_id = body.get("node_id", "").strip()
            if not task_id or not node_id:
                self._send_error("Fields 'task_id' and 'node_id' are required", 400)
                return

            success = self.db.task_heartbeat(task_id, node_id)
            self._send_json({"ok": success, "task_id": task_id})

        elif path == "/tasks/result":
            task_id = body.get("task_id", "").strip()
            node_id = body.get("node_id", "").strip()
            status = body.get("status", "COMPLETED").strip()
            result = body.get("result", "")
            session_id = body.get("session_id", "")
            duration_sec = float(body.get("duration_seconds", 0.0))
            tokens_used = int(body.get("tokens_used", 0))

            if not task_id or not node_id:
                self._send_error("Fields 'task_id' and 'node_id' are required", 400)
                return

            task = self.db.complete_task(
                task_id=task_id,
                node_id=node_id,
                status=status,
                result=result,
                session_id=session_id,
                duration_seconds=duration_sec,
                tokens_used=tokens_used
            )
            if task:
                self._send_json(task, 200)
            else:
                self._send_error("Failed to record result or task not found", 404)

        elif path == "/node/heartbeat":
            node_id = body.get("node_id", "").strip()
            hostname = body.get("hostname", "").strip()
            capabilities = body.get("capabilities", [])
            agy_ver = body.get("agy_version", "")
            agy_auth = body.get("agy_auth", "")
            quota = body.get("quota", None)
            power = body.get("power", None)

            if not node_id:
                self._send_error("Field 'node_id' is required", 400)
                return

            client_ip = self.client_address[0] if hasattr(self, "client_address") and self.client_address else ""
            resp = self.db.register_node_heartbeat(
                node_id=node_id,
                hostname=hostname or node_id,
                capabilities=capabilities,
                agy_ver=agy_ver,
                agy_auth=agy_auth,
                quota=quota,
                power=power,
                ip=client_ip
            )
            self._send_json(resp, 200)

        elif path == "/node/activity":
            node_id = body.get("node_id", "").strip()
            activity = body.get("activity", {})
            if not node_id:
                self._send_error("Field 'node_id' is required", 400)
                return
            self.db.set_node_activity(node_id, activity)
            broadcast_event("node_activity", {"node_id": node_id, "activity": activity})
            self._send_json({"ok": True}, 200)

        elif path == "/swarm/wake":
            duration = int(body.get("duration_sec", 3600))
            self.db._manual_wake_until = int(time.time()) + duration
            broadcast_event("swarm_wake_hold", {"duration_sec": duration, "until": self.db._manual_wake_until})
            self._send_json({"ok": True, "manual_wake_until": self.db._manual_wake_until})

        elif path == "/swarm/sleep-allow":
            self.db._manual_wake_until = 0
            broadcast_event("swarm_wake_released", {})
            self._send_json({"ok": True, "manual_wake_until": 0})

        elif path == "/mesh/action":
            action = body.get("action", "").strip()
            target = body.get("target", "").strip() or "--all"

            allowed_actions = {
                "restart_kvm": ["knot", "kvm", "restart"],
                "screen_lock": ["knot", "screen", "lock", target],
                "screen_unlock": ["knot", "screen", "unlock", target],
                "screen_status": ["knot", "screen", "status", target],
                "doctor": ["knot", "doctor", target],
            }

            if action not in allowed_actions:
                self._send_error(f"Unsupported action '{action}'. Allowed: {list(allowed_actions.keys())}", 400)
                return

            cmd = list(allowed_actions[action])
            knot_path = shutil.which("knot") or os.path.join(KNOT_ROOT, "bin", "knot")
            cmd[0] = knot_path

            try:
                proc = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=45.0
                )
                output = proc.stdout + (("\n" + proc.stderr) if proc.stderr else "")
                self._send_json({
                    "ok": proc.returncode == 0,
                    "action": action,
                    "target": target,
                    "exit_code": proc.returncode,
                    "output": output.strip()
                }, 200)
            except subprocess.TimeoutExpired:
                self._send_json({
                    "ok": False,
                    "action": action,
                    "target": target,
                    "exit_code": -1,
                    "output": "Action timed out after 45 seconds"
                }, 504)
            except Exception as e:
                self._send_json({
                    "ok": False,
                    "action": action,
                    "target": target,
                    "exit_code": -1,
                    "output": str(e)
                }, 500)

        elif path == "/mesh/exec":
            target = (body.get("target") or body.get("node") or "").strip()
            command = body.get("command", "").strip()
            timeout = float(body.get("timeout", 30))

            if not target or not command:
                self._send_error("Fields 'target' and 'command' are required", 400)
                return

            knot_path = shutil.which("knot") or os.path.join(KNOT_ROOT, "bin", "knot")
            cmd = [knot_path, "exec", target, command]

            try:
                proc = subprocess.run(
                    cmd,
                    capture_output=True,
                    text=True,
                    timeout=timeout
                )
                self._send_json({
                    "ok": proc.returncode == 0,
                    "target": target,
                    "command": command,
                    "exit_code": proc.returncode,
                    "stdout": proc.stdout,
                    "stderr": proc.stderr
                }, 200)
            except subprocess.TimeoutExpired:
                self._send_json({
                    "ok": False,
                    "target": target,
                    "command": command,
                    "exit_code": -1,
                    "stdout": "",
                    "stderr": f"Command timed out after {timeout} seconds on {target}"
                }, 200)
            except Exception as e:
                self._send_json({
                    "ok": False,
                    "target": target,
                    "command": command,
                    "exit_code": -1,
                    "stdout": "",
                    "stderr": str(e)
                }, 500)

        elif path == "/swarm/model":
            model = body.get("model", "").strip()
            node_id = body.get("node_id", "").strip() or None
            apply_to_all = bool(body.get("apply_to_all", False))

            if not model:
                self._send_error("Field 'model' is required", 400)
                return

            if apply_to_all:
                self.db.set_all_node_models(model)
            elif node_id:
                self.db.set_node_model(node_id, model)
            else:
                self.db.set_setting("default_swarm_model", model)

            default_model = self.db.get_setting("default_swarm_model", DEFAULT_SWARM_MODEL)
            node_models = self.db.get_all_node_models()

            broadcast_event("model_updated", {
                "default_model": default_model,
                "node_models": node_models,
                "updated_node": node_id if (node_id and not apply_to_all) else None,
                "model": model,
                "apply_to_all": apply_to_all
            })
            self._send_json({
                "ok": True,
                "default_model": default_model,
                "node_models": node_models,
                "updated_node": node_id,
                "model": model,
                "apply_to_all": apply_to_all
            }, 200)

        elif path == "/projects":
            pid = body.get("id", "").strip() or str(uuid.uuid4())
            name = body.get("name", pid).strip() or pid
            desc = body.get("description", "").strip()
            folders = body.get("folders", [])
            proj = self.db.create_project(project_id=pid, name=name, description=desc, folders=folders)
            self._send_json(proj, 201)

        elif path == "/chat/conversations":
            cid = body.get("id", "").strip() or re.sub(r'[^a-zA-Z0-9_-]', '-', body.get("title", "").strip().lower()) or str(uuid.uuid4())
            title = body.get("title", cid).strip() or cid
            proj_id = body.get("project_id", "knot").strip() or "knot"
            desc = body.get("description", "").strip()
            created_by = body.get("created_by", "human").strip() or "human"
            conv = self.db.create_conversation(conv_id=cid, title=title, project_id=proj_id, description=desc, created_by=created_by)
            self._send_json(conv, 201)

        elif path.startswith("/chat/conversations/") and path.endswith("/model"):
            cid = path.replace("/chat/conversations/", "").replace("/model", "").strip()
            model = body.get("model", "").strip()
            node_id = body.get("node_id", "").strip() or None
            res = self.db.set_conversation_model(conv_id=cid, model=model, node_id=node_id)
            self._send_json(res, 200)

        elif path == "/chat/session":
            conv_id = body.get("conv_id", "").strip()
            node_id = body.get("node_id", "").strip()
            agy_session_id = body.get("agy_session_id", "").strip()
            if not conv_id or not node_id or not agy_session_id:
                self._send_error("Fields conv_id, node_id, and agy_session_id are required", 400)
                return
            self.db.set_node_session(conv_id, node_id, agy_session_id)
            self._send_json({"ok": True, "conv_id": conv_id, "node_id": node_id, "agy_session_id": agy_session_id}, 200)

        elif path == "/chat/messages":
            sender = body.get("sender", "user").strip() or "user"
            content = body.get("content", "").strip()
            conv_id = body.get("conv_id", "main").strip() or "main"
            mentions = body.get("mentions", None)
            artifacts = body.get("artifacts", None)
            reply_to = body.get("reply_to", None)
            meta = body.get("meta", None)

            if not content:
                self._send_error("Field 'content' is required", 400)
                return

            msg = self.db.post_chat_message(
                sender=sender,
                content=content,
                conv_id=conv_id,
                mentions=mentions,
                artifacts=artifacts,
                reply_to=reply_to,
                meta=meta
            )
            self._send_json(msg, 201)

        elif path == "/council/threads":
            tid = body.get("id", "").strip() or str(uuid.uuid4())
            run_id = body.get("run_id", tid).strip()
            title = body.get("title", tid).strip()
            tbody = body.get("body", "").strip()
            category = body.get("category", "general").strip()
            url = body.get("url", f"knot://mesh/council/{tid}").strip()
            res = self.db.create_council_thread(tid, run_id, title, tbody, category, url)
            self._send_json(res, 201)

        elif path.startswith("/council/threads/") and path.endswith("/reply"):
            tid = path.replace("/council/threads/", "").replace("/reply", "").strip()
            msg_id = body.get("id", "").strip() or f"msg_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
            run_id = body.get("run_id", tid).strip()
            node_id = body.get("node_id", "desktop").strip()
            status = body.get("status", "PROGRESS").strip()
            mbody = body.get("body", "").strip()
            created_at = body.get("created_at", "").strip()
            res = self.db.post_council_message(msg_id, tid, run_id, node_id, status, mbody, created_at)
            self._send_json(res, 201)

        elif path == "/artifacts/lock":
            name = body.get("name", "").strip()
            locked_by = body.get("node_id", body.get("locked_by", "")).strip()
            ttl_sec = int(body.get("ttl", body.get("lease_ttl", DEFAULT_ARTIFACT_LEASE_TTL)))
            state = body.get("state", "LOCKED_SURGERY").strip() or "LOCKED_SURGERY"

            if not name or not locked_by:
                self._send_error("Fields 'name' and 'node_id' (or 'locked_by') are required", 400)
                return

            res = self.db.lock_artifact(name=name, locked_by=locked_by, ttl_sec=ttl_sec, state=state)
            status_code = 200 if res.get("ok") else 409
            self._send_json(res, status_code)

        elif path == "/artifacts/release":
            name = body.get("name", "").strip()
            node_id = body.get("node_id", "").strip()
            new_state = body.get("state", "VERIFIED_COMMITTED").strip() or "VERIFIED_COMMITTED"

            if not name or not node_id:
                self._send_error("Fields 'name' and 'node_id' are required", 400)
                return

            res = self.db.release_artifact(name=name, node_id=node_id, new_state=new_state)
            status_code = 200 if res.get("ok") else 400
            self._send_json(res, status_code)

        elif path == "/topology":
            active_swarm, _ = get_active_swarm_info()
            user_home = os.path.expanduser("~")
            topo_path = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/topology.json")

            anchor = body.get("anchor")
            screens = body.get("screens", [])
            layout = body.get("layout", {})
            locked = bool(body.get("locked", False))

            if not anchor:
                self._send_error("Field 'anchor' is required", 400)
                return

            topo_data = {
                "anchor": anchor,
                "screens": screens,
                "layout": layout,
                "locked": locked
            }

            os.makedirs(os.path.dirname(topo_path), exist_ok=True)
            with open(topo_path, "w") as tf:
                json.dump(topo_data, tf, indent=2)

            nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")
            mode = "locked" if locked else "unlocked"
            recompiled = recompile_and_restart_deskflow(
                topo_path=topo_path,
                nodes_dir=nodes_dir,
                mode=mode,
                restart_stripd=True
            )

            broadcast_event("topology_updated", topo_data)
            self._send_json({"ok": True, "recompiled": recompiled, "topology": topo_data})

        elif path == "/topology/analyze-photo":
            active_swarm, _ = get_active_swarm_info()
            user_home = os.path.expanduser("~")
            nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")

            mode = body.get("mode", "auto")
            raw_data = None

            if "raw_bytes" in body:
                raw_data = body["raw_bytes"]
            elif "image_base64" in body:
                b64_str = body["image_base64"]
                if "," in b64_str:
                    b64_str = b64_str.split(",", 1)[1]
                try:
                    raw_data = base64.b64decode(b64_str)
                except Exception as be:
                    self._send_error(f"Invalid base64 image data: {be}", 400)
                    return
            elif "image_path" in body:
                p = body["image_path"].strip()
                if os.path.isfile(p):
                    try:
                        with open(p, "rb") as f:
                            raw_data = f.read()
                    except Exception as fe:
                        self._send_error(f"Cannot read image_path: {fe}", 400)
                        return
                else:
                    self._send_error(f"image_path file not found: {p}", 404)
                    return
            else:
                self._send_error("Provide 'image_base64', 'image_path', or binary image payload", 400)
                return

            # Gather swarm node context
            node_list = []
            if os.path.isdir(nodes_dir):
                for fname in sorted(os.listdir(nodes_dir)):
                    if fname.endswith(".json"):
                        try:
                            with open(os.path.join(nodes_dir, fname), "r") as mf:
                                node_list.append(json.load(mf))
                        except Exception as exc:
                            sys.stderr.write(f"[Knot Hub] Failed to read node manifest {fname}: {exc}\n")

            topo_path = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/topology.json")
            anchor_id = "desktop"
            if os.path.exists(topo_path):
                try:
                    with open(topo_path, "r") as tf:
                        anchor_id = json.load(tf).get("anchor") or "desktop"
                except Exception as exc:
                    sys.stderr.write(f"[Knot Hub] Failed to read topology at {topo_path}: {exc}\n")
            if anchor_id == "desktop":
                for node in node_list:
                    if node.get("role") == "anchor":
                        anchor_id = node.get("id") or node.get("node_id", anchor_id)
                        break

            try:
                from core.vision.engine import analyze_desk_photo
                analysis = analyze_desk_photo(
                    raw_data,
                    mode=mode,
                    swarm_nodes=node_list,
                    anchor_id=anchor_id
                )
                self._send_json({"ok": True, "result": analysis}, 200)
            except Exception as ve:
                logger.exception("Photo topology analysis error: %s", ve)
                self._send_error(f"Topology analysis failed: {ve}", 500)

        elif path == "/topology/identify":
            bg = body.get("bg", "white")
            duration = int(body.get("duration") or body.get("duration_sec") or 15)
            active_swarm, _ = get_active_swarm_info()
            user_home = os.path.expanduser("~")
            nodes_dir = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/nodes")
            anchor_id = "desktop"
            topo_path = os.path.join(user_home, f".config/knot/swarms/{active_swarm}/topology.json")
            if os.path.isfile(topo_path):
                try:
                    with open(topo_path, "r") as tf:
                        anchor_id = json.load(tf).get("anchor", "desktop")
                except Exception as exc:
                    sys.stderr.write(f"[Knot Hub] Failed to read topology at {topo_path}: {exc}\n")

            # 1. Broadcast display_identify SSE event to all connected Kafe web clients
            broadcast_event("display_identify", {
                "bg": bg,
                "duration": duration,
                "timestamp": time.time()
            })

            # 2. Trigger local display overlay on anchor if display is available and not already running
            overlay_script = os.path.join(REPO_ROOT, "core/vision/display_overlay.py")
            if os.path.exists(overlay_script) and (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY")):
                try:
                    res_check = subprocess.run(["pgrep", "-f", "display_overlay.py"], capture_output=True, text=True)
                    if not res_check.stdout.strip():
                        subprocess.Popen([
                            sys.executable,
                            overlay_script,
                            "--bg", bg,
                            "--duration", str(duration)
                        ])
                except Exception as oe:
                    logger.warning("Failed to launch local display overlay: %s", oe)

            # 3. Asynchronously trigger remote strand overlays over SSH concurrently in background threads
            def _trigger_single_node(nid, user, ip, port):
                remote_cmd = (
                    f"export XDG_RUNTIME_DIR=/run/user/$(id -u); "
                    f"export WAYLAND_DISPLAY=${{WAYLAND_DISPLAY:-wayland-0}}; "
                    f"export DISPLAY=${{DISPLAY:-:0}}; "
                    f"export PATH=\"$HOME/.local/bin:$HOME/.local/share/knot-mesh/bin:/usr/local/bin:$PATH\"; "
                    f"knot topology identify --bg {bg} --duration {duration}"
                )
                # Try via SSH config alias first (supports dynamic knot-resolve proxy)
                ssh_cmd = [
                    "ssh", "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=accept-new",
                    nid, remote_cmd
                ]
                try:
                    res = subprocess.run(ssh_cmd, capture_output=True, text=True, timeout=duration + 5)
                    if res.returncode != 0:
                        sys.stderr.write(f"[knot-hub] Remote overlay trigger via alias '{nid}' returned {res.returncode}: {res.stderr.strip()}\n")
                        if ip:
                            # Fallback to direct user@ip
                            fallback_cmd = [
                                "ssh", "-o", "ConnectTimeout=3", "-o", "StrictHostKeyChecking=accept-new",
                                "-p", port, f"{user}@{ip}", remote_cmd
                            ]
                            res_fb = subprocess.run(fallback_cmd, capture_output=True, text=True, timeout=duration + 5)
                            if res_fb.returncode != 0:
                                sys.stderr.write(f"[knot-hub] Remote overlay fallback to {user}@{ip} returned {res_fb.returncode}: {res_fb.stderr.strip()}\n")
                except subprocess.TimeoutExpired:
                    sys.stderr.write(f"[knot-hub] Timeout triggering remote overlay on '{nid}'\n")
                except Exception as exc:
                    sys.stderr.write(f"[knot-hub] Error triggering remote overlay on '{nid}': {exc}\n")

            def _trigger_remote_nodes():
                if not os.path.isdir(nodes_dir):
                    return
                threads = []
                for fname in sorted(os.listdir(nodes_dir)):
                    if fname.endswith(".json"):
                        try:
                            with open(os.path.join(nodes_dir, fname), "r") as mf:
                                mdata = json.load(mf)
                            nid = mdata.get("id") or fname[:-5]
                            role = mdata.get("role", "strand")
                            if role == "anchor" or nid == anchor_id:
                                continue
                            ip = mdata.get("ip_hint") or ""
                            user = mdata.get("user") or os.environ.get("USER") or "user"
                            port = str(mdata.get("port") or 22)
                            t = threading.Thread(target=_trigger_single_node, args=(nid, user, ip, port), daemon=True)
                            threads.append(t)
                            t.start()
                        except Exception as re:
                            sys.stderr.write(f"[knot-hub] Remote identify trigger error for {fname}: {re}\n")
                for t in threads:
                    t.join(timeout=duration + 5)

            threading.Thread(target=_trigger_remote_nodes, daemon=True).start()

            self._send_json({"ok": True, "bg": bg, "duration": duration, "broadcast": True}, 200)

        elif path == "/topology/align":
            knot_bin = shutil.which("knot") or os.path.expanduser("~/.local/bin/knot")
            if knot_bin and os.path.exists(knot_bin):
                res = subprocess.run([knot_bin, "topology", "align-internal"], capture_output=True, text=True)
            else:
                topo_script = os.path.join(REPO_ROOT, "core/modules/topology.sh")
                res = subprocess.run(["bash", "-c", f"source {topo_script} && topology_align_internal"], capture_output=True, text=True)
            self._send_json({"ok": res.returncode == 0, "output": res.stdout, "error": res.stderr}, 200 if res.returncode == 0 else 500)

        else:
            self._send_error("Not found", 404)

    def log_message(self, format, *args):
        # Suppress poll logs
        if args and str(args[1]) in ("200", "201"):
            cmd_path = str(args[0])
            if any(p in cmd_path for p in ("/tasks/claim", "/chat/messages", "/artifacts/leases")):
                return
        super().log_message(format, *args)


def lease_reaper_loop(db: Database, stop_event: threading.Event):
    while not stop_event.is_set():
        try:
            db.reap_expired_leases()
            db.reap_expired_artifact_leases()
        except Exception as e:
            print(f"[!] Error in lease reaper: {e}", file=sys.stderr)
        stop_event.wait(5.0)


def main():
    port = int(os.environ.get("KNOT_HUB_PORT", DEFAULT_PORT))
    db_path = os.environ.get("KNOT_HUB_DB", DEFAULT_DB_PATH)

    db = Database(db_path)
    HubRequestHandler.db = db

    server = ThreadingHTTPServer(("0.0.0.0", port), HubRequestHandler)

    # Wrap with TLS if not explicitly disabled
    is_tls = False
    if not os.environ.get("KNOT_HUB_DISABLE_TLS"):
        try:
            try:
                from core.hub.tls import ensure_hub_tls
            except ImportError:
                from tls import ensure_hub_tls
            tls_info = ensure_hub_tls()
            cert_path = tls_info["cert_path"]
            key_path = tls_info["key_path"]
            if os.path.exists(cert_path) and os.path.exists(key_path):
                ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                ssl_ctx.load_cert_chain(certfile=cert_path, keyfile=key_path)
                server.socket = ssl_ctx.wrap_socket(server.socket, server_side=True)
                is_tls = True
                print(f"[*] TLS encryption active (SHA256: {tls_info['fingerprint_short']}...)")
        except Exception as te:
            print(f"[!] Warning: TLS initialization failed ({te}), falling back to plain HTTP", file=sys.stderr)

    protocol = "https" if is_tls else "http"
    print(f"[*] Knot Swarm Blackboard Hub listening on {protocol}://0.0.0.0:{port}")
    print(f"[*] Database: {db_path} (WAL mode active)")
    print(f"[*] Web Cockpit available at: {protocol}://0.0.0.0:{port}/kafe")

    stop_event = threading.Event()
    reaper_thread = threading.Thread(target=lease_reaper_loop, args=(db, stop_event), daemon=True)
    reaper_thread.start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Shutting down Knot Hub...")
    finally:
        stop_event.set()
        server.server_close()


if __name__ == "__main__":
    main()
