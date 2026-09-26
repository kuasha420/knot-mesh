# Knot Mesh — Architectural Specification & Design

> **Production-grade distributed workspace mesh for Arch Linux / KDE Plasma 6 Wayland.**  
> Version: `v1.0.0-rc5`

---

## 1. Core Architectural Tenets

1. **Hardware-Anchored Network Fencing**: Swarm association is determined strictly by physical layer network hardware identifiers (Default Gateway MAC and Wi-Fi BSSID), preventing spoofing via arbitrary IP reassignment or DHCP anomalies.
2. **Mutually Exclusive Active Swarms**: A roaming node belongs to at most one active swarm at any moment (`home`, `office`, `campus`). On unrecognized or public networks, nodes seamlessly transition to **Graceful Standalone Mode**.
3. **Defense-in-Depth Dynamic PAM Gating**: Sudo permissions and KVM cursor crossovers are dynamically verified in real time at execution time rather than permanently granted in `/etc/sudoers`.
4. **Cryptographic Pinned Enrollment**: Node onboarding uses ephemeral cryptographic OTPs coupled with SHA-256 TLS certificate fingerprint pinning, completely eliminating MITM vulnerabilities without external CA infrastructure.
5. **Zero Error Swallowing (PSL Gold Standard)**: In accordance with system reliability standards, all scripts strictly forbid `2>/dev/null`, `&>/dev/null`, `> /dev/null 2>&1`, `|| true`, and `|| :`. Every exit code is checked, errors are logged transparently to stderr, and fallbacks are explicit.

---

## 2. Two-Tier Mesh Hierarchy & Architecture

Knot Mesh is partitioned into two cleanly decoupled architectural planes:

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

### Tier 1: Device-to-Device (D2D) Physical Workspace Fabric
The foundational infrastructure layer managing physical machines, hardware network boundaries, displays, and KVM virtualization:
- **Hardware Network Fencing (`knot-guard`)**: Gateway MAC and BSSID discovery pinning active swarm profiles to physical locations.
- **Wayland-Native Spatial KVM (`knot-deskflow`)**: Sub-pixel cursor crossovers, dynamic spatial topology compilation, and InputCapture persistence across Wayland compositors.
- **C InputCapture Shim (`libinputcapture-persist.so`)**: Persistent portal session re-binding preventing barrier grab loss across DPMS cycles.
- **Dynamic PAM Gating (`knot-auth-check`)**: Mathematical CIDR subnet validation for ephemeral passwordless sudo execution.
- **Display Management & Auto-Unlock (`knot-autounlock`)**: Unlocking and waking Wayland/KDE display sessions on cursor entry.
- **Dynamic Crossover Strip Daemon (`knot-stripd`)**: High-visibility border strips along active crossover boundaries with GPU-accelerated physics impulse flare animations.
- **Full-Mesh Clipboard & Payload Transport (`knot kdeconnect`)**: Asynchronous, zero-latency payload synchronization over KDE Connect, strictly decoupled from Tier 2 cognitive agents and supervised continuously by Tier 1 systemd user timers (`knot-kdeconnect-reconcile.timer`) and NetworkManager roaming guards (`knot-guard`).
- **Wayland Virtual Monitor Fabric (`knot kdeconnect vmon`, `knot display extend`)**: Dynamic headless display creation via KWin Wayland + `krdpserver` (`krdp`) and hardware-accelerated RDP streaming to remote strands via KRDC (`krdc` + `freerdp`). Enables docked handhelds (Steam Deck OLED, ROG Ally) and laptops to toggle instantly between independent KVM workstations and auxiliary high-density desktop displays.
- **3-Tier Mesh Network Resolver (`core/resolver.sh`)**: Dynamic resolution hierarchy traversing WireGuard $\to$ mDNS $\to$ LAN physical fallback.

