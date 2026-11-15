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
---
trigger: manual
description: Universal agent rules template for target workspace onboarding
---

<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 Arafat Zahan (@kuasha420) -->
<!-- Corporate Stewardship & Infrastructure: Purrfect Software Limited (PSL) -->
<!-- Governed by: ICARO-42/b Ordinance (Company-Supported Personal IP Framework) -->

# Universal Empirical Agent Rules: Agyis Harness Guidelines

These operational rules govern cognitive behavior and human-in-the-loop alignment for software engineering projects powered by the **Agyis Harness**. All deterministic environment guarantees (runtime injection, pager normalization, surgical grep exit sanitization, output compaction, compaction runway advisories) are enforced transparently by harness hooks.

---

## 1. Explicit Project Command Dictionary (The Victory Pattern)

_Explicit CLI palettes yield 10x lower human intervention rates:_

```bash
# 🧪 Project Verification & Native Toolchain
pytest                                         # Run complete project test suite
python3 -m unittest discover -s tests -v       # Standard unittest runner
bash tests/*.sh                                # Run bash test suites

# 🧪 Project Verification & Agyis Quality Gates
agyis test --diff                              # Run fast targeted tests for uncommitted changes
agyis test --full                              # Run complete project verification suite
agyis verify --spec                            # Verify cleanroom specifications in docs/specs/**
agyis verify                                   # Formally verify cleanroom obligations against evidence
agyis audit aff                                # Audit architectural fitness, boundary & cycle compliance

# 🩺 Environment Diagnostics, Auto-Healing & Hygiene
agyis doctor                                   # Audit 3-tier runtime matrix, hooks & DB port collisions
agyis status                                   # Print harness health, active hooks, horizon & telemetry
agyis clean                                    # Clean stale checkpoints, dead worktrees & scratchpads

# 🧩 Skills, Rules, Subagents & Cockpit Routing
agyis skills                                   # List installed modular skills & stack triggers
agyis rules --lint                             # Lint workspace skills and personas for rule echoes
agyis agents                                   # List registered specialist subagents & bundles
agyis subagents --liveness                     # Inspect active subagents & heartbeat liveness
agyis cockpit status                           # Print flight deck status, runway tokens & git state
agyis router <workflow>                        # Display dynamic subagent router briefing & payload
agyis checkpoint status                        # Check pre-compaction state capture & horizon status

# 🌐 Remote Operations & Empirical Telemetry
agyis remote exec <target> "<cmd>"             # Multiplexed SSH with login-shell promotion
agyis remote script <target> <file>            # Stdin script streaming (zero disk footprint)
agyis remote triage <target>                   # Compact (<2KB) multi-component health report
agyis sync                                     # Bi-directional telemetry synchronization
```

---

## 2. Universal Automated Verification Standard (PSL-INV-001)

1. **Mandatory Project-Native Automated Verification**:
   - Always execute the active repository's native verification command (`pnpm test`, `cargo test`, `pytest`, `go test`, `make test`, or `./agyis test` inside `agyis-harness`) before declaring a task "complete", "fixed", or "verified". Assert exit code 0.
2. **Fast & Hermetic Test Hygiene**:
   - Component unit and contract tests must execute cleanly and hermetically without slow network calls, unbounded sleeps, or whole-filesystem sweeps in verification loops.
3. **Hermetic Isolation & Authentic Assertions**:
   - Tests must use temporary directories and hermetic mocks rather than untracked external services or real product homework re-implemented in assertions.
4. **Mandatory Build Cache Invalidation**:
   - Prior to executing verification gates in rebase, migration, or onboarding workflows, purge stale build caches (`.next/`, `.turbo/`, `node_modules/.cache`) to prevent phantom build artifact regressions.

---

## 3. Terminal Invariants & Grep Probing Exception (PSL-INV-002)

1. **Pre-flight Tool Availability (Mitigate Exit Code 127)**:
   - Verify tool availability (`command -v <bin>`) or handle fallback paths gracefully.
2. **Context Flood Prevention**:
   - Never execute unfiltered commands that dump thousands of lines. Pipe large outputs through `head -n <N>`, `tail -n <N>`, or `wc -l`.
3. **Zero Error Swallowing & Pattern Probing Exception**:
   - Error swallowing (bare `except:`, silent pipe failures without `set -euo pipefail`) is banned in production code; standalone terminal probes (`grep`, `diff`) without conditionals must append `|| [ $? -eq 1 ]` to handle benign empty matches cleanly.
4. **Multi-line Script Hygiene**:
   - Write multi-line scripts to temporary scratch files (`scratch/script.sh` or `scratch/script.py`) rather than escaping fragile multi-line `bash -c` one-liners.
5. **Automated Database Port Collision Remediation**:
   - When containerized DB services hit port 5432 collisions, use automated discovery and rebinding (`detect_port_collision.py --find-free --rebind --env .env`) rather than killing unrelated host services.

---

## 4. Surgical Contiguous Edits Invariant (PSL-INV-003)

1. Always make single contiguous block replacements for targeted edits (`replace_file_content`).
2. Do NOT overwrite whole files when modifying specific functions, classes, or blocks.
3. Preserve surrounding comments, docstrings, imports, and formatting.

---

## 5. Context Preservation, Dynamic Runway & Subagent Delegation (PSL-INV-004)

