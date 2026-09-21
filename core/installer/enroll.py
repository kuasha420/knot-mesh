#!/usr/bin/env python3
"""
Knot Mesh Strand Enrollment Client
Connects to an Anchor Hub over pinned TLS, submits local node manifests,
and completes cryptographic mutual enrollment.
"""

import os
import sys
import json
import ssl
import socket
import hashlib
import argparse
import subprocess
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from typing import Dict, Any, Tuple, Optional


class EnrollmentSecurityError(Exception):
    """Raised when TLS fingerprint validation or cryptographic handshake fails."""
    pass


def parse_token(token: str) -> Tuple[str, str]:
    """Parses a composite token <pin>.<fingerprint>."""
    if "." not in token:
        raise ValueError(f"Invalid token format '{token}'. Expected <PIN>.<FINGERPRINT_SHORT>")
    pin, fp = token.split(".", 1)
    return pin.strip(), fp.strip().lower()


def get_peer_cert_fingerprint(host: str, port: int) -> str:
    """
    Connects to remote host and retrieves the SHA-256 fingerprint
    of the presented TLS certificate.
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    with socket.create_connection((host, port), timeout=10) as sock:
        with ctx.wrap_socket(sock, server_hostname=host) as ssock:
            der_cert = ssock.getpeercert(binary_form=True)
            if not der_cert:
                raise EnrollmentSecurityError("Failed to retrieve peer TLS certificate")
            return hashlib.sha256(der_cert).hexdigest().lower()


def detect_display_specs() -> Dict[str, Any]:
    """Detects active display specs via core/installer/display.sh or fallbacks."""
    knot_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    display_sh = os.path.join(knot_root, "core", "installer", "display.sh")
    if os.path.isfile(display_sh):
        try:
            out = subprocess.check_output(["bash", display_sh, "--json"], text=True)
            return json.loads(out)
        except Exception as e:
            sys.stderr.write(f"Notice: [enroll] Failed to read display.sh specs: {e}\n")

    specs = {
        "resolution": "1920x1080",
        "refresh_rate": 60.0,
        "scale": 1.0
    }
    if not shutil_which("kscreen-doctor"):
        return specs

    try:
        out = subprocess.check_output(["kscreen-doctor", "-o"], text=True)
        # Strip ANSI
        import re
        out_clean = re.sub(r'\x1b\[[0-9;]*[a-zA-Z]', '', out)
        for line in out_clean.splitlines():
            line = line.strip()
            if "Modes:" in line:
                m = re.search(r'([0-9]+)x([0-9]+)@([0-9.]+)\*', line)
                if m:
                    specs["resolution"] = f"{m.group(1)}x{m.group(2)}"
                    specs["refresh_rate"] = float(m.group(3))
            elif "Scale:" in line:
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        specs["scale"] = float(parts[1])
                    except ValueError as ve:
                        sys.stderr.write(f"Notice: [enroll] Invalid scale format: {ve}\n")
    except Exception as e:
        sys.stderr.write(f"Notice: [enroll] kscreen-doctor detection failed: {e}\n")
    return specs


def detect_local_pubkey() -> str:
    """Reads local Ed25519 public key, auto-generating one if missing."""
    home = os.environ.get("HOME", os.path.expanduser("~"))
    pub_path = os.path.join(home, ".ssh/id_ed25519.pub")
    key_path = os.path.join(home, ".ssh/id_ed25519")
    if not os.path.exists(pub_path):
        os.makedirs(os.path.join(home, ".ssh"), mode=0o700, exist_ok=True)
        try:
            subprocess.run(
                ["ssh-keygen", "-t", "ed25519", "-N", "", "-f", key_path, "-C", f"{os.environ.get('USER', 'knot')}@{socket.gethostname()}"],
                check=True,
                capture_output=True
            )
        except Exception as e:
            sys.stderr.write(f"Notice: [enroll] ssh-keygen failed: {e}\n")
    if os.path.exists(pub_path):
        with open(pub_path, "r") as f:
            return f.read().strip()
    return ""


def detect_node_capabilities() -> list[str]:
    """Detects local hardware capabilities."""
    caps = ["strand", socket.gethostname().lower()]
    # Check GPU
    if shutil_which("nvidia-smi"):
        caps.append("gpu_cuda")
    elif os.path.exists("/dev/dri"):
        caps.append("gpu")
    # Check battery (mobile device)
    if os.path.exists("/sys/class/power_supply"):
        for ps in os.listdir("/sys/class/power_supply"):
            if "BAT" in ps:
                caps.append("battery")
                caps.append("laptop")
                break
    return caps


def shutil_which(cmd: str) -> Optional[str]:
    import shutil
    return shutil.which(cmd)


def enroll_strand(
    anchor_addr: str,
    token: str,
    node_id: Optional[str] = None,
    role: str = "strand",
    custom_resolution: Optional[str] = None,
    custom_scale: Optional[float] = None
) -> Dict[str, Any]:
    """
    Executes the cryptographic Strand enrollment handshake.
    """
    pin, expected_fp = parse_token(token)

    # Parse Anchor address
    if ":" in anchor_addr:
        anchor_host, port_str = anchor_addr.split(":", 1)
        anchor_port = int(port_str)
    else:
        anchor_host = anchor_addr
        anchor_port = 4242

    print(f"[*] Verifying TLS certificate for Anchor {anchor_host}:{anchor_port}...")
    actual_fp = get_peer_cert_fingerprint(anchor_host, anchor_port)

    # Strict Pinning Check
    if not actual_fp.startswith(expected_fp):
        raise EnrollmentSecurityError(
            f"\n🚨 SECURITY ALERT: TLS Certificate Fingerprint Mismatch!\n"
            f"   Expected: {expected_fp}\n"
            f"   Received: {actual_fp}\n"
            f"Potential Man-In-The-Middle (MITM) attack or expired invite token. Aborting!"
        )

    print(f"[✓] TLS certificate verified and pinned: {actual_fp[:16]}...")

    if not node_id:
        node_id = socket.gethostname()

    display_specs = detect_display_specs()
    if custom_resolution:
        display_specs["resolution"] = custom_resolution
    if custom_scale:
        display_specs["scale"] = custom_scale

    pubkey = detect_local_pubkey()
    user = os.environ.get("USER", "user")

    payload = {
        "pin": pin,
        "node_id": node_id,
        "hostname": socket.gethostname(),
        "role": role,
        "user": user,
        "port": 22,
        "pubkey": pubkey,
        "display": display_specs,
        "capabilities": detect_node_capabilities()
    }

    url = f"https://{anchor_host}:{anchor_port}/swarm/enroll/join"
    req_data = json.dumps(payload).encode("utf-8")

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    req = Request(url, data=req_data, headers={"Content-Type": "application/json"}, method="POST")

    print(f"[*] Submitting enrollment request for '{node_id}' to Anchor...")
    print(f"[*] Waiting for Anchor administrator approval...")

    try:
        with urlopen(req, context=ctx, timeout=130) as resp:
            resp_body = resp.read().decode("utf-8")
            result = json.loads(resp_body)
            print(f"[✓] Enrollment Approved by Anchor! Placement: [{result.get('placement', 'unmapped')}]")
            return result
    except HTTPError as he:
        err_msg = he.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"Anchor rejected enrollment (HTTP {he.code}): {err_msg}")
    except URLError as ue:
        raise RuntimeError(f"Connection to Anchor failed: {ue.reason}")


def save_swarm_profile(enrollment_result: Dict[str, Any], anchor_host: str) -> str:
    """Writes the received swarm profile into /etc/knot/swarms.d/<swarm_id>.conf."""
    swarm_id = enrollment_result.get("swarm_id", "home")
    anchor_id = enrollment_result.get("anchor_id", "desktop")
    hub_port = enrollment_result.get("hub_port", 4242)

    user_home = os.environ.get("HOME", os.path.expanduser("~"))
    if os.geteuid() == 0 or os.access("/etc", os.W_OK):
        conf_dir = "/etc/knot/swarms.d"
    else:
        conf_dir = os.path.join(user_home, f".config/knot/swarms")

    os.makedirs(conf_dir, exist_ok=True)
    conf_path = os.path.join(conf_dir, f"{swarm_id}.conf")

    conf_content = f"""# Knot Swarm Profile: {swarm_id}