### Tier 2: Agent-to-Agent (A2A) Cognitive Swarm Layer
The autonomous multi-agent intelligence layer orchestrating distributed AI agent instances across the mesh:
- **Swarm Council Plane (`knot council`)**: Out-of-band collaborative deliberation across autonomous CLI agents with zero startup token overhead and topological Kitty confluence multiplexing.
- **Linda Tuplespace & Blackboard Hub (`knot-hub`, `knot-agent`)**: Distributed state synchronization, atomic task leasing, and coordination.
- **Decentralized Memory Palace (`core/memory/`)**: In-process SQLite WAL storage with vector cosine similarity and CRDT Hybrid Logical Clocks.
- **Lean Stateless MCP Gateway (`core/mcp/gateway.py`)**: Zero-dependency stdio Model Context Protocol server exposing the 4 canonical mesh tools.
- **Antigravity CLI Orchestrator (`core/modules/antigravity.sh`)**: Headless agy CLI discovery, session execution slices, and quota tracking.

### 2.1 Strict Domain Separation Contract (Tier 1 vs Tier 2)

To maintain system stability, security, and predictability, Tier 1 and Tier 2 adhere to a strict architectural firewall:

| Dimensional Aspect | Tier 1 (D2D Physical Workspace Fabric) | Tier 2 (A2A Cognitive Swarm Layer) |
| :--- | :--- | :--- |
| **Primary Domain** | Display compositors, Wayland input, hardware networking, PAM sudo, system power. | Autonomous multi-agent coordination, memory recall, LLM task fanout. |
| **Authority Level** | System root / user desktop session privileges (`systemd`, `loginctl`, `pam`). | Application-level non-root processes (`agy`, `python3`, `knot council`). |
| **State Persistence** | `/etc/knot/`, `/run/knot/` runtime locks, NetworkManager dispatchers. | `~/.config/knot/council.db`, `~/.config/knot/memory/`, Blackboard Hub memory. |
| **Failure Domain** | Physical network disruption, DPMS sleep, Wayland portal restarts. | LLM quota exhaustion, agent task crashes, reasoning loops. |
| **Isolation Contract** | Completely oblivious to agent deliberation and cognitive states. | Accesses Tier 1 strictly via typed CLI commands (`bin/knot`) or TLS REST API (`:4242`). |

**Failure Containment Guarantees**:
1. **Cognitive Fault Isolation**: An A2A failure (e.g. LLM rate limiting, agent crash, out-of-quota exception) **never** degrades physical workspace functions (cursor routing, display auto-unlock, or network fencing continue uninterrupted).
2. **Physical Lockdown Isolation**: When Tier 1 transitions to Standalone Lockdown on public Wi-Fi, Tier 2 agents are immediately constrained to local memory pools and prevented from making unauthorized cross-node RPC calls without corrupting tuplespace state.
3. **Zero Privilege Escalation**: Tier 2 agents cannot directly mutate PAM configurations, bypass CIDR gates, or disable network guards.

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

### C InputCapture Persistence Shim (`core/shim/input_capture_shim.c`)
KDE Plasma 6 Wayland enforces strict security around cursor capture using `org.freedesktop.portal.RemoteDesktop` and `org.freedesktop.portal.InputCapture`. In stock implementations, Wayland pointer barriers are dropped when monitors enter DPMS standby or when portal interfaces cycle.

The Knot C preload shim (`libinputcapture-persist.so`) solves this at the library level:
1. **Dynamic Interception**: Intercepts `xdp_portal_create_input_capture_session` and `xdp_portal_create_input_capture_session_finish` via `dlopen`/`dlsym`.
2. **Persistent Session Restore Token**: Automatically extracts the session restore token and persists it to `~/.local/share/Deskflow/input_capture_restore_token`.
3. **Barrier Persistence**: Intercepts barrier registration calls (`xdp_input_capture_session_set_pointer_barriers`), recording active screen geometry and edge bounds.
4. **Transparent Reconnection**: On DPMS wake or portal reinitialization, the shim passes the saved restore token, immediately re-arming input capture barriers without user interaction or dialog prompts.

---

## 6. Wayland Virtual Monitor Fabric & Zero-Touch Trust Protocol (`knot display`, `knot kdeconnect vmon`)

The Wayland Virtual Monitor Fabric expands an Anchor workstation's physical workspace onto docked handhelds (Steam Deck OLED, ROG Ally) or laptops without physical video cables or hardware capture dongles. It pairs KDE Plasma 6 KWin headless display virtualization with RDP hardware streaming and zero-touch cryptographic trust bootstrapping.