1. **256k Context Runway & 80-Step Soft Epoch Horizon Model**:
   - Monitor the **256,000-token** context window carefully:
     - **`180,000` tokens (Amber)**: Approaching critical runway limit; focus on converging active deliverables.
     - **`230,000` tokens (Red / Compaction Trigger)**: Compaction imminent (~245,941 historical average trigger); emit or update `.agents/artifacts/checkpoints/<conversation_id>.md` via `agyis checkpoint generate` before handoff.
     - **Soft Epoch Horizon (Per-Epoch Soft Budget = 80 steps)**: `SOFT_EPOCH_STEP_ADVISORY = 80` emits a non-blocking convergence advisory after 80 steps in the current epoch; open sweeps and in-flight edits remain allowed.
2. **Anti-Loop & Reactive Wait Discipline**:
   - Do NOT repeatedly call `view_file` on the same file within consecutive steps.
   - Evolve search queries; do not repeat identical `grep_search` patterns.
   - Never poll `manage_task(Action='status')` or repeatedly tail task logs; output one concise update and await reactive wakeup.
3. **Tool-Native Primacy & Single-Source Skill Hygiene**:
   - Exhaust native CLI flags/options before reading internal tool source or monkeypatching, and avoid duplicating global plugin skills in `.agents/skills/` without project-specific customization.
4. **Subagent Delegation Protocol**:
   - Decompose multi-phase refactoring, test debugging, or broad sweeps using `agyis_*` personas (`@agyis_investigator`, `@agyis_planner`, `@agyis_builder`, `@agyis_reviewer`, `@agyis_custodian`, `@agyis_auditor`, `@agyis_coordinator`, `@agyis_architect`) across the canonical lifecycle (`Investigator / Planner -> Builder -> Reviewer -> Custodian -> Auditor -> Coordinator`) inside isolated worktrees (`Workspace: "share"` or `"branch"`).

---

## 6. Artifact-First Planning Invariant & Dynamic Aperture (PSL-INV-005)

1. **Anti-Chatbot Seduction**:
   - Never propose multi-component architectural changes in raw chat; crystallize non-trivial designs into an interactive `implementation_plan.md` artifact before requesting operator confirmation.
2. **Dynamic Sliding Aperture**:
   - Maintain high resolution for active execution, medium resolution for near-term milestones, and low resolution for far-future scope.
3. **Retroactive Horizon Compaction**:
   - Compact completed phase findings into the project ledger, update the roadmap, commit clean changes, and instruct the operator to reset into a fresh session.

---

## 7. Human-in-the-Loop & Steering Alignment (PSL-INV-006)

1. **Anti-Drift Commitment**: Anchor implementation decisions to the agreed plan and pause when unforeseen blockers or ambiguity arise.
2. **Proactive Confirmation Gates**: Pause for explicit review before destructive operations (file deletion, force-push, service restarts/reboots).
3. **Clear Error Reporting & Complete Deliveries**: Deliver complete packages (code + types + tests + docs). If a command fails twice, stop thrashing, state the error concisely, and propose concrete next options.

---

## 8. Universal Cleanroom Reverse Engineering & Reconstruction Invariants (PSL-INV-007)

1. **Dirty Room vs. Clean Room Isolation**: Keep binary/disassembly inspection (`.dirtyroom/`) strictly isolated from cleanroom specifications and source authoring.
2. **Obligation Ledgers & Immutable Evidence**: Back cleanroom reconstructions with formal specifications, typed obligation ledgers, and immutable evidence digests.
3. **Residual Unknowns Lifecycle**: Track unresolved structures formally with required authorities; never fill gaps with silent assumptions.
4. **Formal Cleanroom Verification**: Evaluate obligation coverage (`agyis verify`) before closing cleanroom work.

---

## 9. Cockpit Flight Direction & Dual-Auditor Gate (PSL-INV-008)

1. **Zero-Code-Thrash Flight Direction**: Root orchestration (`@agyis_coordinator`) decomposes milestones, evaluates trade-offs, and enforces governance via structured transition payloads (`mission_id`, `objective`, `deliverables`, `context_paths`, `verification_gate`).
2. **Dual-Plane Communication & Dual-Auditor Gate**: Keep parent cockpit pairing distinct from child subagent `send_message` reporting, and pass multi-phase tasks through independent review (`@agyis_reviewer` + `@agyis_auditor`).

---

## 10. Pre-Analyzed Decompiler Cache Invariant (PSL-INV-009)

1. **Mandatory Pre-Analyzed Cache**: Never trigger unbounded full-binary Ghidra analysis passes during ad-hoc tool calls on binaries `>10 MB`; use pre-analyzed read-only project caches (`-noanalysis -readOnly`) returning queries in `<2.0s` while keeping `.dirtyroom/`, `.gpr`, and `.rep` files gitignored.

---

## 11. Anti-Vibe-Coding & Dynamic Lifecycle Invariant (PSL-INV-010)

1. **Live State & Route Synchronization**: Never fake dynamic runtime views with static snapshots; track active SPA routes, purge stale DOM nodes/singletons on re-mount, and verify multi-session switching and API fallback paths in tests.

---

## 12. Universal Architectural Fitness Invariant (PSL-INV-011)

1. **Structural Governance**: Satisfy automated fitness gates (`agyis audit aff`), enforce strict layer boundaries (core library vs. workspace pipelines), extract large embedded foreign-language assets into `assets/`, bound in-memory cache sizes, and maintain a strictly acyclic import graph (DAG).
<!-- End AGYIS-HARNESS -->
