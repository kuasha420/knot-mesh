---
name: subagent-ladder
description: >-
  Strictly user-invoked SWE ladder protocol (/subagent-ladder). Coordinates multi-agent
  execution pipelines (Executioner -> Hammer -> Auditor) for multi-phase engineering tasks.
  Activate ONLY when explicitly commanded by the user (e.g., 'run subagent ladder',
  'use subagent flow', '/subagent-ladder', 'execute ladder'). Never auto-trigger autonomously.
---

# Subagent Ladder: Multi-Agent SWE Execution Protocol 🪜🤖

The **Subagent Ladder** formalizes an autonomous, multi-agent pair-programming protocol for complex software engineering tasks, large-scale refactorings, and multi-phase milestones across the Knot mesh.

> [!IMPORTANT]
> **Strictly User-Invoked Activation Contract**:
> Autonomous agents must **NEVER** activate or auto-trigger this skill autonomously. It is engaged **strictly upon explicit operator command** (e.g. `/subagent-ladder`, *"use subagent ladder"*, *"run the ladder flow"*). Single-turn or minor edits must use standard direct execution.

---

## 1. Architectural Rationale & Cognitive Benefits

Complex engineering initiatives easily cause **conversational context collapse** when executed in a single monolithic context window. Accumulated tool outputs, compile logs, and search results bloat context, degrade instruction following, and incur exponential token costs.

The Subagent Ladder partitions execution across specialized subagent roles:
1. **Zero Context Carryover**: Subagents operate in lean, task-focused contexts, preserving high reasoning capability and deterministic instruction following.
2. **Cognitive Role Isolation**: Separates the builder from the reviewer. An agent that writes code never reviews or audits its own diffs.
3. **Hermetic State Preservation**: High-level milestone state, plan artifacts, and empirical test logs are preserved in persistent markdown documents, resilient to conversational compaction or session resets.

---

## 2. The Phase Lifecycle Ladder

Every milestone progresses through a strict 5-stage pipeline:

