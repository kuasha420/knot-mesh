---
name: Bug Report
about: Create a report to help us improve Knot Mesh
title: "[BUG] "
labels: ["bug"]
assignees: ""
---

## Description
A clear and concise description of the bug.

## Steps to Reproduce
1. Run `knot ...`
2. Configure node manifest in `~/.config/knot/swarms/<swarm_id>/nodes/`
3. See error

## Expected Behavior
A clear and concise description of what you expected to happen.

## Actual Behavior / Raw Diagnostics
Raw CLI exit codes, terminal output, or systemd journal logs (`journalctl --user -u knot-*`):
```text
<paste output here>
```

## Environment & Hardware Topology
- **OS / Distro**: (e.g. Arch Linux, SteamOS 3.6, Fedora 40)
- **Knot Mesh Version**: (e.g. `knot --version`)
- **Node Role**: Anchor Architect / Compute Worker / Handheld Controller
- **Display Server**: Wayland (KWin / gamescope / Sway) / X11

## Additional Context
Add any other context about the problem here (network configuration, VPN, Tailscale, KDE Connect status).