```
┌────────────────────────────────────────────────────────┐
│                   Anchor Workstation                   │
│                                                        │
│  1. kdeconnect_vmon_ensure_host_certs                  │
│     - Generate 10-year RSA 2048 cert (krdp.crt)        │
│     - Configure krdpserverrc (ListeningPort=5900)      │
│                                                        │
│  2. kdeconnect_vmon_seed_client_trust (over SSH)       │
│     - Push krdp.crt to client ~/.config/freerdp/server │
│     - Symlink ports 5900..5920 to eliminate prompt     │
│     - Set krdcrc ShowPreferences=false, Fullscreen=true│
│                                                        │
│  3. DBus requestVirtualMonitor                         │
│     - KWin spawns headless virtual output              │
│     - krdpserver streams display over RDP (5900/tcp)   │
└──────────────────────────┬─────────────────────────────┘
                           │ Authenticated TLS Stream
                           │ (ports 5900-5910/tcp)
                           ▼
┌────────────────────────────────────────────────────────┐
│                      Client Strand                     │
│                                                        │
│  - Receives rdp:// URI via KDE Connect DBus packet     │
│  - Launches KRDC fullscreen without security warnings  │
│  - Renders low-latency Wayland virtual desktop         │
│  - On stop: Host terminates DBus & issues pkill over   │
│    SSH to cleanly close remote KRDC viewer window      │
└────────────────────────────────────────────────────────┘
```

### Headless Display Virtualization (`krdp` / `krdpserver`)
Under KDE Plasma 6 Wayland, virtual monitors cannot be created via X11 dummy drivers or virtual monitor packages. Instead, Knot orchestrates KWin's native virtual monitor portal and `krdpserver`:
- **Dynamic Virtual Output**: Spawns a headless virtual screen in KWin dynamically sized and scaled to the remote strand's physical panel (e.g. 1920x1080@100% or 1280x800@100%).
- **Hardware-Accelerated Frame Capture**: KWin pipes rendered frames directly into `krdpserver` via Wayland DMA-BUF / PipeWire buffers.
- **Automatic Output Destruction**: When the `krdpserver` process terminates, KWin automatically destroys the virtual output and cleanly refits the Anchor's multi-head layout without leaving ghost screens.

### Zero-Touch Cryptographic Trust Protocol
Stock implementations of KDE Connect Virtual Monitor require tedious manual interaction: certificate acceptance dialogs, connection preference popups, and recurring trust warnings. Knot resolves this through an out-of-band automated trust pipeline:
1. **Host TLS Certificate Generation**: `krdpserver` requires an explicit TLS certificate to start. `kdeconnect_vmon_ensure_host_certs` checks `~/.local/share/krdpserver/krdp.crt`. If missing, it generates a 10-year self-signed RSA 2048 certificate and writes `ListeningPort=5900`, `Certificate`, and `CertificateKey` into `~/.config/krdpserverrc` via `kwriteconfig6`.
2. **FreeRDP Dynamic Port Range Pre-Trusting**: KDE Connect's `virtualmonitorplugin.cpp` increments its listening port on every session (`static uint s_port = DEFAULT_PORT; s_port++`). Because FreeRDP 3 indexes trusted server certificates strictly by `<host>_<port>.pem` in `~/.config/freerdp/server/`, standard "Remember this certificate" prompts fail as soon as the port increments on subsequent connections. Knot's `kdeconnect_vmon_seed_client_trust` pushes the host certificate to the client and automatically creates symlinks across the entire dynamic port range `5900..5920` (`<host>_<port>.pem -> <host>.pem`).
3. **Zero-Prompt Fullscreen KRDC Preferences**: Client configuration `~/.config/krdcrc` is pre-configured with `ShowPreferencesForNewConnections=false` and `FullscreenOnConnect=true`, suppressing modal dialogs and presenting the virtual desktop full-screen instantly.
4. **Ephemeral Credential Exchange**: Single-use UUID passwords and dynamic connection endpoints are negotiated privately over KDE Connect's TLS encrypted DBus channel. Zero shared secrets or persistent passwords are ever stored on disk.

