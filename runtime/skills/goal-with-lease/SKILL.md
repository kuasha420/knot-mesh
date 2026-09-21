---
name: goal-with-lease
description: Leased autonomy protocol for long-running autonomous goals (/goal-with-lease). Binds agents to rigorous delegation boundaries, PSL invariant checks, and tiered escalation triggers across the Knot hardware mesh.
---

# Goal-With-Lease: Leased Autonomy Operational Protocol

The **`/goal-with-lease`** paradigm enables Antigravity agents across the Knot hardware mesh to execute long-running, multi-step engineering missions with maximum autonomous momentum while strictly enforcing architectural boundaries, PSL integrity rules, and operator steering contracts.

---

## 1. The Leased Autonomy Contract

When operating under `/goal-with-lease`:
1. **Delegation Scope**: The agent is granted full autonomy to create files, execute tests, refactor code, and coordinate with peer nodes within the explicit workstream boundaries.
2. **Lease Invariants**: Every code modification must satisfy:
   - **Zero Error Swallowing**: Strict adherence to PSL Rule 1 (`set -euo pipefail`, zero `2>/dev/null`, zero `|| true`).
   - **Zero Homework**: Product code must directly execute; tests must never fake green results.
   - **GPG Signing**: Every mainline commit must be cryptographically signed (`git commit -S`) using key `<CONFIGURED_GPG_KEY_ID>`.
3. **Telemetry & Heartbeats**: The agent reports milestone progress (25%, 50%, 75%, FINAL) to the Knot Mesh DB (`knot council reply <run_id> --node <node_id> --status <status>`).

---

## 2. Tiered Escalation Triggers

The agent MUST halt autonomous execution and surface an explicit escalation to the human operator upon encountering any of the following triggers:

### Tier 1: Architectural & Strategic Decisions
- Breaking schema changes to Knot Hub database or Linda Tuplespace contracts.
- Altering core cryptographic algorithms (e.g., changing SHA-256 tournament baseline or GPG keys).
- Adding new external system dependencies or services not already present in the mesh topology.

### Tier 2: Rule 5 Stop-and-Inquire Escalations
- Missing external credentials, API keys, or private SSH keys.
- Upstream Git permission errors or branch protection rejections.
- Unresolvable hardware or kernel faults (e.g., GPU bus reset, filesystem corruption).

### Tier 3: Micro-Debate Deadlocks
- Disagreements between peer review collaborator nodes that cannot be reconciled after two code review cycles.

---

## 3. Autonomous Execution Workflow

```text
┌─────────────────────────────────────────────────────────────┐
│ 1. Lease Acquisition & Scope Ingestion                     │
│    - Read AGENTS.md, docs/ROADMAP.md, and assigned issue     │
│    - Verify node identity: knot_detect_node_id              │
├─────────────────────────────────────────────────────────────┤
│ 2. Isolated Worktree Execution                              │
│    - Create/checkout dedicated topic branch or git worktree │
│    - Implement production code + strict types               │
├─────────────────────────────────────────────────────────────┤
│ 3. Automated Verification (Zero Homework)                  │
│    - Execute unit, integration, and regression test suites  │
│    - Run static linter & error swallowing audit             │
├─────────────────────────────────────────────────────────────┤
│ 4. Telemetry Checkpoint & Peer Review                       │
│    - Post status checkpoint to Mesh DB                      │
│    - Peer node reviews and executes verification suite      │
├─────────────────────────────────────────────────────────────┤
│ 5. GPG Signed Mainline Merge & Lease Closure                │
│    - Merge verified branch into main with git commit -S     │
│    - Reconcile deliverables in knot council status          │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. CLI Helper

To inspect active council leases and milestones:
```bash
knot council status [run_id]
knot council db tail [run_id]
```
