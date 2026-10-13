# AGENTS.md — Knot Mesh Engineering Governance & Operational Protocol

Welcome to **Knot Mesh** (`kuasha420/knot-mesh`). All autonomous agents, subagents, and human contributors operating within this repository are bound by the governance standards, architectural gradients, verification rules, and engineering protocol defined in this document.

---

## 1. Core Engineering Philosophy: PSL Gold Standard

This repository strictly adheres to the PSL Gold Standard of engineering integrity:

### 1.1 The 5 Ground Rules of Engineering Integrity

1. **Rule 1: Zero Error Swallowing & Strict Failure Transparency**
   * Absolute ban on `2>/dev/null`, `&>/dev/null`, `> /dev/null 2>&1`, and `|| true` / `|| :` in bash scripts, tooling, and test runners.
   * Absolute ban on empty `catch (e) {}` blocks, `// @ts-ignore`, `// @ts-nocheck`, or careless `any` in TypeScript, as well as bare `except Exception: pass` in Python.
   * All shell scripts must enforce `set -euo pipefail`. Stderr and non-zero exit codes must remain transparently logged and resolved.
   * Probing commands must use clean, explicit branching and status inspections instead of blanket error suppression.

2. **Rule 2: Do Not Do the Product's Homework in Tests**
   * Never manufacture false green test passes by duplicating logic, synthetic mocks, or artificial bypasses inside test files.
   * Tests must directly import, execute, and validate exported product code and live CLI executables.

3. **Rule 3: Complete Package Deliveries**
   * Every delivery is incomplete unless it contains: **Production Code + Strict Types / Shell Hygiene + Comprehensive Automated Tests + Packaging Definitions + Up-to-Date Documentation**.

4. **Rule 4: Zero "Homework" in Verification**
   * Every claim must be backed by verifiable, automated proof (`pytest`, bash test suites, CLI exit code inspections, syntax verification).
   * If any flakiness, unexpected exit code, or ambiguity arises, **STOP immediately** and report the raw diagnostic or challenge the premise.

5. **Rule 5: Stop and Inquire Before Overengineering Workarounds**
   * When external dependencies, credentials, or environment prerequisites fail, never invent synthetic wrappers, fallback bypasses, or proxy hacks.
   * Stop, surface the exact raw diagnostic, and prompt the operator for decision or intervention.

---

## 2. Multi-Agent SWE Execution Protocol

For complex multi-phase engineering milestones, contributors and operators invoke the **`subagent-ladder`** operational skill ([`runtime/skills/subagent-ladder/SKILL.md`](runtime/skills/subagent-ladder/SKILL.md)).

> [!IMPORTANT]
> **User-Invoked Only**: Autonomous agents must **NEVER** auto-trigger or assume the multi-agent ladder pipeline on their own. The ladder workflow is strictly engaged upon explicit operator direction (e.g., `/subagent-ladder`, *"use subagent ladder"*). Single-turn queries and targeted bug fixes must be handled directly.

---

## 3. Pull Request Standards & Issue Conventions

### 3.1 Branching Strategy
- Feature branches: `feat/<component>-<description>`
- Bug fixes: `fix/<component>-<description>`
- Refactors: `refactor/<module>-<description>`
- Documentation: `docs/<topic>`

### 3.2 Commit Message Standards
All commits must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
- `feat(<scope>): <concise description>`
- `fix(<scope>): <concise description>`
- `refactor(<scope>): <concise description>`
- `test(<scope>): <concise description>`
- `docs(<scope>): <concise description>`
- `chore(<scope>): <concise description>`

Every commit must be atomic, focused on a single change, and accompanied by automated tests verifying the change.

### 3.3 Pull Request Criteria
1. **Title & Summary**: Clear summary detailing changes, rationale, and issue references.
2. **Automated Verification Proof**: Raw output from test suites (`tests/test_*.sh`, `pytest`) confirming zero regressions.
3. **No Suppressed Failures**: Codebase passes `bash -n`, `py_compile`, and linter checks without warning suppression.
4. **Cryptographic Signing**: All commits must be GPG signed by the contributor.

---

## 4. The Resolution Gradient Architecture

All features, refactors, and issue resolutions follow the **Resolution Gradient**:

* **Horizon 1 (Immediate: High Resolution)**: Concrete deliverables, strict type contracts, executable test suites, zero ambiguity, independent node-level verification.
* **Horizon 2 (Intermediate: Medium Resolution)**: Architectural enablers, macro milestones, domain boundaries without premature micro-specification.
* **Horizon 3 (Far Horizon: Low Resolution)**: Strategic capabilities, cross-ecosystem connectors, long-term protocol evolutions.

---

## 5. Anti-Drama & Signal-to-Noise Policy