### Viewer Lifecycle & Remote Process Cleanup
When stopping a virtual monitor (`knot display stop <node_id>` or `knot kdeconnect vmon stop <node_id>`):
1. Knot dispatches `org.kde.kdeconnect.device.virtualmonitor.stop` via DBus on the host, signaling KWin and `krdpserver` to terminate the stream and tear down the virtual display output.
2. Knot simultaneously resolves the remote strand over authenticated SSH and issues a targeted process termination (`pkill -f 'krdc.*rdp://.*<my_ip>'`), instantly closing the KRDC viewer window on the remote screen without leaving orphaned windows or dangling sessions.

### Dual-Mode Coexistence
The Virtual Monitor Fabric seamlessly coexists with Deskflow KVM:
- **Mode A (Independent KVM Strand)**: The strand runs its own local desktop session and apps; mouse and keyboard traverse physical screen boundaries via Deskflow KVM.
- **Mode B (Auxiliary Desktop HUD)**: The strand renders the Anchor's virtual display output full-screen via KRDC. The user moves windows and mouse fluidly into the handheld or laptop as an extra monitor of the primary desktop workstation.

---

## 7. 3-Tier Dynamic Network Resolution Hierarchy (`core/resolver.sh`)

Mesh nodes must communicate reliably despite DHCP lease shifts, roaming between Wi-Fi and Ethernet, and mixed subnet topologies. `core/resolver.sh` implements an algorithmic 3-tier resolution sequence:

```
[Target: node_id] ──► [Tier 0: Lease Cache & Localhost] ──(Valid & Alive?)──► RESOLVED
                                  │ No
                                  ▼
                      [Tier 1: mDNS / Zeroconf] ───────(Valid & Alive?)──► RESOLVED
                                  │ No
                                  ▼
                      [Tier 2: Declarative IP Hint] ───(Valid & Alive?)──► RESOLVED
                                  │ No
                                  ▼
                      [Tier 3: Hardware MAC ARP Scan] ─(Valid & Alive?)──► RESOLVED
                                  │ No
                                  ▼
                      [WireGuard Mesh Overlay] ────────(Valid & Alive?)──► RESOLVED
                                  │ No
                                  ▼
                             FAILED (Exit 1)
```

### Resolution Tiers
1. **Tier 0: Lease Cache & Loopback**: Checks `~/.cache/knot/leases/${SWARM}_${NODE}`. If the cached IP responds to health checks, it returns instantly (< 5ms). If resolving the local node identity, returns `127.0.0.1`.
2. **Tier 1: mDNS / Zeroconf**: Probes `<hostname>.local` via `getent ahostsv4` or `avahi-resolve -n`. Ideal for zero-configuration L2 local networks.
3. **Tier 2: Declarative IP Hint**: Inspects the node manifest (`~/.config/knot/swarms/<swarm>/nodes/<node>.json`) for statically declared `ip_hint`.
4. **Tier 3: Hardware MAC ARP Scan**: Extracts hardware MAC addresses from the node manifest, scans the kernel ARP neighbor table (`ip neigh`), and falls back to a parallel non-blocking subnet ICMP ping sweep (`nmap -sn` or parallel background ping probes).
5. **WireGuard Mesh Overlay**: Traverses point-to-point encrypted tunnels (`wg0`, `10.42.0.0/24`), enabling seamless cross-subnet and roaming reachability.

### Health and Port Probing
Before returning an IP address, `resolver.sh` validates that the host is alive using `is_host_alive`:
- Target port probe (`nc -z`, `socat`, or `/dev/tcp` socket probe).
- Mesh service probes (Deskflow port `24800`, Knot Hub port `4242`).
- ICMP echo fallback.
- In `--proxy` mode (used by `knot exec` and SSH ProxyCommand), the target SSH port (`22`) is strictly enforced.

---

## 8. Ephemeral Advisory Autologin & DPMS Autounlock Flows

Knot Mesh eliminates physical workstation friction through coordinated display power and session management while maintaining non-destructive safety guarantees:

