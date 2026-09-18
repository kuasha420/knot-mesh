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
Synchronizes declarative swarm manifests, screen topologies, and profile configurations.

```bash
knot sync                          # Standalone sync: pull latest manifests from Anchor
knot sync <node_id>                # Anchor mode: push configuration to a specific Strand
knot sync --all                    # Anchor mode: push configuration to all active Strands
```

---

### `knot update`
Swarm-wide binary and core module updater. Checks for new releases or synchronizes code changes from the Anchor across all Strands.

```bash
knot update                        # Check and update local node from GitHub release
knot update --all [-f]             # Anchor mode: rollout update across all active Strands
knot update <node_id> [-f]         # Anchor mode: rollout update to a specific Strand
```

- **Options**:
  - `-f, --force`: Force re-synchronization even if the remote tag or commit hash matches.
- **Workflow**:
  - Anchor updates local binaries.
  - Automatically pushes `bin/` and `core/` to target strands via `rsync` (or streaming `tar` fallback).
  - Atomically reloads background user services (`knot-agent`, `knot-stripd`) without interrupting active KVM sessions.

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
