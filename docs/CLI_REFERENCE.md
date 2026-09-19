# Knot Mesh CLI Reference Manual 🪢⚡

This document provides a comprehensive command-line reference for both `knot` (daily mesh orchestrator) and `knot-installer` (bootstrap, onboarding, and lifecycle utility).

---

## Table of Contents

- [Global Environment Variables](#global-environment-variables)
- [1. `knot` — Mesh Orchestrator](#1-knot--mesh-orchestrator)
  - [knot status](#knot-status)
  - [knot doctor](#knot-doctor)
  - [knot repair](#knot-repair)
  - [knot sync](#knot-sync)
  - [knot update](#knot-update)
  - [knot screen](#knot-screen)
  - [knot autologin](#knot-autologin)
  - [knot kvm](#knot-kvm)
  - [knot kdeconnect](#knot-kdeconnect)
  - [knot swarm](#knot-swarm)
  - [knot exec](#knot-exec)
  - [knot resolve](#knot-resolve)
  - [knot shutdown](#knot-shutdown)
  - [knot council](#knot-council)
- [2. `knot-installer` — Onboarding & Lifecycle CLI](#2-knot-installer--onboarding--lifecycle-cli)
  - [knot-installer init](#knot-installer-init)
  - [knot-installer invite](#knot-installer-invite)
  - [knot-installer join](#knot-installer-join)
  - [knot-installer doctor](#knot-installer-doctor)
  - [knot-installer update](#knot-installer-update)
  - [knot-installer uninstall](#knot-installer-uninstall)

---

## Global Environment Variables

| Variable | Description | Default |
| :--- | :--- | :--- |
| `KNOT_ACTIVE_SWARM` | Explicitly overrides the active swarm profile for the shell session. | Read from `/run/knot/active_swarm` or `~/.local/state/knot/active_swarm` |
| `KNOT_RUNTIME_DIR` | Directory containing runtime fences, sockets, and transient PID files. | `/run/knot` |
| `KNOT_VERSION` | Knot release version override. | `1.0.0-rc4` |
| `KNOT_TEST_MODE` | If set (`1`), bypasses graphical prompts and system modifications. | Empty |

---

## 1. `knot` — Mesh Orchestrator

The primary binary used across all swarm nodes to monitor health, synchronize manifests, orchestrate sessions, and control KVM boundaries.

```bash
knot [command] [options] [arguments...]
```

### `knot status`
Displays real-time mesh telemetry, active swarm profile, local node identity, and reachability across all registered peers.

```bash
knot status
# or simply:
knot
```

- **Output Includes**:
  - Active Swarm ID and Swarm Name
  - Local node role (`Anchor` or `Strand`), IP hint, hostname, and SSH port
  - Peer list with latency, online/offline status, display resolution, and active services
  - Deskflow server/client status and active connections

---

### `knot doctor`
Comprehensive multi-tier health diagnosis covering systemd units, network interfaces, SSH keys, Wayland portals, and KVM configurations.

```bash
knot doctor local                  # Diagnose local workstation only
knot doctor <node_id>              # Remotely diagnose a specific node
knot doctor --all                  # Fleet-wide diagnosis across all active nodes
knot doctor --fix                  # Run diagnosis and automatically invoke repairs
```

- **Diagnostic Checks**:
  1. `KNOT_ACTIVE_SWARM`: Verifies active profile validity in `/etc/knot/swarms.d` or `~/.config/knot/swarms`.
  2. `Network & Ports`: Validates binding for Hub (4242), KVM (24800), and SSH.
  3. `Display Manager`: Validates `plasma-login-manager` configuration for headless Wayland autounlock.
  4. `Systemd Services`: Checks status of `knot-hub`, `knot-deskflow`, `knot-agent`, and `knot-guard`.
  5. `SSH Key Mesh`: Verifies bidirectional authorized keys exchange between all swarm members.

---

### `knot repair`
Executes automated remediation scripts to fix common misconfigurations, reload systemd daemons, repair display manager links, and restart stuck services.

```bash
knot repair local                  # Repair local node components
knot repair <node_id>              # Remotely repair a specific strand
knot repair --all                  # Fleet-wide repair across all swarm nodes
```

---

### `knot sync`
Synchronizes declarative swarm manifests, screen topologies, and profile configurations across the mesh.

```bash
knot sync                          # Standalone sync: pull latest manifests from Anchor
knot sync <node_id>                # Anchor mode: push configuration to a specific Strand
knot sync --all                    # Anchor mode: push configuration to all active Strands
knot sync --dev                    # Dev mode: auto-heal local symlinks, global hooks, and Antigravity drift
knot sync --dev --all              # Dev mode: auto-heal dev environment & sync topology across all Strands
knot sync --dev <node_id>          # Dev mode: auto-heal dev environment on a specific Strand
```

- **Options**:
  - `--dev`: Development synchronization mode. Auto-heals local/remote development drift:
    - Sets `~/.config/knot/install_type` marker to `dev`.
    - Restores binary symlinks (`~/.local/bin/knot`, `knot-installer`) to active Git worktrees.
    - Symlinks global Antigravity skill (`~/.gemini/config/skills/swarm-council`).
    - Configures global Antigravity lifecycle hooks (`~/.gemini/config/hooks.json`).
    - Auto-heals Antigravity settings (`useAiCredits: false`, `useG1Credits: false`, dark theme).
  - `--force-prod`: Override development lockout to execute production sync on a Git development node.
  - `--force-dev`: Override production lockout to execute development sync on a packaged/standalone node.
- **Safety Lockout**:
  - Running production `knot sync` on a dev installation is hard-blocked to protect local checkouts and configurations from being overwritten.
  - In fleet sync (`--all`), Strand install types are checked; production nodes skip dev drift healing and dev nodes skip binary tarball overwrites.

---

### `knot update`
Swarm-wide binary and core module updater. Checks for new releases or synchronizes code changes across the mesh.

```bash
# Production Release Mode
knot update                        # Check and update local node from GitHub release
knot update --all [-f]             # Anchor mode: rollout release update across all active Strands
knot update <node_id> [-f]         # Anchor mode: rollout update to a specific Strand

# Development Mode (Git Mesh)
knot update --dev                  # Dev mode: fast-forward git pull on local repository & restart worker daemons
knot update --dev --all            # Dev mode: fleet-wide git pull, binary audit, service restart & status reconciliation
knot update --dev <node_id>        # Dev mode: update a specific Strand via git pull
```

- **Options**:
  - `--dev`: Development update mode. Orchestrates `git -C <repo> pull --ff-only` across Anchor and Strands, audits executable permissions, heals symlinks, restarts background worker daemons (`knot-agent`, `knot-stripd`, `knot-hub`) without interrupting active KVM (`knot-deskflow`), and runs mesh status reconciliation.
  - `-f, --force`: Force re-synchronization even if the remote tag matches.
  - `--force-prod`: Override development lockout to execute production update on a Git development node.
  - `--force-dev`: Override production lockout to execute development update on a packaged/standalone node.
- **Safety Lockout**:
  - Running production `knot update` on a development installation is hard-blocked to prevent overwriting active Git worktrees with release tarballs.
  - During production fleet rollout (`knot update --all`), any Strand running a development installation is safely skipped with a warning.
- **KVM Resilience**:
  - Updates only restart background agent daemons; `knot-deskflow.service` and `knot-autounlock.service` are never interrupted, guaranteeing zero display flicker or input dropouts.

---

### `knot screen`
Controls Wayland screen lock states across the mesh.

```bash
knot screen status                 # Check lock status (LOCKED / UNLOCKED) on local node
knot screen unlock                 # Unlock screen using PAM credentials or secret token
knot screen lock                   # Lock screen via loginctl
knot screen toggle                 # Toggle lock state
```

---

### `knot autologin`
Manages headless session unlocking and automated session resumption when the Anchor is unlocked.

```bash
knot autologin status              # Check autologin readiness and session status
knot autologin unlock              # Execute coordinated unlock on local or strand nodes
knot autologin lock                # Lock node sessions
knot autologin enable              # Enable autologin service on boot
knot autologin disable             # Disable autologin service
```

---

### `knot kvm`
Controls the Wayland Deskflow KVM server and client daemons.

```bash
knot kvm status                    # Display Deskflow daemon and connection status
knot kvm restart                   # Coordinated KVM restart across the entire swarm
knot kvm lock                      # Confine cursor to the local screen (KVM lock)
knot kvm unlock                    # Release cursor confinement across physical boundaries
knot kvm lock-toggle               # Toggle cursor confinement
```

---

### `knot kdeconnect`
Manages KDE Connect mesh synchronization, custom device discovery, and cross-device clipboard sharing.

```bash
knot kdeconnect status             # Show paired devices and clipboard status
knot kdeconnect sync               # Synchronize swarm IP hints into local customDevices
knot kdeconnect sync --all         # Propagate customDevices and enforce clipboard across fleet
```

- **Features**:
  - Automatically merges swarm node IP addresses into `customDevices` while preserving existing devices (e.g. smartphones).
  - Enables `kdeconnect.clipboard` and `kdeconnect.clipboard.daemon` plugins across all paired workstations.

---

### `knot swarm`
Manages multi-tenant swarm profiles and Antigravity multi-agent cluster authentication.

```bash
knot swarm status                  # List configured swarm profiles and active fence
knot swarm switch <swarm_id>       # Switch active swarm profile (e.g. home, office)
knot swarm test [node_id]          # Test Antigravity CLI telemetry and ping latency
knot swarm auth [node_id]          # Verify Google OAuth token validity for headless agy
```

---

### `knot exec`
Executes arbitrary shell commands across one or all nodes in the swarm via hardened SSH batch sessions.

```bash
knot exec <node_id> <command...>   # Execute command on a specific node
knot exec --all <command...>       # Execute command concurrently across all active nodes
```

- **Example**:
  ```bash
  knot exec --all "uname -r; uptime"
  ```

---

### `knot resolve`
Resolves a node ID to its active reachable IP address and SSH port using the cached leases and mDNS resolver.

```bash
knot resolve <node_id> [port]
```

- **Example**:
  ```bash
  knot resolve laptop
  # Output: 192.168.68.142
  ```

---

### `knot shutdown`
Coordinates scheduled or immediate power management across the mesh.

```bash
knot shutdown status               # Show pending shutdown/reboot timers across the fleet
knot shutdown cancel               # Cancel pending scheduled shutdown timers
knot shutdown [node] poweroff      # Power off a specific node immediately
knot shutdown [node] reboot        # Reboot a specific node immediately
knot shutdown --all poweroff       # Gracefully power off all Strands, then the Anchor
knot shutdown --all reboot         # Reboot all Strands, then the Anchor
```

- **Options**:
  - `--delay <minutes|now>`: Delay before shutdown (e.g. `+10` for 10 minutes, `23:00`, or `now`).
  - `--wall "<message>"`: Custom broadcast message sent to all logged-in users.

---

### `knot council`
Out-of-band multi-agent coordination protocol using GitHub Discussions, Mesh DB, and scale-aware Kitty Confluence multiplexing. Allows autonomous Antigravity agents across physical nodes to coordinate on distributed audits, verification sweeps, or interactive pair steering.

```bash
knot council <start|resume|status|reply|steer|list|attach|reconcile|copy|clean|kill> [options]
```

#### `knot council start`
Launches an autonomous council mission or zero-token interactive multi-node cockpit.

```bash
# Autonomous Mission (with prompt scaffolding)
knot council start [--mode <mode>] [--db <ghd|mesh>] [--tiling <layout>] [--pack <pack>] [--prompt <text>]

# Zero-Token Interactive Cockpit (direct drop into agy TUI with on-demand steering)
knot council start --interactive [--tiling <layout>] [--project <name>] [--nodes <list>]

# Dry-run validation
knot council start --interactive --dry-run
```

- **Options**:
  - `--mode <confluence|headless|tui|gui|suggested>`: Execution surface. Default: `confluence`.
  - `--db <ghd|mesh>`: Coordination message board backend: `ghd` (GitHub Discussions, default for autonomous missions) or `mesh` (Knot Hub REST API `:4242` and SQLite fallback, default for interactive cockpit).
  - `--interactive`: Spawns fullscreen Kitty Confluence cockpit with all swarm nodes connected in `agy` standby. **Consumes 0 tokens at startup**; context is injected on-demand via Antigravity `PreInvocation` lifecycle hook when the operator prompts a node.
  - `--resume [run_id]`: Resumes previous conversations across all cockpit panes using `agy -c`.
  - `--tiling <grid|sidebyside|splits|tall|fat|stacked>`: Scale-aware Kitty window layout. Default: `grid`.
  - `--pack <audit-parity|fast-triage|tournament>`: Prompt scaffold template pack. Default: `audit-parity`.
  - `--prompt <text>`: Base mission prompt text.
  - `--prompt-file <path>`: Path to file containing base mission prompt.
  - `--nodes <list>`: Comma-separated list of target nodes (default: all online fleet nodes).
  - `--project <name>`: Target Antigravity project name (default: auto-detected from CWD).
  - `--dry-run`: Generates prompts and Kitty session configurations without launching runners.

---

#### `knot council resume`
Re-opens the Kitty Confluence cockpit and re-attaches all swarm nodes to their active conversations using `agy -c`.

```bash
knot council resume [run_id]
```

- If `[run_id]` is omitted, automatically finds and resumes the latest active council session.
- Restores active tiling layout, project directory, and exports council environment variables across all panes.

---

#### `knot council status`
Inspects real-time milestone progress, node check-ins, and peer updates for a mission.

```bash
knot council status [run_id]
```

- Displays the fleet status matrix, verified alerts, milestone progress (25%, 50%, 75%), and deliverables.
- If `[run_id]` is omitted, inspects the latest mission.

---

#### `knot council reply`
Posts status checkpoints, alerts, or final reports to the mission registry (GitHub Discussions or Mesh DB).

```bash
knot council reply <run_id> [--node <id>] [--status <25%|50%|75%|ALERT|FINAL|PROGRESS>] [--body "<text>"]

# Or pipe markdown deliverable from stdin:
knot council reply <run_id> --node desktop --status FINAL < deliverable.md
```

- **Options**:
  - `--node <id>`: Node identifier (defaults to `$KNOT_NODE_ID` or local hostname).
  - `--status <status>`: Milestone indicator (`25%`, `50%`, `75%`, `ALERT`, `FINAL`, `PROGRESS`).
  - `--body <text>`: Message text (strictly under 15-20 lines for interim checkpoints).

---

#### `knot council steer`
Injects guidance, prompts, or cognitive challenges directly into a target node's active Kitty Confluence cockpit pane using Kitty's remote control bridge socket (`/tmp/kitty-council-<run_id>.sock`).

```bash
knot council steer <node> "<prompt>" [run_id]

# Or pipe guidance from stdin:
echo "Focus on edge case validation" | knot council steer laptop
```

- **Observability**: Prompts are visibly typed into the target agent's terminal in real time, waking up that node's interactive `agy` session so the human operator can watch reasoning and tool calls live.
- **Inter-Agent Delegation**: Used by the Coordinator and peer agents to pass cryptographic rally volleys or assign audit chunks across co-located panes without bypassing the terminal with headless SSH.

---

#### `knot council list`
Lists recent Swarm Council missions from local storage with execution metadata, backend, and status.

```bash
knot council list [interactive|active|mesh|ghd]
```

- **Filters**:
  - `interactive`: Display only interactive cockpit sessions.
  - `active`: Display only active, running missions.
  - `mesh` / `ghd`: Filter by registry backend.
- Displays `[INTERACTIVE | ACTIVE]` and `[AUTONOMOUS | ACTIVE]` badges with tiling mode and node rosters.

---

#### `knot council attach`
Connects directly to an active agent session on a specific node from the current terminal.

```bash
knot council attach <node_id> [run_id]
```

- Inherits council environment variables (`KNOT_NODE_ID`, `KNOT_COUNCIL_RUN_ID`, `KNOT_PROJECT`) and attaches via `agy -c`.

---

#### `knot council reconcile`
Synthesizes all discussion comments and node deliverables into a consolidated Markdown audit report.

```bash
knot council reconcile [run_id]
```

- Saves report to `~/.config/knot/missions/<run_id>/reconciled_report.md` and marks mission `status: COMPLETED`.

---

#### `knot council copy`
Copies the staged prompt for the local node to the Wayland or X11 clipboard for GUI delivery (`--mode gui`).

```bash
knot council copy
```

---

#### `knot council kill`
Halts all running council runner processes and Kitty cockpit instances across the fleet.

```bash
knot council kill <run_id>
```

- Marks mission `status: TERMINATED` in `meta.json`.

---

#### `knot council clean`
Prunes mission directories older than the specified retention window.

```bash
knot council clean [days]        # Default: 7 days
```

---

## 2. `knot-installer` — Onboarding & Lifecycle CLI

The deployment binary responsible for Anchor bootstrapping, invitation token generation, Strand enrollment rendezvous, and clean uninstallation.

```bash
knot-installer <command> [options] [arguments...]
```

### `knot-installer init`
Initializes this workstation as an Anchor for a new Knot Mesh swarm.

```bash
knot-installer init [OPTIONS]
```

- **Options**:
  - `--name <name>`: Human-readable swarm name (e.g. `"Office Swarm"`).
  - `--id <id>`: Normalized profile slug (defaults to lowercased name, e.g. `office`).
  - `--port <port>`: Hub TLS listener port (default: `4242`).
  - `--anchor-id <id>`: Node ID for this Anchor workstation (default: `desktop`).
  - `--gateway-mac <mac>`: Gateway MAC for hardware network fencing (auto-detected if omitted).
  - `--ssid <ssid>`: Wi-Fi network SSID to fence this swarm (auto-detected if omitted).
  - `--subnet <cidr>`: Network subnet CIDR for PAM sudo verification (auto-detected if omitted).
  - `--headless`: Configure Anchor as a headless compute node without display outputs.
  - `--skip-firewall`: Skip automated UFW / firewalld rule injection.
  - `--skip-antigravity`: Skip automated Antigravity MCP and skills onboarding.

---

### `knot-installer invite`
Generates a secure, short-lived enrollment invitation token and coordinates rendezvous with incoming Strands.

```bash
knot-installer invite [OPTIONS]
```

- **Options**:
  - `--ttl <seconds>`: Token validity duration in seconds (default: `300`).
  - `--port <port>`: Hub port (default: `4242`).
  - `--host <host>`: Local Hub binding IP (default: `127.0.0.1`).
  - `--anchor-ip <ip>`: Explicit external IP address advertised to joining Strands.

- **Workflow**:
  1. Requests ephemeral 6-digit PIN and SHA-256 certificate fingerprint from `knot-hub`.
  2. Displays invitation banner, QR code, and one-liner `curl` join command.
  3. Blocks until the Strand connects via TLS.
  4. Prompts operator interactively for screen placement (`left`, `right`, `above`, `below`, `headless`).
  5. Compiles reciprocal Deskflow KVM server layout and pushes keys to the Strand.

---

### `knot-installer join`
Enrolls the local workstation or handheld as a Strand into an existing swarm.

```bash
knot-installer join <anchor_endpoint> <token> [OPTIONS]
```

- **Arguments**:
  - `<anchor_endpoint>`: Anchor IP or hostname and port (e.g. `192.168.68.153:4242`).
  - `<token>`: Pairing token in `<PIN>.<FINGERPRINT>` format.
- **Options**:
  - `--id <id>`: Custom node ID (defaults to local hostname).
  - `--role <role>`: Node role (`strand` or `headless`).
  - `--width <pixels>`: Override probed screen width.
  - `--height <pixels>`: Override probed screen height.
  - `--scale <factor>`: Override display scale factor (e.g. `1.25`).
  - `--auto`: Automated non-interactive enrollment mode.
  - `--skip-firewall`: Skip automated firewall configuration.
  - `--skip-antigravity`: Skip automated Antigravity MCP sync and skills setup.

---

### `knot-installer doctor`
Runs the comprehensive Knot diagnostics suite via `core/modules/doctor.sh`.

```bash
knot-installer doctor [arguments...]
```

---

### `knot-installer update`
Alias dispatch for `knot update`. Updates binaries and modules from GitHub release or Anchor.

```bash
knot-installer update [arguments...]
```

---

### `knot-installer uninstall`
Cleanly stops user services, unlinks local binaries, removes PAM sudo drop-ins, and cleans up runtime state.

```bash
knot-installer uninstall [-y]
```

- **Options**:
  - `-y, --yes`: Bypass confirmation prompt and execute immediately.
- **Actions**:
  - Stops and disables `knot-deskflow`, `knot-guard`, `knot-hub`, `knot-agent`, and `knot-autounlock`.
  - Cleans up `/run/knot` and transient sockets.
  - Preserves configuration files in `~/.config/knot` unless manually removed.
