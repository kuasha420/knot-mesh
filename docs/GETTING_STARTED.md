# Getting Started with Knot Mesh 🪢⚡

Welcome to Knot Mesh! This guide walks you through setting up a distributed workspace across your Linux workstations, laptops, and handheld PCs running Arch Linux and KDE Plasma 6 Wayland.

---

## Table of Contents

- [Overview & Architecture](#overview--architecture)
- [Prerequisites](#prerequisites)
- [Step 1: Install Knot Mesh](#step-1-install-knot-mesh)
- [Step 2: Bootstrap the Anchor Workstation](#step-2-bootstrap-the-anchor-workstation)
- [Step 3: Generate an Enrollment Invitation](#step-3-generate-an-enrollment-invitation)
- [Step 4: Connect Strands (Laptops & Handhelds)](#step-4-connect-strands-laptops--handhelds)
- [Step 5: Interactive Spatial Screen Placement](#step-5-interactive-spatial-screen-placement)
- [Step 6: Verify Mesh Health](#step-6-verify-mesh-health)
- [Next Steps](#next-steps)

---

## Overview & Architecture

A Knot Mesh swarm consists of two node roles:

1. **Anchor**:
   - The primary workstation (e.g. multi-monitor desktop or stationary docked PC).
   - Hosts the **Knot Hub** (`knot-hub.service`) on pinned TLS port `4242`.
   - Runs the **Deskflow KVM Server** (`knot-deskflow.service`) on port `24800`.
   - Acts as the single source of truth for swarm profiles and declarative topologies.

2. **Strand**:
   - Roaming or secondary machines (laptops, handheld gaming consoles like Steam Deck or ROG Ally).
   - Connects to the Anchor over local Wi-Fi / LAN.
   - Runs the **Deskflow KVM Client** runner to seamlessly receive keyboard, mouse, and clipboard focus.
   - Monitors physical networks via `knot-guard.service` to switch swarms or isolate safely on public Wi-Fi.

```
                    ┌─────────────────────────────────────────┐
                    │          Anchor (Workstation)           │
                    │  - Knot Hub (HTTPS / SSE API :4242)     │
                    │  - Deskflow Server (KVM :24800)         │
                    │  - Spatial Topology Compiler            │
                    └───────────────────▲─────────────────────┘
                                        │
                Pinned TLS Handshake &  │  Deskflow Wayland
                Dynamic Peer Discovery  │  Input Capture Shim
                                        │
                    ┌───────────────────▼─────────────────────┐
                    │             Roaming Strand              │
                    │  - NetworkManager Dispatcher Guard      │
                    │  - Dynamic PAM Sudo Gate                │
                    │  - Wayland LayerShell Boundary Strip    │
                    └─────────────────────────────────────────┘
```

---

## Prerequisites

Before starting, ensure all machines meet these requirements:

- **Operating System**: Arch Linux, EndeavourOS, or SteamOS 3.5+ (developer mode).
- **Desktop Environment**: KDE Plasma 6 running in a **native Wayland session**.
- **User Account**: Standard user with `sudo` privileges.
- **Network**: All devices connected to the same local Wi-Fi / LAN subnet (or bridged network).
- **Packages**: `openssh`, `deskflow` (or `synergy` / `barrier`), `python`, `python-pillow`, `python-numpy`.

---

## Step 1: Install Knot Mesh

Run the bootstrap installer on all workstations and strands:

```bash
curl -fsSL https://raw.githubusercontent.com/kuasha420/knot-mesh/main/install.sh | bash
```

Alternatively, if building from source via `makepkg`:

```bash
git clone https://github.com/kuasha420/knot-mesh.git
cd knot-mesh
makepkg -si
```

This installs:
- Binaries in `/usr/bin/knot` and `/usr/bin/knot-installer` (or `~/.local/bin/`).
- Core modules and Python Tuplespace engine in `/usr/share/knot-mesh/`.
- Systemd user service templates in `~/.config/systemd/user/`.

---

## Step 2: Bootstrap the Anchor Workstation

Choose your primary multi-monitor desktop or stationary workstation to be the **Anchor**.

Run:

```bash
knot-installer init --name "Home Studio" --id "home"
```

### What Happens During `init`:
1. **Persistent TLS CA**: Generates a self-signed Root CA and Hub TLS keypair in `~/.config/knot/tls/`.
2. **Wayland Display Probing**: Queries `kscreen-doctor` to capture screen resolutions, refresh rates, scale factors, and display geometry.
3. **Swarm Profile Creation**: Writes `/etc/knot/swarms.d/home.conf` and `~/.config/knot/swarms/home/swarm.conf` with active Wi-Fi SSID, Gateway MAC fence, and subnet CIDR.
4. **Automated Firewall Configuration**: Opens required mesh ports (4242, 24800, 5353, 1714–1764) in UFW or firewalld scoped strictly to your local subnet.
5. **Antigravity Synchronization**: Syncs MCP tool schemas to `~/.gemini/config/mcp_config.json` and configures maintained operational skills from `runtime/skills/` (`knot-swarm`, `hardware-profiles`, `swarm-council`, `goal-with-lease`).
6. **Service Launch**: Starts `knot-hub.service`, `knot-deskflow.service`, and `knot-guard.service`.

---

## Step 3: Generate an Enrollment Invitation

On the Anchor machine, initiate an invitation session:

```bash
knot-installer invite
```

The terminal prints an enrollment banner:

```text
======================================================================
              KNOT MESH — STRAND ENROLLMENT INVITATION                 
======================================================================
  Pairing PIN:    839201
  Join Token:     839201.cf2e3f93b4fbc23a
  Expires In:     300 seconds

  🪄 Magic Zero-Setup Onboarding (copy & paste in terminal on Strand):
    curl -kfsSL https://192.168.1.50:4242/join/839201.cf2e3f93b4fbc23a | bash

  🌐 Web Onboarding Page:
    https://192.168.1.50:4242/join/839201.cf2e3f93b4fbc23a

  Or if Knot is already installed:
    knot-installer join 192.168.1.50:4242 839201.cf2e3f93b4fbc23a
======================================================================
Waiting for Strand rendezvous connection (timeout: 300s)...
```

---

## Step 4: Connect Strands (Laptops & Handhelds)

On your laptop or handheld device (e.g. Steam Deck or ROG Ally):

### Option A: Magic One-Liner (Zero-Setup)
```bash
curl -kfsSL https://192.168.1.50:4242/join/839201.cf2e3f93b4fbc23a | bash
```

### Option B: Using Installed CLI
```bash
knot-installer join 192.168.1.50:4242 839201.cf2e3f93b4fbc23a
```

### What the Strand Does:
1. Validates the Anchor's TLS certificate against the token fingerprint.
2. Extracts its Wayland screen resolution and refresh rate via `kscreen-doctor`.
3. Sends its Ed25519 SSH public key and hardware specs to the Anchor.
4. Receives the swarm profile, Anchor SSH public key, and TLS trust roots.
5. Starts `knot-agent.service` and `knot-guard.service`.

---

## Step 5: Interactive Spatial Screen Placement

Once the Strand connects, the Anchor terminal updates with an interactive prompt:

```text
[✓] Strand connected: laptop

Where is 'laptop' positioned relative to this Anchor?
  [1] Left (default)
  [2] Right
  [3] Above / Up
  [4] Below / Down
  [5] Headless (No KVM screen)
Select placement [1-5 or Left/Right/Above/Below/Headless] (1): 1
```

1. Enter your placement (e.g. `1` for Left).
2. The Anchor immediately compiles a reciprocal `deskflow.conf`:
   - Cursor moving off the left edge of the desktop enters the laptop.
   - Cursor moving off the right edge of the laptop returns to the desktop.
3. The Deskflow server reloads smoothly without dropping connections.

---

## Step 6: Verify Mesh Health

Run `knot doctor` on the Anchor:

```bash
knot doctor local
```

You should see all green checks:
```text
[✓] Knot Active Swarm: home
[✓] Hub TLS Certificate valid
[✓] Deskflow KVM Server active (3 connected clients)
[✓] Dynamic PAM passwordless sudo active
[✓] SSH Key Mesh synchronized
[✓] All services operational
```

To view live fleet status across all nodes:

```bash
knot status
```

To test cross-machine execution:

```bash
knot exec --all "hostname; uptime"
```

To bootstrap and verify KDE Connect clipboard sharing across the entire mesh:

```bash
# 1. Automated zero-interaction pairing across all strands
knot kdeconnect pair --all

# 2. Check fleet-wide connection & clipboard status
knot kdeconnect status --all

# 3. Verify end-to-end clipboard synchronization
knot kdeconnect test-clipboard --all
```

---

## Next Steps

- Explore [CLI Reference Manual](CLI_REFERENCE.md) for full syntax and options.
- Read [Swarm Operations & Roaming Guide](SWARM_OPERATIONS.md) to configure multiple swarms (e.g. `office` vs `home`).
- Consult [Firewall & Network Configuration](FIREWALL.md) for network port details.
