# Knot Mesh — Architectural Specification & Design

> **Production-grade distributed workspace mesh for Arch Linux / KDE Plasma 6 Wayland.**

---

## 1. Core Architectural Tenets

1. **Hardware-Anchored Network Fencing**: Swarm association is determined strictly by physical layer network hardware identifiers (Default Gateway MAC and Wi-Fi BSSID), preventing spoofing via arbitrary IP reassignment or DHCP anomalies.
2. **Mutually Exclusive Active Swarms**: A roaming node belongs to at most one active swarm at any moment (`home`, `office`, `campus`). On unrecognized or public networks, nodes seamlessly transition to **Graceful Standalone Mode**.
3. **Defense-in-Depth Dynamic PAM Gating**: Sudo permissions and KVM cursor crossovers are dynamically verified in real time at execution time rather than permanently granted in `/etc/sudoers`.
4. **Cryptographic Pinned Enrollment**: Node onboarding uses ephemeral cryptographic OTPs coupled with SHA-256 TLS certificate fingerprint pinning, completely eliminating MITM vulnerabilities without external CA infrastructure.
5. **Zero Error Swallowing**: In accordance with system reliability standards, all scripts strictly forbid `2>/dev/null`, `|| true`, and `|| :`. Every exit code is checked, errors are logged, and fallbacks are explicit.

---

## 2. Mesh Hierarchy & Topology

```
                                  ┌─────────────────────────────────────────┐
                                  │          Anchor Workstation             │
                                  │  - Knot Hub (TLS / SSE API :4242)       │
                                  │  - Persistent 10-Year CA (/etc/knot/tls)│
                                  │  - Deskflow KVM Server (:24800)         │
                                  │  - Dynamic Spatial Compiler             │
                                  └───────────────────▲─────────────────────┘
                                                      │
                       Pinned TLS Handshake &         │  KWin Wayland InputCapture
                       Rendezvous Pairing Token       │  + Fractional Bounds (0,100)
                                                      │
              ┌───────────────────────────────────────┴───────────────────────────────────────┐
              │                                                                               │
┌─────────────▼───────────────────────────┐                     ┌─────────────────────────────▼───────────┐
│              Strand Node                │                     │            Headless Compute Node        │
│  - Dynamic KVM Client Runner            │                     │  - Headless Worker Daemon               │
│  - kscreen-doctor Auto-Discovery        │                     │  - Scoped SSH Routing Alias             │
│  - NetworkManager Roaming Guard         │                     │  - Mathematical CIDR Sudo Gate          │
│  - Graceful Standalone Lockdown         │                     │  - Omitted from KVM Screens             │
└─────────────────────────────────────────┘                     └─────────────────────────────────────────┘
```

### Node Roles

- **Anchor Workstation**: High-performance primary system (e.g. multi-monitor desktop). Runs `knot-hub.service`, manages swarm state, coordinates pairing rendezvous, and runs the Deskflow KVM server.
- **Strand (Client)**: Portable or auxiliary interactive machine (laptop, Steam Deck / handheld PC). Runs dynamic client runner `knot-deskflow-client` and `knot-guard.service`.
- **Headless Compute Node**: Server or headless workstation without physical monitors. Participates in SSH routing, task distribution, and sudo access without being included in the KVM screen layout.

---

## 3. Cryptographic TLS CA & Pinned Enrollment Protocol

### Persistent Anchor TLS CA
The Anchor generates a 10-year persistent self-signed X.509 certificate (`/etc/knot/tls/hub.crt`) and 2048-bit RSA private key (`hub.key`) with Subject Alternative Names (SAN) for:
- All non-loopback IPv4 addresses detected on active interfaces
- Local DNS hostnames (`localhost`, `hostname`, `hostname.local`)

### Pinned Composite Pairing Token
When the Anchor issues an invitation (`knot-installer invite`):
1. Knot Hub generates a cryptographically secure 6-digit numeric OTP (e.g. `749201`).
2. Computes the SHA-256 digest of `hub.crt` (64 hex characters) and extracts the 16-character prefix (`fp_short`).
3. Forms the composite token:
   $$\text{Token} = \langle\text{PIN}\rangle.\langle\text{fp\_short}\rangle \quad \text{e.g.}\quad \texttt{749201.352d971d8d92a398}$$

