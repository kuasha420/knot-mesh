# Knot DevOps Hygiene & Safety Guardrails

These rules govern automated and manual maintenance of the Knot mesh across all strands.

## 1. Zero Secret Leakage Boundary
- **Private keys (`~/.ssh/id_ed25519`) must NEVER be read, staged, committed, or transmitted.**
- Only public keys (`.pub`) and non-sensitive hardware metadata are tracked in git.
- Verify git status before any commit to ensure no key files are staged.

## 2. Drop-in Configuration Pattern (Non-Destructive)
- Never mutate base system files like `/etc/ssh/sshd_config`, `/etc/sudoers`, or `/etc/nsswitch.conf` directly when drop-in directories exist.
- Always use isolated drop-in configuration files:
  - SSH: `/etc/ssh/sshd_config.d/10-knot-keyonly.conf`
  - Sudo: `/etc/sudoers.d/99-knot-nopasswd`
  - Systemd: `/etc/systemd/system/knot-guard.service`
  - NetworkManager: `/etc/NetworkManager/dispatcher.d/99-knot-guard.sh`
- Always pre-validate configurations before restarting services:
  - `sshd -t`
  - `visudo -cf <file>`

## 3. Delimited Managed Blocks
- In files where drop-ins are not possible (e.g. `~/.ssh/authorized_keys`, `~/.ssh/config`):
  - Enclose Knot-managed lines in explicit markers:
    ```
    # >>> KNOT MESH MANAGED (DO NOT EDIT MANUALLY) >>>
    ...
    # <<< KNOT MESH MANAGED <<<
    ```
  - Never alter, delete, or overwrite user keys/configs outside these blocks.

## 4. Idempotency Guarantee
- Every tool, module, and sync command must be strictly idempotent:
  - Running `knot sync` multiple times in succession must produce zero drift and identical, stable system state.
  - Checks must test whether a rule or configuration is already applied before performing writes.

## 5. Strict Subnet & Network Gating
- Knot services and SSH port 22 must never be exposed to the global public Internet.
- Access is restricted exclusively to trusted local subnets (defined per swarm profile in `/etc/knot/swarms.d/*.conf`) and gated on verification of the gateway MAC.

## 6. Strict Error Transparency (No Silent Swallowing)
- As specified in `02-zero-error-swallowing.md`, silent error suppression via `2>/dev/null`, `|| true`, or `|| :` is strictly prohibited across all code, tests, and devops tooling.
- Always check preconditions, inspect exit codes, log diagnostic output, and fail fast.