SWARM_ID="{swarm_id}"
SWARM_NAME="{swarm_id.capitalize()} Swarm"
ANCHOR_ID="{anchor_id}"
ANCHOR_HOST="{anchor_host}"
HUB_PORT={hub_port}
ALLOW_NOPASSWD_SUDO="true"
ALLOW_DESKFLOW_KVM="true"
"""
    with open(conf_path, "w") as f:
        f.write(conf_content)

    # Also write directory format ~/.config/knot/swarms/<id>/swarm.conf
    swarm_subdir = os.path.join(user_home, ".config/knot/swarms", swarm_id)
    try:
        os.makedirs(swarm_subdir, exist_ok=True)
        with open(os.path.join(swarm_subdir, "swarm.conf"), "w") as f:
            f.write(conf_content)
    except Exception as e:
        sys.stderr.write(f"Notice: [enroll] Failed to write swarm.conf: {e}\n")

    # Automatically activate this newly enrolled swarm
    state_dir = os.path.join(user_home, ".local/state/knot")
    try:
        os.makedirs(state_dir, exist_ok=True)
        with open(os.path.join(state_dir, "active_swarm"), "w") as f:
            f.write(f"{swarm_id}\n")
    except Exception as e:
        sys.stderr.write(f"Notice: [enroll] Failed to write active_swarm to state_dir: {e}\n")

    run_dir = os.environ.get("KNOT_RUNTIME_DIR", "/run/knot")
    if os.path.isdir(run_dir) and os.access(run_dir, os.W_OK):
        try:
            with open(os.path.join(run_dir, "active_swarm"), "w") as f:
                f.write(f"{swarm_id}\n")
        except Exception as e:
            sys.stderr.write(f"Notice: [enroll] Failed to write active_swarm to run_dir: {e}\n")

    # Mutual SSH: Install Anchor public key into Strand authorized_keys
    anchor_pubkey = enrollment_result.get("anchor_pubkey", "").strip()
    if anchor_pubkey:
        ssh_dir = os.path.join(user_home, ".ssh")
        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        auth_file = os.path.join(ssh_dir, "authorized_keys")
        existing_keys = ""
        if os.path.exists(auth_file):
            try:
                with open(auth_file, "r") as f:
                    existing_keys = f.read()
            except Exception as e:
                sys.stderr.write(f"Notice: [enroll] Failed to read authorized_keys: {e}\n")
        if anchor_pubkey not in existing_keys:
            try:
                with open(auth_file, "a") as f:
                    if existing_keys and not existing_keys.endswith("\n"):
                        f.write("\n")
                    f.write(f"{anchor_pubkey}\n")
                os.chmod(auth_file, 0o600)
                print(f"[✓] Anchor SSH public key installed to authorized_keys")
            except Exception as se:
                sys.stderr.write(f"Warning: could not write authorized_keys: {se}\n")

        # Configure ~/.ssh/config entry for Anchor
        ssh_cfg = os.path.join(ssh_dir, "config")
        existing_cfg = ""
        if os.path.exists(ssh_cfg):
            try:
                with open(ssh_cfg, "r") as f:
                    existing_cfg = f.read()
            except Exception as e:
                sys.stderr.write(f"Notice: [enroll] Failed to read ssh config: {e}\n")
        if f"Host {anchor_id}" not in existing_cfg:
            try:
                entry = f"""
