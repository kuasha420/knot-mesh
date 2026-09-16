# Knot Mesh 🪢⚡

[![Platform: Arch Linux / EndeavourOS](https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20EndeavourOS-1793d1.svg?style=flat-square&logo=arch-linux)](https://archlinux.org)
[![Desktop: KDE Plasma 6 Wayland](https://img.shields.io/badge/Desktop-KDE%20Plasma%206%20Wayland-1d99f3.svg?style=flat-square&logo=kde)](https://kde.org/plasma-desktop/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Release: v1.0.0--rc1](https://img.shields.io/badge/Release-v1.0.0--rc1-blue.svg?style=flat-square)](#)

> **Distributed Workspace Mesh for Arch Linux & KDE Plasma 6 Wayland.**
> Seamlessly weave multiple Linux devices—powerful workstations, roaming laptops, and handheld PCs—into a unified, context-aware physical computing fabric.

---

## 🌟 Key Capabilities

- 🌐 **Multi-Anchor Network Roaming**: Roaming devices (laptops, handhelds) dynamically switch active swarm profiles (`home`, `office`, `campus`) based on hardware network fencing (Gateway MAC & BSSID).
- 🛡️ **Graceful Standalone Mode**: Connect to public Wi-Fi (cafes, airports) safely. Knot automatically isolates cross-node KVM, disables passwordless sudo, and leaves hardened OpenSSH active with rate limiting.
- 🖥️ **Wayland-Native Spatial KVM**: Cursor transitions fluidly between monitors using Deskflow and a persistent C `libportal` InputCapture shim tailored for KWin Wayland.
- 🔐 **Cryptographic Zero-Friction Pairing**: Pair new nodes in seconds using ephemeral 6-digit PIN tokens over pinned TLS without manual SSH key wrangling.
- 🔑 **Dynamic PAM Sudo Gate**: Passwordless `sudo` is securely gated by physical network fencing and client IP subnet verification.
- 💻 **Wayland Boundary Indicators**: PyQt6 LayerShell overlays visually signal cursor boundary transitions between physical screens.

---

## 🏛 System Architecture

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

## 🚀 Quickstart

### Prerequisites
- **Operating System**: Arch Linux or EndeavourOS
- **Desktop Environment**: KDE Plasma 6 (Wayland session)
- **Privileges**: Standard user with `sudo` access

### 1. One-Line Installation
```bash
curl -fsSL https://raw.githubusercontent.com/kuasha420/knot-mesh/main/install.sh | bash
```

### 2. Initialize an Anchor (Primary Workstation)
```bash
knot-installer init
```
This configures your network fence, generates the persistent TLS certificate, enables `knot-hub.service`, and outputs an invite command.

### 3. Generate an Invite for a Strand
```bash
knot-installer invite
```
Prints a composite token with a terminal QR code and waits for the incoming connection to interactively assign screen position:
```text
knot-installer join 192.168.1.50:4242 --token 749201.a1b2c3d4e5f6...
```

### 4. Join a Strand (Laptop or Handheld)
On the client machine:
```bash
knot-installer join 192.168.1.50:4242 --token 749201.a1b2c3d4e5f6...
```
The client automatically detects screen resolution via `kscreen-doctor`, establishes a pinned TLS session, and configures roaming daemons.

---

## ⚡ CLI Command Suite

| Command | Description |
| :--- | :--- |
| `knot status` | Live swarm telemetry, active profile, and peer status |
| `knot-installer init` | Initialize local host as a Swarm Anchor |
| `knot-installer join` | Enroll local host as a Strand to an Anchor |
| `knot-installer invite` | Generate 6-digit pairing token and wait for rendezvous |
| `knot-installer migrate` | Migrate legacy v1.0 configs into multi-swarm profiles |
| `knot-installer doctor` | Comprehensive diagnostic check for Wayland, portals, and PAM |
| `knot-installer uninstall` | Clean, non-destructive removal of hooks and services |

---

## 📜 License
Released under the [MIT License](LICENSE). Copyright (c) 2026 kuasha420.
