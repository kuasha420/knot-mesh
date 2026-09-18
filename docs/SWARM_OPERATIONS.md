# Swarm Operations & Roaming Guide 🪢🌐

This manual details multi-tenant swarm management, automated hardware network fencing, roaming security guards, and distributed fleet operations across the Knot Mesh.

---

## Table of Contents

- [Declarative Swarm Architecture](#declarative-swarm-architecture)
- [Swarm Profile Structure](#swarm-profile-structure)
- [Network Roaming & Hardware Fencing](#network-roaming--hardware-fencing)
- [Knot Guard & Standalone Mode](#knot-guard--standalone-mode)
- [Switching Active Swarms](#switching-active-swarms)
- [Dynamic PAM Sudo Gate](#dynamic-pam-sudo-gate)
- [Antigravity Multi-Agent Orchestration](#antigravity-multi-agent-orchestration)
- [Fleet Operations & Maintenance](#fleet-operations--maintenance)
- [Power & Sleep Coordination](#power--sleep-coordination)

---

## Declarative Swarm Architecture

Knot Mesh isolates workstations into distinct, self-contained **swarms** (such as `home`, `office`, or `lab`).

Each swarm defines:
- An **Anchor** workstation that hosts the local Hub and coordinates KVM cursor routing.
- A set of **Strand** nodes enrolled via cryptographic pairing tokens.
- A **Network Fence** defined by Wi-Fi SSIDs, default gateway BSSIDs/MAC addresses, and IP CIDR subnets.
- A spatial screen layout (`topology.json`) defining physical screen adjacency.

Swarm configurations are stored across two complementary locations:
1. **User Scope**: `~/.config/knot/swarms/<swarm_id>/` (contains `swarm.conf`, `topology.json`, and `nodes/*.json`).
2. **System Scope**: `/etc/knot/swarms.d/<swarm_id>.conf` (used by systemd daemons and PAM security modules).

---

## Swarm Profile Structure

A swarm profile is defined in `swarm.conf`:

```bash
# Example: ~/.config/knot/swarms/office/swarm.conf
SWARM_ID="office"
SWARM_NAME="Office Studio Swarm"
ANCHOR_ID="desktop"
ANCHOR_HOST="kuasha-z490ud"
HUB_PORT=4242

# Physical Network Fence
GATEWAY_MACS="40:3f:8c:b3:6f:3c 00:11:22:33:44:55"
SSID="Studio-Mesh-5G"
SUBNET="192.168.68.0/24"

# Policy Gates
ALLOW_NOPASSWD_SUDO="true"
ALLOW_DESKFLOW_KVM="true"
```

### Key Parameters:
- `GATEWAY_MACS`: Space-separated list of hardware MAC addresses for your network router/gateway. Knot matches ARP tables against this list to prevent spoofing.
- `SUBNET`: Network CIDR block (e.g. `192.168.68.0/24`). Connections originating outside this block are denied by PAM gates and UFW rules.
- `ALLOW_NOPASSWD_SUDO`: If `"true"`, passwordless `sudo` is dynamically enabled when the device is physically located inside this swarm fence.

---

## Network Roaming & Hardware Fencing

Laptops and handhelds roam frequently between home, office, and public Wi-Fi. Knot Mesh eliminates manual re-configuration through the **NetworkManager Dispatcher Guard** (`knot-guard.service`).

### How Hardware Fencing Works:
1. NetworkManager triggers `/etc/NetworkManager/dispatcher.d/99-knot-guard` on every interface `up` or `dhcp4-change` event.
2. `knot-guard` inspects:
   - Current default gateway IP via `ip route show default`.
   - Hardware MAC address of the gateway via `ip neigh` / `/proc/net/arp`.
   - Current connected Wi-Fi SSID via `iwgetid -r` or `nmcli`.
3. `knot-guard` iterates through all registered swarm profiles:
   - If the active MAC/SSID matches a profile, it executes `knot_set_active_swarm <swarm_id>`.
   - If no profile matches, it enters **Standalone Mode**.

---

## Knot Guard & Standalone Mode

When you connect to an unknown network (coffee shop, airport, university public Wi-Fi):

1. **KVM Boundary Isolation**:
   - `knot-guard` immediately disables `knot-deskflow.service`.
   - Your keyboard and mouse remain 100% local; external cursor transitions are disabled.
2. **PAM Sudo Demotion**:
   - Dynamic passwordless sudo is immediately deactivated.
   - Sudo falls back to requiring your master user password.
3. **Tuplespace Agent Disconnection**:
   - `knot-agent.service` pauses mesh polling.
4. **Hardened SSH Fallback**:
   - OpenSSH remains active for authorized key logins, but non-subnet access is dropped by the local firewall.

When you return to your desk at home or office, `knot-guard` detects the matching Gateway MAC and re-enables all services automatically within 1.5 seconds.

---

## Switching Active Swarms

To manually switch profiles (or force a specific swarm profile):

```bash
# Switch active profile to 'office'
knot swarm switch office

# Switch active profile to 'home'
knot swarm switch home
```

To view current swarm status and fence match:

```bash
knot swarm status
```

---

## Dynamic PAM Sudo Gate

Knot Mesh implements passwordless `sudo` that is physically contingent on being connected to your verified hardware network.

- **Configuration**: `/etc/pam.d/sudo` includes `/etc/pam.d/knot-pam-sudo`.
- **Validation**:
  - The PAM module verifies that `/run/knot/active_swarm` is set to a valid swarm.
  - Checks that `ALLOW_NOPASSWD_SUDO="true"` in the active profile.
  - Verifies that the client IP matches the configured `SUBNET`.
  - Confirms the gateway MAC matches `GATEWAY_MACS`.

If any condition fails, standard password authentication is enforced.

---

## Antigravity Multi-Agent Orchestration

Knot integrates natively with Google Antigravity (AGY) to enable distributed multi-agent pair programming and headless task dispatch across all swarm nodes.

### 1. Unified MCP Gateway
- All nodes run `core/mcp/gateway.py` via `~/.gemini/config/mcp_config.json`.
- Tools include:
  - `knot_task_post`: Post background tasks to remote nodes.
  - `knot_task_wait`: Await completion of distributed tasks.
  - `knot_gpu_status`: Monitor remote NVIDIA / AMD VRAM and utilization.
  - `knot_memory_store` / `knot_memory_recall`: Distributed Memory Palace.

### 2. Pre-Approved Operational Skills
All nodes share standardized skill bundles in `~/.gemini/antigravity/skills/`:
- `knot-swarm`: Multi-node health, synchronization, and telemetry.
- `core-mesh`: Spatial topology, KVM boundaries, and Deskflow configuration.
- `remote-control`: Secure execution and power management.
- `vision`: Automated camera-based desk topology detection.

### 3. Swarm Telemetry & Testing
To verify Antigravity agent connectivity across the mesh:

```bash
knot swarm test local             # Test local agy execution
knot swarm test laptop            # Probe latency and telemetry to laptop
knot swarm auth --all             # Verify OAuth credentials across entire fleet
```

---

## Fleet Operations & Maintenance

### 1. Coordinated Binary & Module Updates
When changes are pulled on the Anchor, deploy them to all active Strands with zero downtime:

```bash
knot update --all
```

- Synchronizes `bin/` and `core/` via streaming `rsync`.
- Reloads `knot-agent.service` and `knot-stripd.service`.
- Preserves active Deskflow KVM cursor control during rollout.

### 2. Declarative Topology Synchronization
To distribute updated node manifests or display layouts:

```bash
knot sync --all
```

### 3. Fleet Command Execution
Execute commands concurrently across all active nodes:

```bash
# Check kernel versions across the entire fleet
knot exec --all "uname -r"

# Check GPU temperatures
knot exec --all "nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null || sensors | grep -i edge"
```

---

## Power & Sleep Coordination

### 1. Headless Autounlock & Session Resumption
When you unlock the Anchor workstation (via password or fingerprint):
- `knot-autounlock.service` broadcasts an unlock signal over mDNS/Hub.
- Strands at the login screen automatically unlock their Wayland graphical sessions via `plasma-login-manager`.

### 2. Fleet Power Management
Schedule coordinated reboots or power-offs:

```bash
# Schedule full mesh shutdown in 15 minutes with a broadcast wall message
knot shutdown --all poweroff --delay +15 --wall "System maintenance in 15m"

# Cancel pending scheduled shutdown
knot shutdown cancel
```
