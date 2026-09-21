---
name: swarm-council
description: Out-of-band multi-agent coordination protocol using GitHub Discussions, spatial GPU-accelerated terminal multiplexing (Confluence mode in Kitty), and dynamic mode selection. Use whenever coordinating distributed audits, verification sweeps, or parallel multi-node missions across the Knot mesh without relying on Linda Tuplespace or when service/network instability is expected.
---

# Swarm Council: Distributed Multi-Agent Coordination Skill

The **Swarm Council** skill formalizes a resilient, out-of-band coordination framework for the Knot mesh. It enables autonomous Antigravity agents across physical nodes to collaborate on shared missions via GitHub Discussions, bypassing built-in Linda Tuplespace or daemon RPC when network reassignments, service restarts, or deep system audits take place.

---

## 1. Core Architecture & Execution Modes

Swarm Council supports 5 execution modes:

| Mode | Invocation | Execution Surface | Best For |
| :--- | :--- | :--- | :--- |
| **`--confluence`** *(Default)* | `knot council start --mode confluence` | Fullscreen GPU-accelerated **Kitty** on anchor with native spatial splits matching `~/.config/knot/swarms/home/topology.json` | High-visibility multi-agent audits, interactive monitoring, instant human takeover |
| **`--headless`** | `knot council start --mode headless` | Headless background execution via `systemd-run --user` with `--dangerously-skip-permissions` | Unattended overnight batch runs, cron maintenance, CI/CD verification sweeps |
| **`--tui`** | `knot council start --mode tui` | Dedicated **Konsole** windows spawned on each target node's local Wayland screen | Device-specific hardware ergonomics, local display scaling, battery profiling |
| **`--gui`** | `knot council start --mode gui` | Staged prompt delivery with local-only `knot council copy` helper | Visual web UI/CSS design, Generative UI, interactive plan review |
| **`--suggested`** | `knot council start --mode suggested` | **Dual Ensemble Classifier** (deterministic rubric + fast local AI inference) | Automatic mode selection based on task prompt with 5-second countdown override |

---

## 2. GitHub Discussion Communication Norms

To prevent token waste and eliminate race conditions across shared GitHub credentials:

### A. Identity & Status Markup Header
Every reply posted by any node MUST begin with a machine-parseable HTML comment header, immediately followed by explicit visual self-identification:
```markdown
<!-- KNOT-NODE: <node_id> | RUN: <run_id> | STATUS: <25%|50%|75%|ALERT|FINAL> -->
### 🛰️ `@{node_id}` — <Node Role / Hardware Specialization>
**Assigned Focus**: `<Assigned Chunks or Exploration Target>`
```

### B. Unmistakable Node Callouts
When addressing a specific peer node in a comment, use the unambiguous mention syntax:
```markdown
@[node:<target_node_id>]
```
Nodes only parse and respond to comments explicitly containing their own node markup or general broadcast alerts.

### C. Checkpoint Cadence & Compact Pulse Updates
Each node posts:
1. **Milestone Checkpoints (25%, 50%, 75%)**:
   - **MANDATORY CONCISENESS RULE**: Keep updates strictly under 15-20 lines.
   - **DO NOT** write full discovery reports, large tables, or exhaustive code analysis in checkpoint updates.
   - **REQUIRED FOCUS**:
     - **Liveness & Status**: What the agent is actively executing or inspecting right now.
     - **Progress & ETA**: Estimated percentage completed and remaining time.
     - **Curious Cases & Red Flags**: Anomalies, odd behaviors, or potential breaking regressions that peer nodes should be aware of immediately.
2. **Verified Alerts**: Immediately upon discovering and confirming a critical defect or regression (`STATUS: ALERT`).
3. **Cross-Node Queries**: When an architectural clarification from another node is required.
4. **Final Verdict**: Exactly ONE final completion reply (`STATUS: FINAL`) summarizing all verified findings, edge cases, full tables, and a release readiness verdict.

### D. Token-Efficient Delta Querying
Agents must NOT fetch the entire discussion thread on every poll. The helper script `scripts/gh_discussion.py poll_delta` queries comment counts and only retrieves new comments added after the last known timestamp.

---

## 3. Stages 0 through 7 Workflow

