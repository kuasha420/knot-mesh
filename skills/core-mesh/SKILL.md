---
name: knot-core-mesh
description: Orchestrate and execute tasks across the Knot mesh (Desktop Anchor, Laptop, Steam Deck). Use when executing commands, verifying strand status, or deploying configs across nodes.
---

# Knot Core Mesh Skill

Allows AI agents to discover, inspect, and execute commands across any active strand in the Knot mesh.

## Capabilities

### 1. Check Mesh Status & Reachability
```bash
knot status
```
Outputs online state, active IP, network interface (Wi-Fi vs Ethernet dock), and round-trip latency for all registered nodes.

### 2. Execute Commands on a Specific Strand
```bash
knot exec <strand-id> "<command>"
```
Examples:
- `knot exec laptop "uptime"`
- `knot exec steamdeck "systemctl status sshd"`
- `knot exec laptop "sudo pacman -Syu --noconfirm"`

### 3. Broadcast Commands Across All Strands
```bash
knot exec --all "<command>"
```
Runs the command in parallel or sequence across all active strands and aggregates output.

### 4. Dynamic Node Resolution
```bash
knot resolve <strand-id> [port]
```
Resolves the current reachable IP of any strand using mDNS -> MAC lookup -> Subnet probe.
