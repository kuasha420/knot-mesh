# Knot Mesh 🪢⚡

[![Platform: Arch Linux / EndeavourOS](https://img.shields.io/badge/Platform-Arch%20Linux%20%7C%20EndeavourOS-1793d1.svg?style=flat-square&logo=arch-linux)](https://archlinux.org)
[![Desktop: KDE Plasma 6 Wayland](https://img.shields.io/badge/Desktop-KDE%20Plasma%206%20Wayland-1d99f3.svg?style=flat-square&logo=kde)](https://kde.org/plasma-desktop/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
[![Release: v1.0.0--rc5](https://img.shields.io/badge/Release-v1.0.0--rc5-blue.svg?style=flat-square)](#)

> **Distributed Workspace Mesh for Arch Linux & KDE Plasma 6 Wayland.**  
> Seamlessly weave multiple Linux workstations, roaming laptops, and handheld gaming PCs into a unified, context-aware physical computing fabric with Wayland-native spatial KVM, zero-prompt AI agent orchestration, and hardware-fenced security.

> **Historical Note**: Knot Mesh is the standalone open-source successor to the private multi-device GitOps prototype `knot`.  
> Active development and public releases take place exclusively in this repository.

---

## ⚡ Quickstart

Install Knot Mesh on your primary workstation and client devices in seconds:

```bash
curl -fsSL https://raw.githubusercontent.com/kuasha420/knot-mesh/main/install.sh | bash
```

Bootstrap an Anchor workstation:
```bash
knot-installer init --name "Home Studio"
```

Invite laptops and handhelds to the swarm:
```bash
knot-installer invite
```

---

## 🖥️ Physical Workspace Topology

Knot compiles declarative multi-screen layouts with bidirectional edge boundaries, reciprocal fractional spans, and sub-pixel Wayland cursor routing:

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                           ANCHOR WORKSTATION (desktop)                       │
│                        3440 x 1440 @ 144Hz Ultrawide                         │
│                                                                              │
└───────▲───────────────────────────▲──────────────────────────────▲───────────┘
        │ [0..25% span]             │ [25..75% span]               │ [75..100% span]
        ▼                           ▼                              ▼
┌───────────────┐           ┌───────────────┐              ┌───────────────┐
│               │           │               │              │               │
│    LAPTOP     │           │   ROG ALLY    │              │  STEAM DECK   │
│   (@laptop)   │           │  (@rog-ally)  │              │ (@steamdeck)  │
│  1920 x 1080  │           │  1920 x 1080  │              │  1280 x 800   │
│   @ 60Hz      │           │   @ 120Hz     │              │   @ 60Hz      │
│  Left Flank   │           │  Dock / Left  │              │  Dock / Right │
└───────────────┘           └───────────────┘              └───────────────┘
```

---

## 🏛️ The Six Core Pillars

1. **🌐 Zero-Friction Distributed Workspace**  
   Move your mouse cursor fluidly across physical machines. Leverages Deskflow with a custom C `libportal` InputCapture shim tailored specifically for KWin Wayland session semantics.

2. **🤖 Zero-Prompt Antigravity Multi-Agent Orchestration**  
   Built-in Model Context Protocol (MCP) server (`core/mcp/gateway.py`) and pre-approved operational skills (`knot-swarm`, `core-mesh`, `vision`, `remote-control`) grant agents headless mesh execution, shared memory palace recall, and distributed task fanout across nodes without human prompts.

3. **💡 Ambient Spatial Awareness & Wayland LayerShell Strips**  
   Subtle, low-opacity PyQt6 Wayland LayerShell edge indicators (`knot-stripd`) glow softly along physical display boundaries, flashing dynamic visual cues when the cursor traverses between machines.

4. **🔐 Cryptographic Pairing & Declarative Swarms**  
   Pair nodes in under 10 seconds via ephemeral 6-digit PIN tokens and pinned TLS certificate fingerprints. Swarms (`home`, `office`, `lab`) declare their topologies, members, and policies in human-readable JSON manifests.

5. **⚡ Unified Power & Session Management**  
   One command unlocks, locks, or shuts down the fleet. Unlocking the Anchor workstation dynamically triggers `plasma-login-manager` headless session resumption across all docked Strands.

6. **🛡️ NetworkManager Roaming Guard & PAM Sudo Gates**  
   `knot-guard` continuously verifies router BSSIDs and Gateway MACs. On trusted home/office Wi-Fi, passwordless `sudo` is dynamically authorized; on public Wi-Fi (cafes, airports), KVM is instantly isolated and sudo demotes to password authentication.

---

## 📚 Documentation Suite

For complete configuration, operational manuals, and architecture deep dives:

- 🚀 **[Getting Started Guide](docs/GETTING_STARTED.md)**: Zero-to-mesh walkthrough, Anchor setup, and token invite pairing.
- 📖 **[CLI Reference Manual](docs/CLI_REFERENCE.md)**: Complete command reference for `knot` and `knot-installer`.
- 🌐 **[Swarm Operations & Roaming](docs/SWARM_OPERATIONS.md)**: Multi-tenant profiles, hardware fencing, and fleet orchestration.
- 🛡️ **[Firewall & Ports](docs/FIREWALL.md)**: Subnet-scoped port requirements (4242, 24800, 5353, 1714–1764) and UFW/firewalld rules.
- 🏛️ **[System Architecture](docs/SWARM_PRIOR_ARTS_AND_ARCHITECTURE.md)**: Tuplespace blackboard hub, Wayland LayerShell stack, and prior arts.
- 🗺️ **[Vision & Roadmap](docs/SWARM_VISION_AND_ROADMAP.md)**: Design philosophy, autonomous agent pairing, and future milestones.

---

## 📜 License

Released under the [MIT License](LICENSE). Copyright (c) 2026 kuasha420.
