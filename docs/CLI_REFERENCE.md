# Knot Mesh CLI Reference Manual 🪢⚡

This document provides a comprehensive command-line reference for both `knot` (daily mesh orchestrator) and `knot-installer` (bootstrap, onboarding, and lifecycle utility).

---

## Table of Contents

- [Global Environment Variables](#global-environment-variables)
- [Error Handling & Diagnostic Observability (PSL Gold Standard)](#error-handling--diagnostic-observability-psl-gold-standard)
- [1. Core Mesh Administration Commands](#1-core-mesh-administration-commands)
  - [knot status](#knot-status)
  - [knot doctor](#knot-doctor)
  - [knot repair](#knot-repair)
  - [knot sync](#knot-sync)
  - [knot update](#knot-update)
  - [knot resolve](#knot-resolve)
  - [knot exec](#knot-exec)
  - [knot shutdown](#knot-shutdown)
  - [knot reboot](#knot-reboot)
  - [knot onboard](#knot-onboard)
- [2. Tier 1: D2D Physical Workspace Fabric Commands](#2-tier-1-d2d-physical-workspace-fabric-commands)
  - [knot kvm](#knot-kvm)
  - [knot screen](#knot-screen)
  - [knot autologin](#knot-autologin)
  - [knot kdeconnect](#knot-kdeconnect)
  - [knot topology](#knot-topology)
  - [knot sleep](#knot-sleep)
- [3. Tier 2: A2A Cognitive Swarm Layer Commands](#3-tier-2-a2a-cognitive-swarm-layer-commands)
  - [knot council](#knot-council)
  - [knot swarm](#knot-swarm)
  - [knot quota](#knot-quota)
  - [knot auth](#knot-auth)
  - [knot memory](#knot-memory)
  - [knot hub](#knot-hub)
  - [knot agent](#knot-agent)
  - [knot task](#knot-task)
  - [knot project](#knot-project)
  - [knot worktree](#knot-worktree)
  - [knot chat](#knot-chat)
  - [knot artifact](#knot-artifact)
- [4. Handheld & Graphical Cockpit Commands](#4-handheld--graphical-cockpit-commands)
  - [knot kafe](#knot-kafe)
  - [knot web](#knot-web)
- [5. `knot-installer` — Onboarding & Lifecycle CLI](#5-knot-installer--onboarding--lifecycle-cli)
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
| `KNOT_VERSION` | Knot release version override. | `1.0.0-rc5` |
| `KNOT_TEST_MODE` | If set (`1`), bypasses graphical prompts and system modifications. | Empty |
| `KNOT_HUB_URL` | Explicit Knot Hub endpoint URL override. | `https://127.0.0.1:4242` |
| `KNOT_DEBUG` | Enables verbose diagnostic traces on stderr if set (`1`). | Empty |

---

## Error Handling & Diagnostic Observability (PSL Gold Standard)

All Knot Mesh CLI utilities, daemon processes, and test suites strictly enforce the **PSL Gold Standard**:
- **Zero Error Swallowing**: Subcommands never swallow errors or discard stderr into `/dev/null` (`2>/dev/null`, `&>/dev/null`, `>/dev/null 2>&1`, `|| true`, and `|| :` are permanently banned).
- **Exit Code Contracts**:
  - `0`: Operation succeeded; target is healthy and operational.
  - `1`: Operational failure, health check violation, or unreachable peer.
  - `2`: Invalid CLI syntax or unknown arguments.
- **Diagnostic Logging Format**:
  - `[✓]` (Green): Successful state transition or healthy component.
  - `[•]` (Cyan/Blue): Informational progress or active dispatch notice.
  - `[!]` (Yellow): Warning, locked state, or non-fatal diagnostic emitted to `stderr`.
  - `[✗]` (Red): Hard error, broken precondition, or failed execution emitted to `stderr`.
- **Automated Validation**: Automated CI verification via `tests/test_psl_integrity.sh` ensures ongoing compliance across 100% of codebase files.

---

## 1. Core Mesh Administration Commands

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

### `knot resolve`
Resolves a canonical node ID to its active reachable IP address and SSH port using the 3-tier resolution sequence: lease cache $\to$ mDNS $\to$ manifest IP hint $\to$ hardware MAC ARP scan.

```bash
knot resolve <node_id> [port] [--proxy] [--swarm <id>]
```

- **Options**:
  - `--proxy`: Formats output for OpenSSH `ProxyCommand` and verifies TCP connectivity to SSH port.
  - `--swarm <id>`: Explicit swarm profile to search for target node manifests.
- **Exit Codes**:
  - `0`: Node resolved and verified reachable. IP emitted to `stdout`.
  - `1`: Node unresolvable or dead. Diagnostics emitted to `stderr`.

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

### `knot shutdown`
Coordinates graceful service teardown, task release, and poweroff/reboot operations across the mesh.

```bash
knot shutdown status               # Show pending shutdown/reboot timers across the fleet
knot shutdown cancel               # Cancel pending scheduled shutdown timers
knot shutdown [node] poweroff      # Power off a specific node immediately
knot shutdown [node] reboot        # Reboot a specific node immediately
knot shutdown --all poweroff       # Gracefully power off all Strands, then the Anchor
knot shutdown --all reboot         # Reboot all Strands, then the Anchor
```

- **Options**:
  - `-d, --delay <minutes|now>`: Delay before shutdown (e.g. `+10`, `23:00`, or `now`).
  - `-m, --msg "<message>"`: Custom broadcast message sent to all logged-in users.
  - `-f, --force, -y`: Bypass operator confirmation prompt.

---

### `knot reboot`
Convenience alias for `knot shutdown --reboot`. Coordinates fleet-wide reboot sequencing.

```bash
knot reboot [target] [options...]
```

---

### `knot onboard`
Enrolls the current machine into the local mesh, provisioning SSH host keys, configuring firewall rules, and deploying system services.

```bash
knot onboard [node_id]
```

---

## 2. Tier 1: D2D Physical Workspace Fabric Commands

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
Advisory opt-in auto-login and display manager orchestration module. Eliminates first-login friction on Strands when Anchor is online and unlocked without forcing destructive system changes.

```bash
knot autologin status              # Inspect autologin readiness, current session, and DM config
knot autologin check               # Non-mutating advisory check of DM compatibility and config
knot autologin doctor              # Deep health diagnosis of display manager and autologin preconditions
knot autologin migrate-dm          # Opt-in display manager migration for headless Wayland auto-unlock (interactive confirmation)
knot autologin local               # Execute local session login/unlock sequence
knot autologin reconcile           # Reconcile auto-login across all reachable swarm strands
knot autologin fix-kwallet         # Launch KDE Wallet password manager to configure empty password for unattended autologin
knot autologin <node_id>           # Trigger remote auto-login on a specific strand node
```

- **Features & Safety Guarantees**:
  - **Advisory Non-Destructive Operation**: Display manager migrations are strictly opt-in; existing display managers (GDM, LightDM, SDDM) are never replaced without explicit user confirmation.
  - **Configuration Backups & Cleanup**: Automatic backup creation (`.bak`) before modifying any DM configuration, with cleanup traps ensuring atomic writes.
  - **KWallet Prompt Elimination**: `fix-kwallet` launches the KDE Wallet password manager dialog to configure empty passwords, avoiding GUI unlock prompts during unattended boot.

---

### `knot kdeconnect`
Manages KDE Connect mesh synchronization, custom device discovery, device pairing, and cross-device clipboard sharing.

```bash
knot kdeconnect status             # Show paired devices, IP hints, and clipboard status locally
knot kdeconnect status --all       # Fleet-wide KDE Connect status across all active swarm nodes
knot kdeconnect sync               # Synchronize swarm IP hints into local customDevices & enforce clipboard plugins
knot kdeconnect sync --all         # Propagate customDevices and enforce clipboard across the entire fleet
knot kdeconnect pair <node_id>     # Initiate bidirectional pairing request with a specific mesh peer
```

---

### `knot topology`
Multi-screen spatial topology reasoning and visual layout management module. Renders 2D spatial ASCII representations of active swarm displays, triggers camera-based computer vision layout analysis, aligns multi-display outputs, and flashes high-contrast display overlays.

```bash
knot topology [show|refresh|align-internal|identify|guide] [options]
```

- **Subcommands**:
  - `knot topology show`: Displays current 2D ASCII screen layout, Anchor screen identity, and active screen boundaries.
  - `knot topology refresh --photo <path> [--mode auto|swarm|offline] [--apply]`: Analyzes a photo of physical monitors using computer vision, inferring relative physical screen positions, spans, and boundaries.
  - `knot topology align-internal`: Automatically aligns internal handheld displays (eDP-1) with connected external monitors via KDE KScreen.
  - `knot topology identify [--all]`: Spawns fullscreen high-contrast colored overlays displaying node identity and display numbers across screens.
  - `knot topology guide`: Outputs photography, lighting, and camera positioning best practices for spatial detection.

---

### `knot sleep`
Enforces whole-swarm prevent-sleep power policies on AC power while permitting natural power-saving sleep on battery.

```bash
knot sleep status                  # Display swarm sleep inhibition state and active workload drivers
knot sleep prevent [reason]        # Prevent sleep across active nodes
knot sleep allow                   # Re-enable natural sleep policies
```

---

## 3. Tier 2: A2A Cognitive Swarm Layer Commands

### `knot council`
Out-of-band multi-agent coordination protocol using GitHub Discussions, Mesh DB, and scale-aware Kitty Confluence multiplexing.

```bash
knot council <start|resume|status|reply|steer|list|attach|reconcile|copy|clean|kill> [options]
```

#### `knot council start`
Launches an autonomous council mission or zero-token interactive multi-node cockpit.

```bash
# Autonomous Mission
knot council start [--mode <mode>] [--db <ghd|mesh>] [--tiling <layout>] [--pack <pack>] [--prompt <text>]

# Zero-Token Interactive Cockpit (<1s startup, 0 prompt tokens consumed)
knot council start --interactive [--tiling <layout>] [--project <name>] [--nodes <list>]
```

#### `knot council resume`
Re-opens the Kitty Confluence cockpit and re-attaches all swarm nodes to active conversations using `agy -c`.

```bash
knot council resume [run_id]
```

#### `knot council steer`
Injects steering prompts live into a target node's active Kitty Confluence pane via Kitty remote socket (`/tmp/kitty-council-<run_id>.sock`).

```bash
knot council steer <node> "<prompt>" [run_id]
```

#### `knot council status`
Inspects real-time milestone progress, node check-ins, and peer updates for a mission.

```bash
knot council status [run_id]
```

#### `knot council reply`
Posts status checkpoints, alerts, or final reports to the mission registry.

```bash
knot council reply <run_id> [--node <id>] [--status <25%|50%|75%|ALERT|FINAL|PROGRESS>] [--body "<text>"]
```

#### `knot council board`
Launches the live zero-token Swarm Council Message Board terminal viewer, streaming active mission threads and peer check-ins in real time.

```bash
knot council board                 # Auto-detect terminal width and render live viewer
knot council board --compact       # Force handheld compact view (Steam Deck / ROG Ally <= 80 cols)
knot council board --wide          # Force wide split-pane view (> 100 cols)
knot council board --render-once   # Render a single snapshot of the message board and exit
```

---

### `knot swarm`
Manages multi-tenant swarm profiles and Antigravity multi-agent cluster operations.

```bash
knot swarm status                  # List configured swarm profiles and active fence
knot swarm switch <swarm_id>       # Switch active swarm profile (e.g. home, office)
knot swarm test [node_id]          # Test Antigravity CLI telemetry and ping latency
knot swarm auth [node_id]          # Verify Google OAuth token validity for headless agy
knot swarm quota [node|--all]      # Inspect real-time 5h and weekly model quotas
knot swarm exec <node> <cmd...>    # Run commands across swarm nodes
```

---

### `knot quota`
Direct alias for `knot swarm quota`. Displays real-time 5-hour and weekly Google AI Pro/Ultra and Antigravity model quota consumption, active reset countdowns, and graphical progress bars across the mesh.

```bash
knot quota                         # Display formatted quota matrix for all online nodes
knot quota <node_id>               # Display quota matrix for a specific node
knot quota live                    # Launch the live zero-token terminal visualizer (auto-detects width)
knot quota live --compact          # Force handheld compact card layout (Steam Deck / ROG Ally <= 80 cols)
knot quota live --wide             # Force wide tabular layout (> 100 cols)
knot quota live --render-once      # Render a single snapshot of the quota visualizer and exit
```

- **Account Tier Awareness**:
  - Automatically identifies **Google AI Pro** (active 5-hour rolling limit + weekly limit).
  - Automatically identifies **Antigravity Starter Quota** (weekly limit only, gracefully formatting 5-hour limits as `[ WEEKLY ONLY ]   N/A` without false 100% progress bars).

---

### `knot auth`
Manages multi-tenant Antigravity Google OAuth sandboxing under `~/.config/knot/auth/`, headless login flows, token synchronization from FreeDesktop Secret Service / KWallet, atomic profile switching, and zero-leakage node isolation.

```bash
# Profile Inspection
knot auth status                   # Show active profile, email, plan tier, token expiry, and keyring state
knot auth status --all             # Fleet-wide authentication status sweep across all strands
knot auth status --json            # Output local auth status as JSON
knot auth list                     # List all locally registered authentication profiles
knot auth list --all               # Fleet-wide profile list sweep across all strands

# Profile Management
knot auth login <alias> [--no-browser] # Enroll new profile sandbox (uses PKCE; cuts off keyring collision)
knot auth switch <alias>          # Atomically switch active profile via symlink and update Secret Service
knot auth remove <alias>          # Delete an inactive profile sandbox (protected against active profile)
knot auth import <alias> [file]   # Import an existing oauth-token.json into a hardened sandbox (0700/0600)
knot auth test-lock               # Non-blocking probe of Secret Service / KWallet lock state

# Token Synchronization & Remote Dispatch
knot auth sync                    # Synchronize tokens from Secret Service / KWallet into active sandbox
knot auth sync --all              # Fleet-wide token synchronization across all active nodes
knot auth <node_id> --gui         # Launch graphical Konsole directly on target node's display

# Targeted Node Dispatch (Zero boilerplate)
knot auth <node_id> <action> [args...]  # e.g., knot auth rog-ally switch secondary
knot auth <action> -n <node_id>         # e.g., knot auth status -n laptop
knot auth <action> --node <node_id>     # e.g., knot auth list --node steamdeck
```

- **Security & Sandboxing Invariants**:
  - **Zero Network Credential Leakage**: Tokens and credentials remain strictly node-local. Remote dispatches execute via SSH subshells on the target node; credentials are never transmitted over the wire.
  - **Hardened Permissions**: Profile directories are enforced at `0700` and `oauth-token.json` files at `0600`.
  - **Atomic Symlink Switching**: Upstream CLI tools resolve active credentials via atomic symlink swaps, preventing intermediate read errors during account changes.


---

### `knot memory`
Decentralized Memory Palace and Vault module backed by embedded SQLite with CRDT synchronization and in-process vector cosine similarity.

```bash
knot memory <store|recall|map|promote|relate|artifact-put|artifact-get|profile|export-crdt|test> [options]
```

- **Subcommands**:
  - `knot memory store`: Stores a memory into the spatial palace.
    ```bash
    knot memory store --wing <wing> --hall <hall> --drawer <drawer> --title "<title>" --content "<content>" [--pool shared|local] [--importance 1-10] [--tags t1,t2]
    ```
  - `knot memory recall`: Recalls memories using vector cosine similarity or spatial path query.
    ```bash
    knot memory recall --query "<search text>" [--wing <wing>] [--hall <hall>] [--pool shared|local|all] [--limit 5] [--min-score 0.1]
    ```
  - `knot memory map`: Displays the complete spatial hierarchy tree of memories stored in the local SQLite palace.
  - `knot memory promote`: Promotes a local scratchpad observation to the swarm-shared memory pool with an importance boost.
  - `knot memory relate`: Creates an associative typed edge between two memories.
  - `knot memory profile <role_or_node>`: Displays hardware node-role profile, constraints, and system prompt.
  - `knot memory test`: Runs the comprehensive embedded SQLite memory palace self-test suite.

---

### `knot hub`
Controls the Knot Swarm Blackboard Hub daemon (`knot-hub.service`), providing Linda tuplespaces, task leasing, and SSE event streaming.

```bash
knot hub start                     # Start knot-hub.service
knot hub stop                      # Stop knot-hub.service
knot hub restart                   # Restart knot-hub.service
knot hub status                    # Query service status and verify /health endpoint
knot hub logs                      # Follow journalctl logs for knot-hub.service
```

---

### `knot agent`
Controls the local Knot Swarm Worker Agent daemon (`knot-agent.service`), executing background tasks claimed from the Blackboard.

```bash
knot agent start                   # Start knot-agent.service
knot agent stop                    # Stop knot-agent.service
knot agent restart                 # Restart knot-agent.service
knot agent status                  # Inspect worker agent status
knot agent logs                    # Follow journalctl logs for knot-agent.service
```

---

### `knot task`
Manages Linda Tuplespace tasks, batch schedules, and execution monitoring.

```bash
knot task post "<prompt>" [--plane <plane>] [--title <title>]  # Post new task to Blackboard
knot task list [status]            # List tasks (QUEUED, CLAIMED, RUNNING, COMPLETED, FAILED)
knot task batch <batch_id>         # Inspect batch progress
knot task wait <task_id>           # Follow task execution until completion
```

---

### `knot project`
Manages native Antigravity multi-folder project registrations and cross-node worktrees.

```bash
knot project list                  # List registered projects
knot project get <project_id>      # Inspect project metadata
knot project sync [project_id]     # Synchronize project workspaces across nodes
```

---

### `knot worktree`
Manages cross-node Git worktrees without duplicate clones, preserving storage and eliminating fetch contention.

```bash
knot worktree list                 # List active git worktrees across the mesh
knot worktree add <repo> <name> [--branch <b>] [--nodes <n1,n2>]  # Provision worktree mesh
knot worktree remove <repo> <name> # Cleanly delete worktree across target nodes
```

---

### `knot chat`
Manages Swarm Konversations channels, inter-agent chat messaging, and persistent channel logs.

```bash
knot chat channels                 # List active chat channels
knot chat create <channel_id> [title] [-p project_id]  # Create a new channel
knot chat post [-c channel] [-s sender] <message>      # Post message to channel
knot chat read [-c channel] [-n limit]                 # Read channel history
```

---

### `knot artifact`
Manages 3-state artifact leases (`DRAFTING`, `LOCKED_SURGERY`, `VERIFIED_COMMITTED`) preventing concurrent file mutation collisions across agents.

```bash
knot artifact list                 # List active artifact leases and expiry countdowns
knot artifact lock <name> [--ttl <sec>]  # Acquire LOCKED_SURGERY lease on an artifact
knot artifact release <name> [--state <state>] # Commit and release artifact lease
```

---

## 4. Handheld & Graphical Cockpit Commands

### `knot kafe`
Boots and manages the Knot Kommand Kafe cockpit (Tauri v2 lightweight desktop container and React Web UI).

```bash
knot kafe open                     # Open web cockpit in default browser
knot kafe desktop                  # Launch native Tauri v2 desktop container (<50MB RAM footprint)
knot kafe build-desktop            # Compile release Tauri v2 container binary
knot kafe dev                      # Launch Vite HMR development server (:5173)
knot kafe build                    # Build production static bundle to web/dist
knot kafe install                  # Install web cockpit npm dependencies
```

---

### `knot web`
Direct alias dispatch for `knot kafe`.

```bash
knot web [open|dev|build|install]
```

---

## 5. `knot-installer` — Onboarding & Lifecycle CLI

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
  - `<anchor_endpoint>`: Anchor IP or hostname and port (e.g. `192.168.1.50:4242`).
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
