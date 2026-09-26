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
| **#60** | **Multi-Tenant Local Profile Sandboxing**<br>• Headless multi-account sandboxing under `~/.config/knot/auth/`.<br>• Atomic symlink switching between profiles without intermediate read errors.<br>• Non-blocking Secret Service / KWallet lock probe.<br>• Zero network credential leakage invariant.<br>• Fleet-wide node targeting (`knot auth <node_id> <action>`, `--all`). | `desktop` (Lead)<br>`rog-ally` (Peer) | **COMPLETED** | Verified via `tests/test_knot_auth.sh` (11/11 tests passed). |
| **Fleet** | **100% Dual-Profile Fleet Rollout & Starter Quota Telemetry**<br>• Complete dual-account enrollment across all 4 strands (8 total profiles).<br>• Dynamic Antigravity Starter Quota detection and weekly-only telemetry.<br>• Elimination of cross-account quota timestamp merging bugs (BUG-022, BUG-023).<br>• Zero-token live visualizers (`knot quota live`, `knot council board`). | `desktop` (Lead)<br>`steamdeck` (Peer) | **COMPLETED** | Verified live across all 4 strands and `tests/test_live_viewers.py`. |
| **#62** | **Full E2E KDE Connect Fleet Audit & Wayland Clipboard Harmonization**<br>• Automated zero-interaction pairing via SSH/DBus (`knot kdeconnect pair [--all]`).<br>• KDE Plasma 6 Klipper DBus pipeline (`getClipboardContents`/`setClipboardContents`) with `wl-clipboard` fallback.<br>• Intentional CLI sharing & broadcast (`knot kdeconnect share`, `sync-clipboard`, `test-clipboard`).<br>• Zero-friction integration with `knot auth login` & `knot-installer invite`/`join`.<br>• 100% full-mesh pairing & large payload (>21KB) verification across 4 nodes. | `desktop` (Lead)<br>`laptop` (Peer) | **COMPLETED** | Verified via `tests/test_kdeconnect_qa.sh` (10/10), `test_kdeconnect_autologin.sh` (11/11), and live fleet audit. |
| **#63** | **Wayland Virtual Monitor Fabric (D2D Phase 2)**<br>• Native Wayland headless virtual display creation via KWin + `krdpserver` (`krdp`).<br>• Low-latency RDP display streaming to remote strands via KRDC (`krdc` + `freerdp`).<br>• Ephemeral DBus signaling and credential exchange via KDE Connect `virtualmonitor` plugin.<br>• Subnet-scoped firewall rules (`knot-vmon` ports 5900-5910/tcp).<br>• Fleet-wide package distribution and `knot doctor` / `knot repair` self-healing.<br>• Turnkey CLI control (`knot kdeconnect vmon <status\|start\|stop>`, `knot display extend`). | `desktop` (Lead)<br>`rog-ally` (Peer) | **COMPLETED** | Verified via `tests/test_virtual_monitor.sh` (10/10), doctor diagnostics, and live 4-node fleet audit. |

---

## 3. Horizon 2 (Intermediate: Medium Resolution) — Platform Maturation & Contracts

* **[Epic #61: Handheld Ambient HUDs & Cockpit Workflow Consolidation](https://github.com/kuasha420/knot-mesh/issues/61)**:
  - Transition from working proof-of-concept to frictionless daily reality for multi-display ambient development.
  - Repurpose Kitty Remote Control as the dedicated interactive A2A direct steering protocol (`knot council steer`) in Confluence mode, workflow packs, `--interactive` sessions, and newly planned Hub integration.
  - Push-button fleet launch (`knot hud up / down / status`) and ambient systemd user supervision (`knot-hud@.service`).

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
