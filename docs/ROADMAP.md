# Knot Mesh Living Roadmap (Resolution Gradient)

> **Governing Standard**: PSL Monorepo Engineering Guidelines (`purrfectsoft/sunshine-physio-webapp`)  
> **Topology**: 4-Node Physical Mesh (`desktop`, `laptop`, `rog-ally`, `steamdeck`)  
> **Current Version**: v1.0.0 GA Target  

---

## 1. The Resolution Gradient Paradigm

The roadmap is structured across three distinct horizons of fidelity:
* **Horizon 1 (Immediate: High Resolution)**: Discrete deliverables, rigorous type definitions, executable test suites, zero ambiguity, independent node-level verification.
* **Horizon 2 (Intermediate: Medium Resolution)**: Architectural enablers, macro milestones, domain boundaries without premature micro-specification.
* **Horizon 3 (Far Horizon: Low Resolution)**: Strategic capabilities, cross-ecosystem connectors, long-term research.

---

## 2. Horizon 1 (Immediate: High Resolution) — Pre-Release Hardening & Issue Elimination

| Issue | Workstream / Deliverable | Assignee Node | Status | Acceptance Verification |
| :--- | :--- | :--- | :---: | :--- |
| **#54** | **Node ID vs Hostname Semantics**<br>• Standardize canonical `node_id` across manifests, Hub DB, CLI.<br>• Dynamic user home resolution (`psl`, `jimha`, `kuasha`).<br>• Preserved `KNOT_NODE_ID` in all remote subshells. | `desktop` (Lead)<br>`rog-ally` (Peer) | **In Progress** | `knot status`, `knot quota`, `knot exec` across all 4 nodes without error. Dedicated `tests/test_node_id_semantics.sh`. |
| **#43** | **Swarm Project Management & Worktrees**<br>• Cockpit project creation modal contract (`project_created` SSE).<br>• Automated `git worktree add` provisioning across mesh nodes.<br>• Cross-node spec sync with home path translation.<br>• LHAA SQLite WAL per-conversation logging. | `desktop` (Lead)<br>`rog-ally` (Peer) | **In Progress** | Isolated worktree creation across 3 nodes; concurrent agent execution test. |
| **#41** | **Decentralized Memory Palace & MCP Gateway**<br>• Local embedded SQLite with `cr-sqlite` CRDT schema.<br>• In-process `sqlite-vec` semantic indexing.<br>• Dual-pool memory architecture (node scratch vs swarm shared).<br>• Hardware node-role system prompt profiles. | `laptop` (Lead)<br>`desktop` (Peer) | **In Progress** | Offline vector recall test, CRDT delta merge validation, MCP gateway tool execution. |
| **#42** | **Knot Kommand Kafe (Tauri v2 & Handheld Mode)**<br>• `src-tauri/` container shell (<50MB RAM footprint).<br>• Blackboard Kanban task board with token telemetry.<br>• Gamepad navigation & 7" 1280x800 responsive layout. | `steamdeck` (Lead)<br>`desktop` (Peer) | **In Progress** | Tauri cargo check / build verification, UI test on Steam Deck Wayland session. |
| **#55** | **Swarm Council Harness Hardening**<br>• `knot council steer --wait-ack` handshake.<br>• `knot council challenge generate / verify` CLI.<br>• Mesh context subshell exports (`KNOT_HUB_URL`, `KNOT_NODE_ID`).<br>• `knot council db inspect / tail` subcommands. | `desktop` (Lead)<br>`laptop` (Peer) | **In Progress** | 100% automated test in `tests/test_swarm_council.sh`. |

---

## 3. Horizon 2 (Intermediate: Medium Resolution) — Platform Maturation & Contracts

* **PSL Rule 1 Compliance (Zero Error Swallowing)**:
  - System-wide purge of `2>/dev/null`, `|| true`, `|| :`, and blind redirects in `bin/` and `core/`.
  - Enforced `set -euo pipefail` across all script entry points.
* **Packaging & Distribution**:
  - Clean Arch Linux `PKGBUILD` packaging without hardcoded machine paths.
  - Portable single-command installer (`install.sh`) supporting immutable SteamOS.
  - Systemd user service unit definitions with auto-restart and socket activation.
* **Antigravity `/goal-with-lease` Engine**:
  - Leased autonomous goal execution loop with milestone boundary triggers and auto-reconciliation.

---

## 4. Horizon 3 (Far Horizon: Low Resolution) — Ecosystem & Grand Rematch

* **The Grand Rematch (Issue #55)**:
  - 4-node, 10-round (40 volleys) autonomous cryptographic tournament with dynamic difficulty scaling.
  - Full leaderboard telemetry published to Mesh DB and Git.
* **Decentralized Federated Agent Mesh**:
  - Zero-anchor P2P gossip protocol for dynamic anchor elections when `desktop` roams or disconnects.
  - Hardware-accelerated local SLM fine-tuning across heterogeneous mesh GPUs.
