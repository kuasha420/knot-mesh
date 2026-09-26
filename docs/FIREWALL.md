# Firewall & Network Configuration Guide 🛡️🔌

Knot Mesh uses local network sockets to coordinate pinned TLS Hub communications, Deskflow KVM cursor routing, KDE Connect clipboard synchronization, and mDNS peer discovery.

This guide outlines required ports, security considerations, and automated/manual firewall configuration.

---

## Table of Contents

- [Required Network Ports](#required-network-ports)
- [Security Architecture & Subnet Scoping](#security-architecture--subnet-scoping)
- [Automated Firewall Configuration](#automated-firewall-configuration)
- [Manual Configuration: UFW](#manual-configuration-ufw)
- [Manual Configuration: firewalld](#manual-configuration-firewalld)
- [Manual Configuration: nftables](#manual-configuration-nftables)
- [Verification & Diagnostics](#verification--diagnostics)

---

## Required Network Ports

All Knot Mesh ports are designed to be **scoped strictly to your trusted local subnet** (e.g. `192.168.1.0/24`). Never expose these ports to the public internet.

| Port | Protocol | Service | Description | Direction |
| :--- | :--- | :--- | :--- | :--- |
| **4242** | TCP | Knot Hub | Pinned TLS REST API & SSE Rendezvous | Ingress on Anchor |
| **24800** | TCP | Deskflow KVM | Wayland Mouse & Keyboard Multiplexing | Ingress on Anchor |
| **1714–1764** | TCP + UDP | KDE Connect | Full-Mesh Clipboard & Notification Sync | Bidirectional Fleet |
| **5353** | UDP | mDNS / Avahi | Zero-Config Local Hostname Resolution | Multicast LAN |
| **5900–5910** | TCP | Knot Virtual Monitor | Wayland Virtual Screen RDP Stream (krdpserver/krdc) | Ingress on Host |
| **22** | TCP | OpenSSH (Std) | Secure Remote Administration & Sync | Ingress all nodes |
| **42069** | TCP | OpenSSH (Knot) | Dedicated Knot Hardened Key-Only Port (if set) | Ingress all nodes |

---

## Security Architecture & Subnet Scoping

Knot Mesh enforces strict boundary protection:

1. **Subnet-Scoped Ingress**:
   - Ingress rules should only accept packets originating from within your local LAN CIDR block (e.g. `192.168.1.0/24`).
   - Any packets from outside the subnet are dropped by default firewall policies.

2. **Pinned TLS**:
   - Knot Hub communicates over TLS with certificates validated against SHA-256 fingerprints embedded in enrollment tokens.
   - Self-signed certificates are rejected unless verified against the local CA in `~/.config/knot/tls/`.

3. **Public Network Isolation**:
   - When a roaming node connects to an untrusted Wi-Fi network, `knot-guard` isolates KVM and drops dynamic sudo privileges, ensuring the device remains secure even if ports are probed on public networks.

---

## Automated Firewall Configuration

Knot Mesh includes automated firewall detection and rule injection in `core/modules/firewall.sh`.

Both `knot-installer init` and `knot-installer join` execute `firewall_configure` automatically during setup. To bypass automated firewall changes, pass `--skip-firewall`:

```bash
knot-installer init --skip-firewall
knot-installer join <anchor_endpoint> <token> --skip-firewall
```

To invoke automated configuration manually at any time:

```bash
# Source core modules and apply rules
source /usr/share/knot-mesh/core/lib.sh
source /usr/share/knot-mesh/core/modules/firewall.sh
firewall_configure
```

---

## Manual Configuration: UFW

If you manage your firewall using **UFW** (Uncomplicated Firewall):

```bash
# Replace 192.168.1.0/24 with your actual local subnet CIDR
SUBNET="192.168.1.0/24"

# 1. Allow OpenSSH (standard port 22 and optional custom port 42069)
sudo ufw insert 1 allow from "$SUBNET" to any port 22 proto tcp comment 'knot-ssh'
sudo ufw insert 2 allow from "$SUBNET" to any port 42069 proto tcp comment 'knot-ssh-alt'

# 2. Allow Knot Hub TLS (4242)
sudo ufw insert 3 allow from "$SUBNET" to any port 4242 proto tcp comment 'knot-hub'

# 3. Allow Deskflow KVM (24800)
sudo ufw insert 4 allow from "$SUBNET" to any port 24800 proto tcp comment 'knot-kvm'

# 4. Allow mDNS Multicast (5353)
sudo ufw insert 5 allow from "$SUBNET" to any port 5353 proto udp comment 'knot-mdns'

# 5. Allow KDE Connect (1714:1764 TCP & UDP)
sudo ufw insert 6 allow from "$SUBNET" to any port 1714:1764 proto tcp comment 'knot-kde-tcp'
sudo ufw insert 7 allow from "$SUBNET" to any port 1714:1764 proto udp comment 'knot-kde-udp'

# 6. Allow Wayland Virtual Monitor RDP streams (5900:5910 TCP)
sudo ufw insert 8 allow from "$SUBNET" to any port 5900:5910 proto tcp comment 'knot-vmon'

# Reload UFW
sudo ufw reload
```

---

## Manual Configuration: firewalld

If you manage your firewall using **firewalld**:

```bash
# Replace 192.168.1.0/24 with your actual local subnet CIDR
SUBNET="192.168.1.0/24"

# 1. Enable services
sudo firewall-cmd --permanent --zone=public --add-service=ssh
sudo firewall-cmd --permanent --zone=public --add-service=kdeconnect
sudo firewall-cmd --permanent --zone=public --add-service=mdns

# 2. Allow Hub, KVM & Virtual Monitor ports
sudo firewall-cmd --permanent --zone=public --add-port=4242/tcp
sudo firewall-cmd --permanent --zone=public --add-port=24800/tcp
sudo firewall-cmd --permanent --zone=public --add-port=5900-5910/tcp

# 3. Add rich rules scoped to local subnet
sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$SUBNET\" port port=\"4242\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$SUBNET\" port port=\"24800\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$SUBNET\" port port=\"5900-5910\" protocol=\"tcp\" accept"
sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$SUBNET\" port port=\"42069\" protocol=\"tcp\" accept"

# Reload firewalld
sudo firewall-cmd --reload
```

---

## Manual Configuration: nftables

If using raw **nftables**, add the following rules to your `inet filter input` chain in `/etc/nftables.conf`:

```text
table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # Accept loopback & established connections
        iif "lo" accept
        ct state established,related accept

        # Knot Mesh Subnet-Scoped Ingress
        ip saddr 192.168.1.0/24 tcp dport { 22, 4242, 24800, 42069 } accept comment "Knot TCP Services"
        ip saddr 192.168.1.0/24 tcp dport 5900-5910 accept comment "Knot Virtual Monitor RDP"
        ip saddr 192.168.1.0/24 tcp dport 1714-1764 accept comment "KDE Connect TCP"
        ip saddr 192.168.1.0/24 udp dport 1714-1764 accept comment "KDE Connect UDP"
        ip saddr 192.168.1.0/24 udp dport 5353 accept comment "mDNS Multicast"
    }
}
```

Reload nftables:
```bash
sudo nft -f /etc/nftables.conf
```

---

## Verification & Diagnostics

To verify firewall readiness across your mesh, run `knot doctor`:

```bash
knot doctor local
```

The diagnostic engine checks:
1. Active firewall daemon detection (`UFW`, `firewalld`, or `none`).
2. Listening socket verification for ports 4242, 24800, and SSH.
3. Ingress rule reachability from remote nodes.

To check UFW status manually:
```bash
sudo ufw status verbose
```

To check firewalld status manually:
```bash
sudo firewall-cmd --list-all
```