### Advisory vs Destructive Philosophy
Legacy autologin approaches forcefully terminate display managers or kill active sessions, causing lost work and broken applications. Knot Mesh employs an **advisory, non-destructive architecture**:
- Active graphical sessions are **never killed or forcefully restarted**.
- Autologin applies strictly when a machine has booted to a login manager greeter with zero active user sessions.
- Authentication state is verified against Anchor lock status and KDE Connect pairing before advisory login triggers.

### DPMS Auto-Unlock Flow (`core/modules/autounlock.sh`)
When cursor movement crosses into a Strand monitor or when `knot screen unlock` is executed:
1. **Session Identification**: Queries `loginctl list-sessions` to locate the active `seat0` Wayland/X11 session.
2. **Unlock Signal**: Issues `loginctl unlock-session <session_id>` to dismiss the KDE screenlocker.
3. **Display Wake (DPMS)**: Dispatches `org.freedesktop.ScreenSaver.SimulateUserActivity` via DBus (`qdbus6` or `qdbus`), waking displays from DPMS power-saving standby and resetting desktop idle timers.

### Ephemeral Strand Autologin Flow (`core/modules/autologin.sh`)
When a docked Strand boots up:
1. **Anchor Lock Probe**: Strand queries the Anchor workstation over authenticated SSH (`knot screen status-raw`).
2. **Precondition Validation**: Autologin activates **only** if the Anchor is online and its desktop session is currently `UNLOCKED`.
3. **Session Resumption**: Initiates user session startup via `plasma-login-manager` or configured display manager.
4. **Keyring & Wallet Integration**: Guides PAM unlock for KWallet without hardcoding plaintext passwords into scripts.

---

## 9. Dynamic PAM Sudo Gate (`knot-auth-check`)

Passwordless sudo execution is guarded dynamically via PAM execution check:
1. Verifies that the host is operating within an authorized active swarm profile (`ALLOW_NOPASSWD_SUDO="true"`).
2. For remote SSH sessions, extracts the client IP address from both `SSH_CLIENT` and `SSH_CONNECTION`.
3. Verifies that the client IP mathematically belongs to the authorized swarm CIDR subnet using Python's `ipaddress.ip_network` engine:
   $$\text{IP} \in \text{Subnet}_{\text{CIDR}}$$
4. Rejects all out-of-subnet requests or unrecognized networks, requiring standard user password prompt.

---

## 10. Web Cockpit & Reactive EventBus

- **Single-Page Application**: Built with React 19, TypeScript, and Tailwind CSS.
- **SSE Event Streaming**: Consumes continuous server-sent events from Knot Hub (`/events`) for node status, task DAG orchestrations, GPU telemetry, and artifact leases.
- **Zero-Dependency Production Assets**: Static assets are pre-compiled to `web/dist` and served natively by Knot Hub's HTTP server without requiring Node.js on production nodes.

---

## 11. Out-of-Band Multi-Agent Swarm Council Architecture

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

---

## 12. Linda Tuplespace Blackboard Lifecycle & Decentralized CRDT Memory Palace

### Linda Tuplespace Blackboard Hub (`core/hub/hub.py`, `core/hub/agent.py`)
Coordination across headless nodes is mediated by an in-memory Linda tuplespace blackboard hosted by Knot Hub:
- **Tuple Primitives**:
  - `out(tuple)`: Posts a task, state fact, or artifact metadata to the space.
  - `in(pattern, lease_timeout)`: Atomically claims a task matching pattern, locking it with a heartbeated lease.
  - `rd(pattern)`: Non-destructive pattern matching inspection of active tuples.
  - `eval(task)`: Asynchronously schedules background execution on a selected worker node.
- **Lease Heartbeats & Orphan Recovery**: When an agent claims a task, it acquires a renewable lease (default: 60s). The agent emits periodic heartbeats via `knot-agent`. If a node crashes, loses power, or disconnects, the lease expires and Knot Hub automatically transitions the task back to `PENDING`, allowing another peer to resume work without deadlocks.

### Decentralized CRDT Memory Palace (`core/memory/palace.py`)
Agent memory and workspace context are stored across nodes without reliance on centralized cloud vector databases:
- **Dual-Pool Architecture**:
  - `local`: Private scratch memory specific to the node (temporary compile caches, local hardware metrics).
  - `shared`: Swarm-wide knowledge pool synchronized across all nodes.
