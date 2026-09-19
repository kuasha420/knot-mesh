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
Every reply posted by any node MUST begin with a machine-parseable HTML comment header:
```markdown
<!-- KNOT-NODE: <node_id> | RUN: <run_id> | STATUS: <25%|50%|75%|ALERT|FINAL> -->
```

### B. Unmistakable Node Callouts
When addressing a specific peer node in a comment, use the unambiguous mention syntax:
```markdown
@[node:<target_node_id>]
```
Nodes only parse and respond to comments explicitly containing their own node markup or general broadcast alerts.

### C. Checkpoint Cadence
Each node posts exactly:
1. **Milestone Checkpoints**: At 25%, 50%, and 75% of its self-assessed mission progress.
2. **Verified Alerts**: Immediately upon discovering and confirming a critical defect or regression.
3. **Cross-Node Queries**: When an architectural clarification from another node is required.
4. **Final Verdict**: Exactly ONE final completion reply summarizing all verified findings, edge cases, and a release readiness verdict.

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