```text
┌────────────────────────────────────────────────────────────────────────┐
│ STAGE 0: Tool & Fleet Availability Audit (audit_tools.sh)              │
│   ├── Verifies gh, git, knot, agy, and model quotas across online nodes│
│   └── Checks repo write permissions and dynamically enables Discussions│
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 1: Dynamic Project & Source Sync (project_sync.sh)               │
│   ├── Discovers current Antigravity project and registered folder URIs │
│   └── Verifies git tree parity across mesh (remote -> mesh -> rsync)   │
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 2: Discussion Initialization (gh_discussion.py)                  │
│   └── Creates thread in 'General' category with run metadata & goals   │
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 3: Prompt Scaffolding (scaffolder.py)                            │
│   ├── Breaks codebase into chunks achieving 1.5x agent coverage        │
│   ├── Injects hardware domain roles (Anchor, Handheld, Roaming, CUDA)  │
│   └── Allocates 30% capacity for autonomous side quests                │
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 4: Execution Mode Selection (classifier.py)                      │
│   └── Runs dual ensemble scorer if --suggested is chosen               │
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 5: Deliverance (deliver.sh & confluence.py)                      │
│   ├── Spawns spatial Kitty cockpit (--confluence)                      │
│   ├── Dispatches systemd-run headless runners (--headless)             │
│   └── Stages isolated prompt files with anti-echo protection (--gui)   │
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 6: Live Monitoring & Human Intervention (council.sh)             │
│   ├── Track milestone progress via `knot council status`               │
│   └── Live attach to any running node session via `knot council attach`│
├────────────────────────────────────────────────────────────────────────┤
│ STAGE 7: Reconciliation & Synthesis (reconcile.py)                     │
│   └── Compiles final discussion deliverables into consolidated report  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Session Attachment & SIGHUP Protection

Every `agy` runner persists its session state into local SQLite (`~/.gemini/antigravity-cli/conversations/<id>.db`). 
- If an SSH connection drops during Confluence mode, the session remains running under SIGHUP immunity (`trap '' HUP`).
- The operator can re-attach to that node's live interactive session at any time:
  ```bash
  knot council attach <node_id> [run_id]
  ```

---

## 5. Mesh Database Registry (`--db mesh`)

To support offline swarms, fast developer iteration, or hermetic testing without polluting GitHub Discussions:
- Pass `--db mesh` to `knot council start`.
- Registry threads and milestone updates are stored in the Mesh DB (backed by Knot Hub TLS REST API `:4242` across physical strands, with automatic fallback to local SQLite at `~/.config/knot/council.db`).
- Checkpoints and deliverables are posted directly via the CLI:
  ```bash
  knot council reply <run_id> --node <node_id> --status <25%|50%|75%|ALERT|FINAL> --body "<message>"
  # Or pipe complete markdown deliverables:
  knot council reply <run_id> --node <node_id> --status FINAL < deliverable.md
  ```

---

## 6. Zero-Token Interactive Cockpit, Hooks & Tiling Engine

### A. Zero-Token Interactive Cockpit (`--interactive`)
To launch a live cockpit across all swarm nodes with zero startup token overhead:
```bash
knot council start --interactive [--tiling <layout>] [--project <name>]
```
- **Zero Startup Tokens**: Drops directly into the `agy` interactive TUI in standby mode across every active node. No prompts are dispatched at launch, consuming **0 tokens** and **0 LLM calls**.
- **Human Steering Model**: The human operator prompts high-level directives and steers execution. The agents coordinate autonomously among themselves across the mesh.

### B. Antigravity Lifecycle Hook (`council_hook.py`)
Context is injected lazily and on-demand using Antigravity's `PreInvocation` lifecycle hook:
1. **Turn-1 Gating (`invocationNum == 1`)**: When the operator submits their first prompt to any node, the hook detects `KNOT_COUNCIL_RUN_ID` and dynamically injects an `ephemeralMessage` containing node identity, peer roster, and CLI coordination commands.
2. **Subsequent Turns (`invocationNum > 1`)**: The hook emits `{"injectSteps": []}`. Because the model already retains the council context in its conversation history, no extra tokens are spent on repetitive injections.
3. **Strict Arena Isolation**: Outside council missions (`$KNOT_COUNCIL_RUN_ID` is unset), the hook exits in `< 2ms` returning `{"injectSteps": []}` with zero impact on normal development.

### C. Cockpit Resumption (`knot council resume`)
To restore an interactive council cockpit across the entire fleet:
```bash
knot council resume [run_id]
```
Re-opens the Kitty Confluence cockpit with the original tiling layout, enters the project directory on all nodes, and connects to previous conversations via `agy -c` with zero prompt overhead.

### D. Cockpit Tiling Layouts (`--tiling <layout>`)
Customize the Kitty window topology for both autonomous and interactive sessions:
- `grid` *(default)*: Balanced NxM matrix (ideal for ultrawide displays)
- `sidebyside` / `horizontal`: Full-height side-by-side vertical columns
- `splits`: Flexible BSP-style splits
- `tall`: Primary master pane on the left, auxiliary panes stacked on the right
- `fat`: Primary master pane on top, auxiliary panes side-by-side on bottom
- `stacked` / `vertical`: Full-width stacked rows

---

## 7. Command Reference

```bash
# Autonomous Mission (with prompt scaffolding)
knot council start [--mode <mode>] [--db <ghd|mesh>] [--tiling <layout>] [--nodes <list>] [--prompt <text>]

# Zero-Token Interactive Cockpit (direct drop into agy TUI with on-demand steering)
knot council start --interactive [--tiling <layout>] [--nodes <list>] [--project <name>]

# Cockpit Resumption
knot council resume [run_id]                  # Re-attach all nodes via agy -c in Kitty

# Mission Lifecycle & Coordination
knot council status [run_id]                  # Inspect real-time status matrix & milestones
knot council reply <run_id> [options]         # Post status checkpoint or final report
knot council reconcile [run_id]               # Compile consolidated audit report
knot council list [interactive|active|mesh]   # List recent missions with status badges
knot council attach <node_id> [run_id]        # Attach directly to node's agy session
knot council copy                             # Load staged prompt into local clipboard
knot council kill <run_id>                    # Halt all mission processes across fleet
knot council clean [days]                     # Prune mission artifacts older than N days
```