- **Hybrid Logical Clocks (HLC)**: Every memory mutation is stamped with an HLC combining physical epoch time with a monotonically increasing logical counter, resolving conflicts deterministically across disconnected nodes.
- **In-Process Vector Search**: Generates embedding vectors directly in Python standard library (`struct`, `math`), executing fast cosine similarity searches without needing external heavyweight vector daemon processes.
- **Hierarchical Taxonomy**: Knowledge is indexed into a spatial memory model:
  $$\text{Wing} \longrightarrow \text{Hall} \longrightarrow \text{Drawer} \longrightarrow \text{Memory Title}$$

---

## 13. Runtime Skills Architecture (`runtime/skills/`)

Autonomous agent capabilities are fully decoupled from core bash orchestrators and relocated to the standardized `runtime/skills/` directory adhering to the open Agent Skills specification:

- **Directory Structure**:
  - `runtime/skills/knot-swarm/`: Fleet-wide agent discovery, quota tracking, and task dispatch.
  - `runtime/skills/hardware-profiles/`: Node-specific architecture, accelerator capabilities (CUDA, ROCm, UMA), and role definitions.
  - `runtime/skills/swarm-council/`: Confluence cockpit coordination, multi-agent steering, and discussion thread reconciliations.
  - `runtime/skills/goal-with-lease/`: Autonomous goal execution with Linda tuplespace artifact locking and distributed heartbeats.
  - `runtime/skills/subagent-ladder/`: User-invoked multi-agent SWE execution pipeline (Executioner $\to$ Hammer $\to$ Auditor) with deterministic workspace artifact bridge.
- **Skill Specification Format**:
  - Each skill directory is anchored by `SKILL.md`, documenting instructions, input schemas, environmental prerequisites, and operational contracts.
  - Skills interact with the underlying mesh strictly via clean CLI entrypoints (`knot`, `knot council`) or REST APIs, preserving strict tier decoupling between A2A cognitive processes and D2D system plumbing.

---

## 14. PSL Gold Standard Error Transparency Contracts & CI Verification

System reliability and observability across Knot Mesh are governed by the Product Systems Language (PSL) Gold Standard:

### Zero Error Swallowing Mandate
- **Strict Ban on Error Suppression**: The patterns `2>/dev/null`, `&>/dev/null`, `> /dev/null 2>&1`, `|| true`, and `|| :` are permanently banned across all production scripts (`bin/*`), runtime modules (`core/modules/*.sh`), libraries (`core/lib.sh`), and test suites (`tests/*.sh`).
- **Python Exception Hygiene**: Bare `except:` and swallowed `except ...: pass` blocks are strictly forbidden. All exceptions must be explicitly captured and logged or re-raised.
- **Shell Hygiene Contract**: Every bash script strictly executes under `set -euo pipefail`.
- **POSIX-Standard Command Probing**: Command and utility detection uses standard `command -v <cmd> >/dev/null` without stderr redirection.
- **Systemd Service Inspection**: Service states are probed using native systemd quiet flags (`systemctl --user is-active --quiet <unit>`, `systemctl is-enabled --quiet <unit>`).
- **DBus & Subprocess Diagnostics**: Status codes and stderr outputs from DBus calls (`busctl`, `qdbus`) and subprocesses are explicitly inspected, with non-zero exits logged transparently to stderr via `knot_log_warn` or `knot_log_err`.

### Universal Integrity Suite (`tests/test_psl_integrity.sh`)
Automated CI validation executes across 5 exhaustive audits:
1. **Audit 1: Forbidden Pattern Scan**: Recursively inspects all `.sh`, `.py`, and binary scripts for error-swallowing regex patterns.
2. **Audit 2: Shell Hygiene**: Verifies that every shell script declares `set -euo pipefail`.
3. **Audit 3: Shell Syntax Validation**: Executes `bash -n` across 100% of shell scripts to detect syntax anomalies.
4. **Audit 4: Python Syntax & Exception Hygiene**: Compiles AST trees for all Python modules, ensuring zero bare `except:` or swallowed exception patterns.
5. **Audit 5: Executable Permissions**: Enforces `+x` executable bits across all `bin/*` binaries and `tests/*.sh` test runners.