### Handshake & Rendezvous Phase
1. **Initial TLS Preflight**: The Strand fetches the Anchor's DER certificate over raw TLS. It independently computes the SHA-256 digest and verifies that the first 16 characters match `fp_short`. Any MITM proxy or spoofed certificate causes an immediate connection abort.
2. **Rendezvous Wait**: Strand submits its hardware manifest (hostname, SSH public key, and display geometry extracted via `kscreen-doctor -o`) to `/swarm/enroll/join`.
3. **Interactive Anchor Placement**: The Anchor CLI terminal prompts the operator for physical placement (`Left`, `Right`, `Above`, `Below`, `Headless`).
4. **Approval & Swarm Activation**: Anchor issues `/swarm/enroll/approve`. The Strand receives swarm configuration and Anchor public keys, writes `/etc/knot/swarms.d/<swarm>.conf`, and restarts client daemons.

---

## 4. Multi-Swarm Roaming Network Guard (`knot-guard`)

### Hardware Network Fencing
Roaming devices dynamically identify networks using the MAC address of the default gateway and Wi-Fi BSSID:
- Default gateway MAC is verified through the Linux kernel neighbor table (`ip neigh show`).
- If an ARP entry is not yet populated, a single non-blocking ping probe is dispatched to prompt resolution.

### Ethernet-over-Wi-Fi Priority Arbitration
When both wired Ethernet and Wi-Fi interfaces are active simultaneously, Ethernet is prioritized over Wi-Fi default routes to prevent split-brain routing.

### 4-Second Debounce Protection
Roaming triggers on NetworkManager dispatcher events (`up`, `down`, `dhcp4-change`). A persistent debounce daemon (`/run/knot/guard_debounce.pid`) enforces a 4-second stabilization window, absorbing rapid DHCP oscillations before profile switching.

### Graceful Standalone Mode
When connected to untrusted networks (public Wi-Fi, coffee shops, airports):
- `ACTIVE_SWARM` is set to `none`.
- `knot-deskflow-client` shuts down cleanly.
- Dynamic PAM sudo gate strictly refuses passwordless authentication.
- OpenSSH daemon remains active with strict public-key-only authentication, preserving remote management access.

---

## 5. Wayland-Native Spatial KVM & Dynamic Compiler

### Compiler Architecture (`core/modules/compile_deskflow.py`)
Deskflow server configuration (`deskflow-server.conf`) is compiled dynamically from `topology.json` and node manifests:
- **Direction Normalization**: Translates directional representations (`above` $\to$ `up`, `below` $\to$ `down`).
- **Fractional Boundary Mapping**: Supports precise cursor crossover windows (e.g. `(65,100)` or `(45,85)`), allowing cursor transit between displays of different physical dimensions or DPI scalings.
- **Reciprocal Link Generation**: Automatically generates reciprocal return links for counterpart screens when only unidirectionally specified in topology.
- **Headless Node Isolation**: Nodes with `role == "headless"` or missing display outputs are automatically excluded from the screen graph.
- **Host Cursor Confinement (Locked Mode)**: When KVM lock is engaged (`ScrollLock` or Global Shortcut), outbound links from the Anchor are omitted, strictly locking mouse cursor to the physical workstation.

### InputCapture Persistence Shim
KDE Plasma 6 Wayland relies on the `org.freedesktop.portal.RemoteDesktop` and `InputCapture` interfaces. A custom C preload shim (`libinputcapture-persist.so`) ensures that Wayland pointer barrier grabs survive dynamic portal re-initialization and DPMS display power-cycles.

---

## 6. Dynamic PAM Sudo Gate (`knot-auth-check`)

Passwordless sudo execution is guarded dynamically via PAM execution check:
1. Verifies that the host is operating within an authorized active swarm profile (`ALLOW_NOPASSWD_SUDO="true"`).
2. For remote SSH sessions, extracts the client IP address from both `SSH_CLIENT` and `SSH_CONNECTION`.
3. Verifies that the client IP mathematically belongs to the authorized swarm CIDR subnet using Python's `ipaddress.ip_network` engine:
   $$\text{IP} \in \text{Subnet}_{\text{CIDR}}$$
4. Rejects all out-of-subnet requests or unrecognized networks, requiring standard user password prompt.

---

## 7. Web Cockpit & Reactive EventBus

- **Single-Page Application**: Built with React 19, TypeScript, and Tailwind CSS.
- **SSE Event Streaming**: Consumes continuous server-sent events from Knot Hub (`/events`) for node status, task DAG orchestrations, GPU telemetry, and artifact leases.
- **Zero-Dependency Production Assets**: Static assets are pre-compiled to `web/dist` and served natively by Knot Hub's HTTP server without requiring Node.js on production nodes.

---

## 8. Out-of-Band Multi-Agent Swarm Council Architecture

