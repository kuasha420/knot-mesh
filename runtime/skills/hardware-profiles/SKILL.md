---
name: hardware-profiles
description: Hardware node-role system prompt profiles for Knot Swarm strands (Anchor Architect, Compute Worker, Handheld Controller). Use to adopt or inspect role-specific constraints, hardware acceleration instructions, and operational invariants.
---

# Hardware Node-Role System Prompt Profiles

Formal system prompt profiles defining hardware specializations, operational boundaries, and swarm coordination responsibilities across physical nodes.

## 1. Profiles Roster
- **Anchor Architect** (`@desktop`): Primary mainline workstation, high RAM, GPG commit signer (`<CONFIGURED_GPG_KEY_ID>`), Knot Hub TLS authority (`:4242`), Swarm Governance.
- **Compute Worker** (`@laptop`): Worker Alpha, NVIDIA RTX 3050 CUDA acceleration, Python daemons (`knot-agent`, `knot-hub`), stateless MCP Gateway, in-process vector indexing, concurrency stress tests.
- **Handheld Controller** (`@rog-ally`, `@steamdeck`): Worker Beta/Gamma, AMD Van Gogh APU / Ryzen Z1 Extreme, 7"-8" touch & gamepad UX, SteamOS immutable rootfs, Wayland/Gamescope compositor, <50MB RAM container constraint.

## 2. Access via CLI & Python API
```bash
# Query role profile via Knot Memory CLI
knot memory profile anchor_architect
knot memory profile compute_worker
knot memory profile handheld_controller
```

```python
from core.memory.profiles import get_profile

profile = get_profile("compute_worker")
print(profile["system_prompt"])
```
