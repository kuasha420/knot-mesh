# Knot Mesh Living Roadmap (Resolution Gradient)

> **Governing Standard**: PSL Gold Standard Engineering Guidelines ([AGENTS.md](../AGENTS.md))  
> **Topology**: 4-Node Physical Mesh (`desktop`, `laptop`, `rog-ally`, `steamdeck`)  
> **Current Version**: v1.0.0-rc5  

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
| **#54** | **Node ID vs Hostname Semantics**<br>• Standardized canonical `node_id` across manifests, Hub DB, CLI.<br>• Dynamic user home resolution across multi-user environments.<br>• Preserved `KNOT_NODE_ID` in all remote subshells. | `desktop` (Lead)<br>`rog-ally` (Peer) | **COMPLETED** | Verified across all nodes via `tests/test_node_id_semantics.sh`. Zero exit-code masking. |
| **#43** | **Swarm Project Management & Worktrees**<br>• Cockpit project creation modal contract (`project_created` SSE).<br>• Automated `git worktree add` provisioning across mesh nodes.<br>• Cross-node spec sync with home path translation.<br>• LHAA SQLite WAL per-conversation logging. | `desktop` (Lead)<br>`rog-ally` (Peer) | **COMPLETED** | Verified via `tests/test_swarm_sync.sh` and worktree isolation suites. |
| **#41** | **Decentralized Memory Palace & Lean MCP Gateway**<br>• Local embedded SQLite with CRDT Hybrid Logical Clock schema.<br>• In-process vector cosine similarity indexing.<br>• Dual-pool memory architecture (node scratch vs swarm shared).<br>• Pruned MCP gateway to 4 canonical mesh tools (`knot_node_status`, `knot_quota_matrix`, `knot_exec_command`, `knot_swarm_topology`).<br>• Hardware node-role system prompt profiles. | `laptop` (Lead)<br>`desktop` (Peer) | **COMPLETED** | Verified via `tests/test_memory_palace.py` (20/20 tests passed). |
| **#55** | **Swarm Council Harness Hardening**<br>• `knot council steer` remote socket injection.<br>• Out-of-band collaboration via GitHub Discussions and Mesh DB.<br>• Scale-aware Kitty Confluence cockpit with zero-token start (<1s).<br>• Antigravity `PreInvocation` hook (`council_hook.py`) with Turn 1 scoping. | `desktop` (Lead)<br>`laptop` (Peer) | **COMPLETED** | Verified via `tests/test_swarm_council.sh` and `test_council_steer.sh`. |
| **PSL** | **PSL Rule 1 & Rule 2 Enforcement**<br>• Zero error swallowing across production code and test suites.<br>• Purged all `2>/dev/null`, `&>/dev/null`, `|| true`, and `|| :`.<br>• Universal PSL integrity suite with 5 automated audits. | `desktop` (Lead)<br>`laptop` (Peer) | **COMPLETED** | Verified via `tests/test_psl_integrity.sh` (0 defects found). |

---

## 3. Horizon 2 (Intermediate: Medium Resolution) — Platform Maturation & Contracts

* **Knot Kommand Kafe (Tauri v2 / Handheld GUI)**:
  - Rust Tauri v2 desktop shell with ultra-low memory footprint (<50MB RAM).
  - Responsive gamepad-friendly and touch-optimized 7" 1280x800 layout for Steam Deck and ROG Ally.
  - Interactive Blackboard Kanban board, live model quota telemetry, and real-time SSE event streaming.
  - Native integration with Wayland LayerShell and KDE Plasma 6 desktop notifications.

* **Dynamic Multi-Monitor Wayland Layout Handling**:
  - Abstract display geometry management away from node-specific hardware quirks into a dynamic, capability-based Wayland layout engine.
  - Sub-pixel boundary alignment and auto-scaling across mixed DPI monitors (e.g. handheld eDP-1 internal displays with external high-refresh monitors).
  - Computer vision photo-based layout inference refinement (`knot topology refresh --photo`).

* **Autonomous Execution with `/goal-with-lease` Engine**:
  - Standardized runtime skill (`runtime/skills/goal-with-lease/`) for autonomous multi-agent task execution.
  - Linda tuplespace artifact locking (`DRAFTING`, `LOCKED_SURGERY`, `VERIFIED_COMMITTED`).
  - Distributed heartbeat renewal, lease timeouts, and orphan task auto-recovery without deadlock.

* **Packaging, Distribution & Automated Verification**:
  - Upstream-ready Arch Linux `PKGBUILD` packaging without hardcoded paths.
  - Portable curl-pipe installer (`install.sh`) supporting Arch Linux, EndeavourOS, and SteamOS.
  - Full CI test harness with automated nightly multi-node regression matrix.

---

## 4. Horizon 3 (Far Horizon: Low Resolution) — Ecosystem & Grand Rematch

* **P2P Dynamic Anchor Elections & Consensus**:
  - Zero-anchor P2P gossip protocol and Raft consensus for dynamic anchor elections when primary desktop disconnects or roams.
  - Distributed split-brain prevention and quorum-fenced state reconciliation.

* **Cross-Ecosystem Connectors & Multi-Platform Clients**:
  - Universal MCP bridges to external multi-agent ecosystems (Claude Desktop, OpenHands, AutoGen).
  - Handheld and mobile companion extensions utilizing KDE Connect secure transport.
  - Heterogeneous GPU compute sharing for local quantized SLM inference.

* **The Grand Rematch**:
  - 4-node autonomous cryptographic council tournament with dynamic difficulty scaling.
  - Full leaderboard telemetry published to Mesh DB and decentralized memory palace.
