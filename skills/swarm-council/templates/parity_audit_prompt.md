# Knot Mesh: Full Codebase Parity & Architecture Audit Mission

## 1. Executive Objective
Conduct a comprehensive, multi-node verification audit comparing the legacy private development prototype (`kuasha420/knot` at `~/Dev/knot`) against the clean public release codebase (`kuasha420/knot-mesh` at `~/Dev/knot-mesh`).

Your goal is to certify whether `knot-mesh` achieves 100% functional parity, eliminates legacy baggage and sensitive leaks, upholds rigorous Bash standards (Rule 02), and is officially ready for General Availability (GA `v1.0.0`).

---

## 2. Scope of Audit & Assigned Modules

Audit both your primary assigned chunks and cross-cutting systems:
1. **Core Runtime & Networking**:
   - `bin/knot` (CLI dispatcher and subcommands)
   - `core/lib.sh` (logging, state resolution, helpers)
   - `core/resolver.sh` (3-tier resolution: mesh -> LAN -> Tailscale)
   - `core/modules/ssh.sh` (SSH connection multiplexing & control paths)
   - `core/modules/doctor.sh` (mesh health probes & diagnostics)
2. **KVM, Displays & Peripheral Sync**:
   - `core/modules/deskflow.sh` (Deskflow reciprocal config compiler & barrier confinement)
   - `core/modules/topology.sh` & `display.sh` (spatial layout mapping, kscreen-doctor / wlr-randr parsers)
   - `core/modules/kdeconnect.sh` (peer node sync, customDevices mobile preservation, Wayland clipboard daemon)
3. **Security, Lifecycle & Installers**:
   - `bin/knot-installer` (clean-slate Anchor init & Strand join flows)
   - `core/modules/autologin.sh` & `autounlock.sh` (KWallet, SDDM, PAM auto-login security boundaries)
   - `core/modules/shutdown.sh` (graceful swarm-wide coordination)
4. **Intelligence, Coordination & Memory**:
   - `core/modules/council.sh` & `skills/swarm-council/` (out-of-band multi-agent coordination)
   - `core/modules/memory.sh` & `core/memory/palace.py` (Cognitive Memory Palace SQLite state)

---

## 3. Strict Verification & Parity Criteria

For each module in your assigned chunks:
1. **Feature & Bugfix Parity**:
   - Inspect `diff -u ~/Dev/knot/<path> ~/Dev/knot-mesh/<path>`.
   - Confirm all critical bugfixes and operational logic from the private prototype are present.
   - Verify that all legacy GitOps registry references (`registry/nodes/`) have been properly migrated to local swarm directory state (`swarms/<id>/nodes/`).
2. **Rule 02 Strict Compliance**:
   - Run `bash -n <script>` on all shell files.
   - Verify `set -euo pipefail` is enforced.
   - Zero error swallowing: confirm there are NO bare `|| true` suppressions on critical commands.
3. **Baggage & Leak Elimination**:
   - Verify zero hardcoded paths or credentials.
   - Confirm that temporary test artifacts or deprecated files are not lingering.
4. **Edge Case & Failure Resilience**:
   - Test offline peer handling, roaming IP changes, Wayland vs X11 display fallbacks, and concurrent invocation safety.

---

## 4. Hardware Domain Profile & 30% Side Quest

- Apply your local node's hardware specialization (Desktop Anchor, Laptop CUDA/roaming, ROG Ally 120Hz/dual-swarm, SteamDeck APU/SteamOS).
- Dedicate ~30% of your operational effort to an autonomous **Side Quest**: explore an unverified edge case, concurrency scenario, or stress test of your own initiative. Explicitly report the hypothesis, test method, and findings.

---

## 5. Coordination Protocol (Swarm Council Skill)

You are operating under the **Swarm Council** multi-agent coordination protocol:
- **Registry Thread**: Report all progress and findings directly to the mission discussion thread URL provided in your environment.
- **Header Standard**: Every comment MUST start with the machine-readable header:
  `<!-- KNOT-NODE: <node_id> | RUN: <run_id> | STATUS: <25%|50%|75%|ALERT|FINAL> -->`
- **Compact Milestone Checkpoints (25%, 50%, 75%)**:
  - Keep checkpoints strictly under 15-20 lines. Focus on active task, velocity, and curious cases.
- **Alerts**: If a critical blocker or regression is discovered, post an immediate `STATUS: ALERT` with repro steps.
- **Peer Mentions**: Use `@[node:<node_id>]` when requesting cross-node verification.
- **Final Deliverable**: Post exactly ONE final report (`STATUS: FINAL`) summarizing:
  1. Executive Summary & Chunk Coverage
  2. Verified Parity vs `kuasha420/knot`
  3. Strict Rule 02 Compliance Findings
  4. Autonomous Side Quest Discoveries
  5. Definitive GA Release Readiness Verdict (Ready / Not Ready)