# Knot Mesh Anchor Entry
Host {anchor_id} {enrollment_result.get("anchor_hostname", anchor_id)}
    HostName {anchor_host}
    User {os.environ.get("USER", "knot")}
    Port 22
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
    ServerAliveInterval 15
    ServerAliveCountMax 3
"""
                with open(ssh_cfg, "a") as f:
                    f.write(entry)
                os.chmod(ssh_cfg, 0o600)
            except Exception as e:
                sys.stderr.write(f"Notice: [enroll] Failed to write ssh config entry: {e}\n")

    # Fetch authoritative Deskflow TLS certificate directly from Anchor Hub
    tls_dir = os.path.join(user_home, ".config/Deskflow/tls")
    os.makedirs(tls_dir, mode=0o700, exist_ok=True)
    pem_path = os.path.join(tls_dir, "deskflow.pem")
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        cert_url = f"https://{anchor_host}:{hub_port}/dist/deskflow.pem"
        cert_req = Request(cert_url)
        with urlopen(cert_req, context=ctx, timeout=10) as c_resp:
            pem_content = c_resp.read()
            with open(pem_path, "wb") as pf:
                pf.write(pem_content)
            os.chmod(pem_path, 0o600)

            fp_out = subprocess.check_output(
                ["openssl", "x509", "-in", pem_path, "-noout", "-fingerprint", "-sha256"],
                text=True
            )
            raw_fp = fp_out.split("=")[1].strip().replace(":", "").lower()
            with open(os.path.join(tls_dir, "trusted-servers"), "w") as ts:
                ts.write(f"v2:sha256:{raw_fp}\n")
            with open(os.path.join(tls_dir, "trusted-clients"), "w") as tc:
                tc.write(f"v2:sha256:{raw_fp}\n")
            os.chmod(os.path.join(tls_dir, "trusted-servers"), 0o600)
            os.chmod(os.path.join(tls_dir, "trusted-clients"), 0o600)
            print(f"[✓] Authoritative Deskflow TLS certificate synchronized from Anchor ({raw_fp[:16]}...)")
    except Exception as ce:
        sys.stderr.write(f"Notice: Could not sync Deskflow certificate from Anchor: {ce}\n")

    print(f"[✓] Swarm profile written to {conf_path} (active swarm: {swarm_id})")
    return conf_path


def main():
    parser = argparse.ArgumentParser(description="Knot Mesh Strand Enrollment Client")
    parser.add_argument("--anchor", required=True, help="Anchor IP or hostname[:port]")
    parser.add_argument("--token", required=True, help="Pairing token in format <PIN>.<FINGERPRINT>")
    parser.add_argument("--id", dest="node_id", default=None, help="Custom node ID (defaults to hostname)")
    parser.add_argument("--role", default="strand", help="Node role (default: strand)")
    parser.add_argument("--width", type=int, help="Screen width override")
    parser.add_argument("--height", type=int, help="Screen height override")
    parser.add_argument("--scale", type=float, help="Display scale factor override")

    args = parser.parse_args()

    custom_res = None
    if args.width and args.height:
        custom_res = f"{args.width}x{args.height}"

    try:
        result = enroll_strand(
            anchor_addr=args.anchor,
            token=args.token,
            node_id=args.node_id,
            role=args.role,
            custom_resolution=custom_res,
            custom_scale=args.scale
        )
        anchor_host = args.anchor.split(":")[0]
        save_swarm_profile(result, anchor_host)
        print("\n🎉 Strand enrollment completed successfully!")
    except Exception as e:
        print(f"\n[✗] Enrollment failed: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
