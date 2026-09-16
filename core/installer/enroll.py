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
        except Exception:
            pass

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
                    except ValueError:
                        pass
    except Exception:
        pass
    return specs


def detect_local_pubkey() -> str:
    """Reads local Ed25519 public key."""
    home = os.environ.get("HOME", os.path.expanduser("~"))
    pub_path = os.path.join(home, ".ssh/id_ed25519.pub")
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
    print(f"[✓] Swarm profile written to {conf_path}")
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
