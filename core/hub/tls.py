#!/usr/bin/env python3
"""
Knot Mesh TLS Certificate Authority & Fingerprint Engine
Manages persistent self-signed TLS certificates for Knot Hub and extracts
cryptographic SHA-256 fingerprints for pinned client handshakes.
"""

import os
import sys
import base64
import hashlib
import socket
import subprocess
import tempfile
from typing import Dict, List, Optional, Tuple


def detect_local_ips() -> List[str]:
    """Detects local IPv4 addresses for Subject Alternative Names (SAN)."""
    ips = ["127.0.0.1"]
    try:
        # Use ip -4 addr show to find non-loopback IPs
        out = subprocess.check_output(
            ["ip", "-4", "addr", "show", "scope", "global"],
            text=True, stderr=subprocess.DEVNULL
        )
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("inet "):
                parts = line.split()
                if len(parts) >= 2:
                    ip = parts[1].split("/")[0]
                    if ip not in ips:
                        ips.append(ip)
    except Exception as e:
        sys.stderr.write(f"Notice: [tls] Hostname IP lookup failed: {e}\n")
        # Fallback socket lookup
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            if ip not in ips:
                ips.append(ip)
        except Exception as fe:
            sys.stderr.write(f"Notice: [tls] Fallback UDP socket IP lookup failed: {fe}\n")
    return ips


def detect_local_dns() -> List[str]:
    """Detects local hostnames for Subject Alternative Names (SAN)."""
    dns = ["localhost"]
    host = socket.gethostname()
    if host and host not in dns:
        dns.append(host)
        if not host.endswith(".local"):
            dns.append(f"{host}.local")
    return dns


def generate_self_signed_cert(
    cert_path: str,
    key_path: str,
    san_ips: Optional[List[str]] = None,
    san_dns: Optional[List[str]] = None,
    days: int = 3650
) -> bool:
    """
    Generates a persistent RSA 2048-bit self-signed certificate with SAN.
    Valid for 10 years by default.
    """
    if san_ips is None:
        san_ips = detect_local_ips()
    if san_dns is None:
        san_dns = detect_local_dns()

    san_parts = [f"IP:{ip}" for ip in san_ips] + [f"DNS:{d}" for d in san_dns]
    san_str = ",".join(san_parts)

    openssl_cnf = f"""
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = Knot Swarm Hub

[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = {san_str}
"""

    os.makedirs(os.path.dirname(os.path.abspath(cert_path)), exist_ok=True)
    os.makedirs(os.path.dirname(os.path.abspath(key_path)), exist_ok=True)

    with tempfile.NamedTemporaryFile("w", suffix=".cnf", delete=False) as f:
        cnf_path = f.name
        f.write(openssl_cnf)

    try:
        cmd = [
            "openssl", "req", "-x509",
            "-newkey", "rsa:2048",
            "-nodes",
            "-keyout", key_path,
            "-out", cert_path,
            "-days", str(days),
            "-config", cnf_path
        ]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            sys.stderr.write(f"[knot-tls] OpenSSL certificate generation failed: {res.stderr}\n")
            return False

        os.chmod(key_path, 0o600)
        os.chmod(cert_path, 0o644)
        return True
    finally:
        if os.path.exists(cnf_path):
            os.remove(cnf_path)


def get_cert_fingerprint(cert_path: str, short: bool = False) -> str:
    """
    Extracts the SHA-256 fingerprint from a PEM certificate.
    Returns standard hex string (or first 16 characters if short=True).
    """
    if not os.path.exists(cert_path):
        raise FileNotFoundError(f"Certificate not found at {cert_path}")

    with open(cert_path, "r") as f:
        content = f.read()

    # Extract base64 DER payload between PEM markers
    lines = content.strip().splitlines()
    b64_lines = [
        line for line in lines
        if not line.startswith("-----BEGIN") and not line.startswith("-----END")
    ]
    der_bytes = base64.b64decode("".join(b64_lines))
    digest = hashlib.sha256(der_bytes).hexdigest().lower()

    if short:
        return digest[:16]
    return digest


def ensure_hub_tls(custom_dir: Optional[str] = None) -> Dict[str, str]:
    """
    Ensures persistent Hub TLS certificate exists, generating if needed.
    Returns dict with cert_path, key_path, fingerprint, and fingerprint_short.
    """
    if custom_dir:
        tls_dir = custom_dir
    elif os.geteuid() == 0 or os.access("/etc", os.W_OK):
        tls_dir = "/etc/knot/tls"
    else:
        user_home = os.environ.get("HOME", os.path.expanduser("~"))
        tls_dir = os.path.join(user_home, ".config/knot/tls")

    os.makedirs(tls_dir, mode=0o700, exist_ok=True)
    cert_path = os.path.join(tls_dir, "hub.crt")
    key_path = os.path.join(tls_dir, "hub.key")

    if not os.path.exists(cert_path) or not os.path.exists(key_path):
        success = generate_self_signed_cert(cert_path, key_path)
        if not success:
            raise RuntimeError(f"Failed to generate persistent Hub TLS certificate in {tls_dir}")

    fp = get_cert_fingerprint(cert_path)
    fp_short = get_cert_fingerprint(cert_path, short=True)

    return {
        "tls_dir": tls_dir,
        "cert_path": cert_path,
        "key_path": key_path,
        "fingerprint": fp,
        "fingerprint_short": fp_short,
    }


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "fingerprint":
        target = sys.argv[2] if len(sys.argv) > 2 else "/etc/knot/tls/hub.crt"
        print(get_cert_fingerprint(target))
    else:
        info = ensure_hub_tls()
        print(f"Hub TLS Ready:")
        print(f"  Certificate: {info['cert_path']}")
        print(f"  Private Key: {info['key_path']}")
        print(f"  Fingerprint: {info['fingerprint']}")
        print(f"  Short Token: {info['fingerprint_short']}")
