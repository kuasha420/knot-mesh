---
name: mesh-ops
description: >-
  Standardized Knot hardware mesh coordination runbook for multi-node topology inspection,
  dynamic node discovery, Tailscale and WireGuard connectivity probes, SSH multiplexing,
  and state synchronization across Desktop, Laptop, and Handheld nodes.
---
<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Arafat Zahan (@kuasha420) -->
<!-- Corporate Stewardship & Infrastructure: Purrfect Software Limited (PSL) -->
<!-- Governed by: ICARO-42/b Ordinance (Company-Supported Personal IP Framework) -->

# PSL Mesh Operations: Knot Swarm Fleet Coordination & Connectivity Runbook

This skill establishes empirical runbooks for Knot hardware mesh coordination, dynamic topology discovery, Tailscale and WireGuard connectivity probes, SSH multiplexing, and cross-node state synchronization.

---

## 1. Dynamic Node Discovery & Topology Inspection

### Invariant: Bounded Timeouts on Mesh Probes
All remote probes must enforce strict network timeouts (`ConnectTimeout=2`, bounded ping count `-c 2`) to prevent hung agent turns when nodes are asleep or off-mesh.

### 1.1 Knot Fleet Roles & Hostnames
The Knot mesh fleet comprises four distinct operational strand tiers:
- **`desktop` (Anchor Architect)**: Primary workstation, storage hub, persistent daemon anchor.
- **`laptop` (Compute Worker)**: CUDA/Tensor acceleration worker, isolated build executor.
- **`rog-ally` / `steamdeck` (Handheld Controllers)**: Mobile monitoring, controller displays.

### 1.2 Tailscale & WireGuard Connectivity Probes
Verify VPN mesh routing and latency before initiating multiplexed operations:
```bash
# Check local Tailscale daemon status and peer table
tailscale status --json | jq -r '.Peer[] | "\(.HostName)\t\(.TailscaleIPs[0])\tOnline=\(.Online)"'

# Ping node via Tailscale with bounded timeout
tailscale ping -c 2 <target_node>

# Fallback: check WireGuard interface status if native wg is configured
command -v wg >/dev/null && (wg show || [ $? -eq 1 ])
```

### 1.3 Rapid Strand Liveness Check
Quickly test SSH reachability without interactive authentication prompts:
```bash
# Fast batch liveness probe (exits 0 if reachable, non-zero if offline)
ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new <target_node> "echo OK"
```

---

## 2. SSH Multiplexing & ControlMaster Management

### Invariant: Zero Exit Code 255 (Unclean SSH Terminations)
Prevent SSH dropouts and connection exhaustion using persistent ControlMaster sockets:

### 2.1 ControlMaster Inspection via Agyis CLI
Check and inspect active OpenSSH ControlMaster connection sockets:
```bash
# List active ControlMaster sockets
agyis remote socket status

# Test target node reachability through active socket
ssh -O check <target_node> && echo "Socket active" || ( [ $? -eq 255 ] && echo "No active socket" )
```

### 2.2 Socket Cleanup
Prune dead or hung connection sockets across `/tmp` or `~/.ssh/sockets/`:
```bash
# Graceful socket exit
ssh -O check <target_node> && ssh -O exit <target_node> || [ $? -eq 255 ]

# Harness CLI socket cleanup
agyis remote socket cleanup
```

---

## 3. Remote Execution & Stdin Script Streaming

### 3.1 Zero-Disk Footprint Script Streaming
Avoid writing temporary script files to the remote node's filesystem:
```bash
# Execute local script on remote target via stdin streaming (zero remote disk footprint)
agyis remote script <target_node> <local_script_path>
```

### 3.2 Staged Execution with Trap Cleanup
For multi-command tasks requiring remote temporary files, stage execution with automatic signal trap cleanup:
```bash
agyis remote script <target_node> <local_script_path> --stage
```

### 3.3 Compact Fleet Triage (<2KB Report)
Run multi-component health diagnostics with output compaction:
```bash
agyis remote triage <target_node>
```

---

## 4. Cross-Strand State Synchronization

### 4.1 Safe Worktree and Codebase Synchronization
Sync project repositories or scratch worktrees between nodes without clobbering local secrets (`.env`):
```bash
# Synchronize codebase to remote worker excluding secrets and git database
rsync -azP --delete \
    --exclude=".env" \
    --exclude=".git" \
    --exclude="data/*.db" \
    --exclude="__pycache__" \
    ./ <target_node>:/path/to/target/dir/
```

### 4.2 Linda Tuplespace & Worktree Sync
In multi-agent swarm missions, coordinate state across nodes using Linda Tuplespace out-of-band directories:
```bash
# Probe Tuplespace barrier state
ssh -o BatchMode=yes <target_node> "[ -d ~/.knot/tuplespace ] && ls -la ~/.knot/tuplespace/"
```

### 4.3 KDE Connect Local Notification Dispatch
Send non-intrusive operator alerts to nearby mobile devices or paired workstations:
```bash
# List available paired KDE Connect devices
kdeconnect-cli --list-available

# Send notification ping to paired device
kdeconnect-cli --device <device_id> --ping-msg "Knot Swarm Phase Complete"
```