```
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: PLANNING & OPERATOR LOCK-IN                                    │
│ - Coordinator drafts `phase_X_plan.md` & updates `implementation_plan.md`│
│ - Operator reviews, grills, refines, and formally locks in the plan.    │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │ (Approved)
                                     ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 2: EXECUTION (`subagent-X-executioner`)                           │◄────────────────────────┐
│ - Executes file creations, edits, code sanitizations, and commands.     │                         │
│ - Produces raw execution outputs, diffs, and self-checks.                │                         │
└────────────────────────────────────┬────────────────────────────────────┘                         │
                                     │ (Execution Complete OR Remedy Complete)                      │
                                     ▼                                                              │
┌─────────────────────────────────────────────────────────────────────────┐                         │
│ STAGE 3: CODE & PSL REVIEW (`subagent-X-hammer`)                        │                         │
│ - Ruthlessly audits all changes against the PSL Gold Standard:          │                         │
│   • Rule 1: Zero error swallowing (`2>/dev/null`, `|| true`, `|| :`).   │                         │
│   • Rule 2: Zero homework in tests (no cherry-picking, no mocks).       │                         │
│   • Rule 3: Complete package delivery (code + types + tests + docs).     │                         │
│   • Rule 4: Verifiable automated proofs.                                │                         │
│   • Rule 5: Stop and inquire (no synthetic workarounds).                │                         │
│ - Verdict: PASS or REJECT with specific line-by-line defect list.       │                         │
└──────────────────┬───────────────────────────────────▲──────────────────┘                         │
                   │ (Passed Hammer Review)            │                                            │
                   ▼                                   │ (Hammer Code Rejection)                    │
┌──────────────────────────────────────────────────┐   │                                            │
│ STAGE 4: QA & AUDIT (`subagent-X-auditor`)       │   │                                            │
│ - Executes automated test suites in shell/python.│   │                                            │
│ - Probes remote nodes via SSH.                   │   │                                            │
│ - Verifies environment state and exit codes.     │   │                                            │
│ - Verdict: PASS or FAIL with raw diagnostics.    │   │                                            │
└──────────────────┬───────────────────────────────┘   │                                            │
                   │                                   │                                            │
         ┌─────────┴─────────┐                         │                                            │
         │ (Passed QA Audit) │ (QA/Audit Failed)       └────────────────────────────────────────────┤
         │                   └──────────────────────────────────────────────────────────────────────┘
         ▼                                                     (MANDATORY: Return to Executioner,
┌─────────────────────────────────────────────────────────────────────────┐   THEN through Hammer!)
│ STAGE 5: PHASE ARCHIVAL & PROMOTION                                     │
│ - Coordinator archives `phase_X_plan.md` -> `phase_X_delivery_final.md`. │
│ - Coordinator records Phase X completion in `master_plan.md`.           │
│ - Phase X subagents are formally retired.                               │
│ - Coordinator presents Phase X+1 Detailed Implementation Plan to user.  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Strict State Machine Invariants

### 3.1 Anti-Bypass Invariant (Zero Shortcuts)
> [!CAUTION]
> If `subagent-X-auditor` detects a failure and `subagent-X-executioner` produces a patch:
> $$\text{Auditor FAIL} \longrightarrow \text{Executioner (Remedy)} \longrightarrow \mathbf{Hammer\ (Mandatory\ Re\text{-}Review)} \longrightarrow \text{Auditor (QA)}$$
> **Under NO circumstances may an Executioner remedy bypass Hammer review.** An executioner fixing an edge case under test failure pressure is prone to introducing error-swallowing constructs (`2>/dev/null`) or artificial mocks.

### 3.2 Zero Coordinator Remediation Invariant
> [!CRITICAL]
> The Coordinator is **strictly forbidden from modifying product code, patching files directly, or self-resolving review defects**.
> - The Coordinator orchestrates the ladder, manages persistent artifacts, and routes diagnostics.
> - Defect reports must be routed back to the designated `subagent-X-executioner`.

---

## 4. Subagent Roles & Responsibilities

| Role | Name Pattern | Mandate | Permitted Tools |
| :--- | :--- | :--- | :--- |
| **Builder** | `subagent-X-executioner` | Implements exact tasks from approved phase plan. Strictly enforces `set -euo pipefail`. Zero scope creep. Delivers exact diffs and outputs. | Read & write tools, bash commands (`view_file`, `write_to_file`, `replace_file_content`, `run_command`). |
| **Reviewer** | `subagent-X-hammer` | Assumes shortcuts were taken until proven otherwise. Ruthlessly scans modified files for forbidden patterns, missing type safety, or mock cheating. Issues formal PASS/REJECT report. | Read-only inspection tools (`view_file`, `grep_search`, `list_dir`). **No write or execution tools.** |
| **Verifier** | `subagent-X-auditor` | Runs automated test suites, probes remote nodes via SSH, checks process states and exit codes, conducts leak detection. Issues formal PASS/FAIL report. | Read tools, test runner commands (`view_file`, `grep_search`, `run_command`). **No file modification tools.** |

---

## 5. Workspace Artifact Bridge (`.agents/artifacts/`)

To prevent subagents from wasting context and tool calls hunting for plan artifacts:

### 5.1 The Standard
1. **Bridge Symlink**: `.agents/artifacts` in the workspace root points to the active Coordinator brain directory:
   ```bash
   python3 runtime/skills/subagent-ladder/scripts/bridge_artifacts.py --setup "<brain_dir>"
   ```
2. **Git Hygiene**: `.agents/artifacts` is ignored in `.gitignore`.
3. **Prompt Standard**: Coordinator prompts strictly reference `.agents/artifacts/<plan_name>.md`.
4. **Tool Compatibility**: `view_file` resolves the symlink natively on Step 2 (the first tool call) with zero search pollution.

### 5.2 Forbidden Prompt Anti-Patterns
- ❌ **Bare filenames**: `Read phase_2_plan.md` (subagent wastes turns grepping the workspace).
- ❌ **`file://` URIs**: `view_file("file:///home/...")` (causes `invalid tool call error: path is not absolute`).
- ❌ **Raw machine paths**: `Read /home/username/.gemini/...` (leaks usernames, host paths, and session UUIDs into prompt history, violating OSS confidentiality).

---

## 6. Remote Fleet Probing Safeguards

When testing distributed multi-node mesh topologies:
1. **Mandatory Execution Ceilings**: All remote SSH checks must enforce hard timeouts and TCP keepalives:
   ```bash
   timeout 10 ssh -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 <node> "<command>"
   ```
2. **Headless Execution Only**: Never invoke interactive graphical binaries (e.g. Electron GUI `/usr/bin/antigravity`) headlessly over SSH; probe daemon sockets, CLI endpoints, or D-Bus services.

---

## 7. Model Selection Hierarchy

* **Gemini 3.8 Flash (`flash`)**: The standard workhorse model for `Executioner`, `Hammer`, and `Auditor`. Delivers modern knowledge, sub-minute step latencies, sharp instruction following, and high concurrency.
* **Gemini 3.1 Pro (`pro`)**: Reserved exclusively for high-ambiguity architectural design or complex formal proofs. Avoid for standard ladder execution.

---

## 8. CLI Helpers & Tooling

The skill bundles dedicated CLI helpers in `scripts/`:

```bash
# 1. Setup or inspect the workspace artifact bridge
python3 runtime/skills/subagent-ladder/scripts/bridge_artifacts.py --setup <brain_dir>
python3 runtime/skills/subagent-ladder/scripts/bridge_artifacts.py --check

# 2. Scaffold subagent invocation payloads
python3 runtime/skills/subagent-ladder/scripts/scaffold_ladder.py --phase 1 --role executioner --plan .agents/artifacts/phase_1_plan.md

# 3. Verify session state machine adherence (audit transcript for Hammer bypasses)
python3 runtime/skills/subagent-ladder/scripts/verify_ladder_state.py --log <transcript.jsonl>
```