* **Zero ACK Spam**: Do not post acknowledgments, polite chitchat, or performative narration ("Understood!", "Working on this now!").
* **Code-First Challenges**: If a design or implementation cannot be substantiated with working code and test passes, peer nodes or the coordinator must challenge it immediately.
* **Operator Steering**: Any node can stop execution and await operator steering or intervention when human alignment is necessary.

---

## 6. OSS Boundary & Confidentiality Hygiene

* **Public Git Tree**: Clean, reproducible, and generic. Zero private IPs, personal usernames, local absolute paths, or machine-specific hardware assumptions.
* **Hardware & Topology Independence**: Device hostnames and roles are dynamic runtime constructs configured via manifests (`~/.config/knot/swarms/<swarm_id>/nodes/`), not hardcoded repository invariants.
* **Internal / Node-Local Artifacts**: Private setup notes, local scratch scripts, and raw diagnostic transcripts must remain in local ephemeral scratch directories and never be committed to git.

---

## 7. Leased Autonomy Contract (`/goal-with-lease`)

* Operate with maximum autonomous momentum within a leased delegation scope bounded by workstream, milestone, and invariant checks.
* **Intervention Triggers**:
  1. *Tier 1: Architectural & Strategic Decisions* — High-level paradigm choices, breaking schema/API contracts, or new dependency additions.
  2. *Tier 2: Rule 5 Stop-and-Inquire Escalations* — Missing credentials, upstream repo permission blocks, or unresolvable hardware/environment faults.
  3. *Tier 3: Micro-Debate Deadlocks* — Unresolvable code review disagreements between collaborator nodes after two peer exchanges.

---

## 8. Contributor GPG Commit Signing Setup

Every git commit to `main` or release branches MUST be cryptographically signed by the contributor's verified GPG key.

### 8.1 Setup Instructions