```
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                      KNOT COUNCIL START --INTERACTIVE (--db mesh)                     │
│                        Total Startup Tokens: EXACTLY 0 TOKENS                         │
└──────────────────────────────────────────────────┬────────────────────────────────────┘
                                                   │
                                                   ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                Kitty Confluence Cockpit (Scale-Aware GPU Multiplexing)                │
├───────────────────────────────┬───────────────────────────────┬───────────────────────┤
│ 🟣 desktop (Anchor)           │ 🟢 laptop (Roaming/CUDA)      │ 🔴 rog-ally (Handheld)│
│ - Injected ENV:               │ - Injected ENV:               │ - Injected ENV:       │
│   KNOT_NODE_ID=desktop        │   KNOT_NODE_ID=laptop         │   KNOT_NODE_ID=...    │
│   KNOT_COUNCIL_RUN_ID=run_... │   KNOT_COUNCIL_RUN_ID=run_... │   ...                 │
│                               │                               │                       │
│ - agy Interactive TUI         │ - agy Interactive TUI         │ - agy Interactive TUI │
│   (Zero-token standby)        │   (Zero-token standby)        │   (Zero-token standby)│
│   > [Type to steer agent...]  │   > [Type to steer agent...]  │   > [Type to steer...]│
└───────────────────────────────┴───────────────────────────────┴───────────────────────┘
                                                   │
                   Operator types steering prompt into e.g. @[desktop]:
                          "Audit core runtime and verify tests"
                                                   │
                                                   ▼
┌───────────────────────────────────────────────────────────────────────────────────────┐
│                  Antigravity Hook Activation (PreInvocation Hook)                     │
│  - council_hook.py reads KNOT_COUNCIL_RUN_ID from environment                         │
│  - Evaluates invocationNum == 1 (Turn 1 only)                                         │
│  - Outputs injectSteps with ephemeralMessage:                                         │
│      • Node Identity (@[desktop] - Anchor / Coordinator)                              │
│      • Active Mesh Peers (laptop, rog-ally, steamdeck)                                │
│      • Council Registry (knot://mesh/council/run_...)                                 │
│      • Autonomous coordination protocol (knot council reply / knot council status)    │
│  - Model executes turn WITH full mesh awareness!                                      │
└──────────────────────────────────────────────────┬────────────────────────────────────┘
                                                   │
                                Autonomous Mesh Coordination
                         (knot council reply & knot council status)
                                                   │
                                                   ▼
                      ┌──────────────────────────────────────────────────┐
                      │    Knot Mesh DB / Knot Hub REST API (:4242)      │
                      │    (or GitHub Discussions if --db ghd)           │
                      └──────────────────────────────────────────────────┘
```

### Out-of-Band Resilience Model
Swarm Council operates independently of Knot's Blackboard Hub and Linda Tuplespace daemons. During deep system audits, kernel updates, network reassignments, or service restarts, agents continue collaborating out-of-band via GitHub Discussions GraphQL or the dedicated Mesh DB subsystem.

### Dual Registry Architecture
- **GitHub Discussions (`--db ghd`)**: Public or team-visible coordination thread with machine-parseable HTML comments (`<!-- KNOT-NODE: <id> | STATUS: <status> -->`).
- **Mesh Database (`--db mesh`)**: High-performance local alternative backed by Knot Hub TLS REST endpoints (`/council/threads`, `/council/messages`) with automatic SQLite WAL fallback at `~/.config/knot/council.db`. Emits GitHub Discussions-compatible JSON payloads for 100% interoperability with downstream reconcilers.

### Zero-Token Start & Arena Isolation
- **Zero Startup Token Overhead**: In interactive mode (`knot council start --interactive`), every pane connects directly into the `agy` interactive TUI in standby mode. **Zero prompts are dispatched, zero LLM calls occur, and startup is instantaneous (< 1s)**.
- **Antigravity `PreInvocation` Lifecycle Hook (`council_hook.py`)**:
  - Gated by `KNOT_COUNCIL_RUN_ID` environment variable. When unset (normal coding), the hook exits in `< 2ms` returning `{"injectSteps": []}`, ensuring **zero contamination** outside council missions.
  - Gated by `invocationNum == 1`. Injects the full node persona, peer roster, and coordination CLI commands strictly on Turn 1 of each steered node.
  - On subsequent turns (`invocationNum > 1`), returns `{"injectSteps": []}`, eliminating repetitive prompt token waste.

### Cockpit Tiling Engine & Display Scaling
- **Topological Tiling Layouts**: Confluence mode configures Kitty with scale-aware layouts (`grid`, `sidebyside`, `splits`, `tall`, `fat`, `stacked`).
- **Dynamic Scale Detection**: Queries Wayland / KDE Plasma display scaling (`kscreen-doctor -o`, `QT_SCALE_FACTOR`, `GDK_SCALE`) and dynamically calculates optimal cockpit typography (8.0pt to 12.0pt).
- **Session Resumption**: `knot council resume [run_id]` re-opens the cockpit and re-attaches all panes using `agy -c` with zero prompt overhead.