1. **Generate a GPG Key** (if you don't already have one):
   ```bash
   gpg --full-generate-key
   ```
   Select `RSA and RSA` (default), keysize `4096`, and set a reasonable expiry.

2. **Retrieve Your Key ID**:
   ```bash
   gpg --list-secret-keys --keyid-format=long
   ```
   Copy the sec line's key ID (e.g., `3AA5C34371567BD2` from `sec rsa4096/3AA5C34371567BD2`).

3. **Configure Git**:
   ```bash
   git config --global user.signingkey <YOUR_KEY_ID>
   git config --global commit.gpgsign true
   ```

4. **Export Public Key to Git Hosting Platform**:
   ```bash
   gpg --armor --export <YOUR_KEY_ID>
   ```
   Paste the exported public key block into your GitHub / GitLab account under GPG Keys.

5. **Commit with Signature**:
   ```bash
   git commit -S -m "feat(module): add verified feature"
   ```

<!-- Added by AGYIS-HARNESS -->
<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright (c) 2026 Arafat Zahan (@kuasha420) -->
<!-- Corporate Stewardship & Infrastructure: Purrfect Software Limited (PSL) -->
<!-- Governed by: ICARO-42/b Ordinance (Company-Supported Personal IP Framework) -->

# Universal Empirical Agent Rules: Agyis Harness Guidelines

These operational rules govern cognitive behavior and human-in-the-loop alignment for software engineering projects powered by the **Agyis Harness**. All deterministic environment guarantees (runtime injection, pager normalization, surgical grep exit sanitization, output compaction) are enforced transparently by harness hooks.

---

## 1. Explicit Project Command Dictionary (The Victory Pattern)
*Explicit CLI palettes yield 10x lower human intervention rates:*

```bash
# 🩺 Environment Diagnostics & Auto-Healing
agyis doctor                                   # Audit workstation runtimes & auto-heal
agyis status                                   # Print harness health, active hooks & telemetry

# 🧩 Skills & Subagents Discovery
agyis skills                                   # List installed modular skills & triggers
agyis agents                                   # List registered specialist subagents & tools

# 🌐 Remote Operations & Cloud/Mesh Triage (ADR-027)
agyis remote exec <target> "<cmd>"             # Multiplexed SSH with login-shell promotion
agyis remote script <target> <file>            # Stdin script streaming (zero disk footprint)
agyis remote triage <target>                   # Compact (<2KB) multi-component health report

# 📊 Empirical Telemetry Laboratory
agyis sync                                     # Audit & synchronize active session telemetry
```

---

## 2. Mandatory Project-Native Automated Verification Contract
1. **Mandatory Automated Verification**:
   - Never declare a task "complete", "fixed", or "verified" without executing the active project's native test runner (e.g. `pnpm test`, `pytest`, `cargo test`, `go test`) and asserting exit code 0.
2. **Sub-Second to Fast Benchmark Invariant**:
   - Unit and integration tests must run as fast and hermetically as possible. Avoid slow network calls, unbounded sleeps, or unneeded whole-filesystem sweeps in verification loops.
3. **Hermetic Isolation**:
   - Tests must never access untracked external services without hermetic mocks or local temporary environments. All state-persisting operations should use temporary directories.

---

## 3. Terminal Invariants & Grep Probing Exception (ADR-013)
1. **Pre-flight Tool Availability (Mitigate Exit Code 127)**:
   - Verify tool availability (`command -v <bin>`) or handle fallback paths gracefully.
2. **Context Flood Prevention (The 200+ Step Cliff)**:
   - Never execute unfiltered commands that dump thousands of lines. Pipe large outputs through `head -n <N>`, `tail -n <N>`, or `wc -l`.
3. **Pattern Probing Exception**:
   - Error swallowing is banned in production code, but standalone terminal pattern probes (`grep`, `diff`) without conditionals must use `|| [ $? -eq 1 ]` to avoid panicking on benign empty matches.
4. **Multi-line Script Hygiene**:
   - Write multi-line scripts to temporary scratch files (`scratch/script.sh` or `scratch/script.py`) rather than escaping fragile multi-line bash `-c` one-liners.

---

## 4. Surgical Contiguous Edits Invariant (99.9% Tool Success)
*Audit revealed single contiguous block replacements achieve 99.9% tool success:*
1. Always make single contiguous block replacements for targeted edits (`replace_file_content`).
2. Do NOT overwrite whole files when modifying specific functions, classes, or blocks.
3. Preserve surrounding comments, docstrings, imports, and formatting.

---

## 5. Context Preservation & Subagent Ladder
*Trajectories <50 steps / <50k tokens maintain 0.8 errors/session; >200 steps suffer a 20x error spike:*
1. **Keep Primary Context in the Healthy Zone (<50k tokens)**.
2. **Anti-Loop Heuristics**:
   - Do NOT repeatedly call `view_file` on the same file within consecutive steps.
   - Evolve search queries; do not repeat identical `grep_search` patterns.
   - Never poll task status in a loop (`manage_task(Action='status')`); await reactive wakeups.
3. **Subagent Delegation Protocol**:
   - Decompose multi-phase refactoring, test debugging, or massive build sweeps, delegating to specialist subagents (`@harness_builder`, `@harness_reviewer`, `@harness_auditor`, `@planner`, `@harness_custodian`, `@coordinator`) in isolated worktrees (`Workspace: "share"` or `"branch"`).
   - Follow the 6-stage Ladder lifecycle: Plan -> Implement (Executioner) -> Review (Hammer) -> Commit Gate (Custodian) -> Verification (Auditor) -> Archival (Coordinator).

---

## 6. The Artifact-First Planning Invariant (ADR-012) & Dynamic Aperture
1. **Anti-Chatbot Seduction**:
   - Never propose multi-component architectural changes or execution plans in raw conversational chat turns.
   - All non-trivial proposals must immediately crystallize into an interactive `implementation_plan.md` artifact before requesting operator confirmation.
2. **Dynamic Sliding Aperture**:
   - High resolution for current task execution.
   - Medium resolution for near-future milestones (macro boundaries; no speculative code).
   - Low resolution for far-future vision.
3. **Retroactive Horizon Compaction**:
   - When completing a phase or milestone, compact findings into the project ledger under 50 lines, update the project roadmap, commit clean code to git, and instruct the operator to reset session.

---

## 7. The 5 Ground Rules
1. **Rule 1 (Zero Error Swallowing)**: Never hide or swallow errors. Zero bare `except:`, no unhandled pipe errors (`set -euo pipefail`).
2. **Rule 2 (No Product Homework in Tests)**: Never redefine product logic or duplicate production calculations in test asserts.
3. **Rule 3 (Complete Deliveries)**: Deliver complete packages (code + types + tests + docs). No partial drafts or broken stubs.
4. **Rule 4 (Zero Verification Homework)**: Self-verify all changes using the project's native test runner before declaring completion.
5. **Rule 5 (Stop & Inquire)**: Stop and ask the operator if an unforeseen blocker, architectural conflict, or ambiguity arises.

---

## 8. Human-in-the-Loop & Steering Alignment
1. **Anti-Drift Commitment**: Anchor all implementation decisions to the agreed plan. If novel obstacles arise, pause and present options.
2. **Proactive Confirmation Gates**: When encountering destructive operations (file deletion, git branch force-push, node reboots), pause for explicit review.
3. **Clear Error Reporting**: If a command fails twice, stop thrashing. State the error concisely and propose a concrete path forward.
<!-- End AGYIS-HARNESS -->
