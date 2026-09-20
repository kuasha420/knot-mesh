# AGENTS.md — Knot Mesh Engineering Governance & Operational Protocol

Welcome to **Knot Mesh** (`kuasha420/knot-mesh`). All autonomous agents, subagents, and human contributors operating within this repository are bound by the governance standards, architectural gradients, and verification rules defined in this document.

---

## 1. Core Engineering Philosophy: PSL Gold Standard

This repository adheres to the engineering standards established in [`purrfectsoft/sunshine-physio-webapp`](https://github.com/purrfectsoft/sunshine-physio-webapp.git):

### 1.1 The 5 Ground Rules of Engineering Integrity

1. **Rule 1: Zero Error Swallowing & Strict Failure Transparency**
   * Absolute ban on `2>/dev/null`, `&>/dev/null`, `> /dev/null 2>&1`, and `|| true` / `|| :` in bash scripts, tooling, and test runners.
   * Absolute ban on empty `catch (e) {}` blocks, `// @ts-ignore`, `// @ts-nocheck`, or careless `any` in TypeScript.
   * All scripts must enforce `set -euo pipefail`. Stderr and non-zero exit codes must remain transparently logged and resolved.
   * Probing commands must use clean, explicit branching instead of blanket error suppression.

2. **Rule 2: Do Not Do the Product's Homework in Tests**
   * Never manufacture false green test passes by duplicating logic or mocks inside test files.
   * Tests must directly import and execute exported product code.

3. **Rule 3: Complete Package Deliveries**
   * Every delivery is incomplete unless it contains: **Production Code + Strict Types + Comprehensive Tests + Formatting/Linting + Up-to-Date Docs**.

4. **Rule 4: Zero "Homework" in Verification**
   * Every claim must be backed by verifiable, automated proof (`pytest`, bash test suites, CLI exit code inspection).
   * If any flakiness or ambiguity arises, **STOP immediately** and report the raw diagnostic or challenge the premise.

5. **Rule 5: Stop and Inquire Before Overengineering Workarounds**
   * When external dependencies, credentials, or environment prerequisites fail, never invent synthetic wrappers, fallback bypasses, or proxy hacks.
   * Stop, surface the exact raw diagnostic, and prompt the operator for decision or intervention.

---

## 2. The Resolution Gradient Architecture

All features, refactors, and issue resolutions follow the **Resolution Gradient**:

* **Horizon 1 (Immediate: High Resolution)**: Concrete deliverables, strict type contracts, executable test suites, zero ambiguity, independent node-level verification. (Issues #54, #43, #41, #42).
* **Horizon 2 (Intermediate: Medium Resolution)**: Architectural enablers, macro milestones, domain boundaries without premature micro-specification.
* **Horizon 3 (Far Horizon: Low Resolution)**: Strategic capabilities, cross-ecosystem connectors, Post-GA Rematch (Issue #55).

---

## 3. Anti-Drama & Signal-to-Noise Policy

* **Zero ACK Spam**: Do not post acknowledgments, polite chitchat, or performative narration ("Understood!", "Working on this now!").
* **Code-First Challenges**: If a design or implementation cannot be substantiated with working code and test passes, peer nodes or the coordinator must challenge it immediately.
* **Operator Steering**: Any node can stop execution and await operator steering or intervention when human alignment is necessary.

---

## 4. OSS Boundary & Local Artifact Hygiene

* **Public Git Tree**: Clean, reproducible, and generic. Zero private IPs, personal user names, or machine-specific environment assumptions.
* **Internal / Node-Local Artifacts**: Private setup notes, local scratch scripts, and raw diagnostic transcripts must be kept in `<appDataDir>/brain/<conversation-id>/` and announced to the swarm via the council message board without polluting public git commits.

---

## 5. Leased Autonomy Contract (`/goal-with-lease`)

* Operate with maximum autonomous momentum within a leased delegation scope bounded by workstream, milestone, and invariant checks.
* **Intervention Triggers**:
  1. *Tier 1: Architectural & Strategic Decisions* — High-level paradigm choices, breaking schema/API contracts, or new dependency additions.
  2. *Tier 2: Rule 5 Stop-and-Inquire Escalations* — Missing credentials, upstream repo permission blocks, or unresolvable hardware/environment faults.
  3. *Tier 3: Micro-Debate Deadlocks* — Unresolvable code review disagreements between collaborator nodes after two peer exchanges.

---

## 6. Swarm Topology & Hardware Roles

| Node ID | Physical Role | Hardware Specialization | Primary Responsibilities |
| :--- | :--- | :--- | :--- |
| **`desktop`** | **Anchor Workstation** | Primary Mainline, High RAM, GPG Signer | Swarm orchestration, issue assignment, peer review merging, GPG signed commits, Hub database management. |
| **`laptop`** | **Worker Alpha** | RTX 3050 CUDA, Linux Core, High Compute | Python daemons (`knot-agent`, `knot-hub`), MCP Gateway tests, concurrency stress tests, memory backend indexing. |
| **`rog-ally`** | **Worker Beta** | Handheld PC / Secondary Compute, Arch/Linux | Multi-node resolution validation, resolver proxy stress tests, cross-node git worktree synchronization tests. |
| **`steamdeck`** | **Worker Gamma** | SteamOS (Immutable FS), Wayland/KWin Specialist | Low-privilege runtime constraints, Wayland portal compliance, KVM zero-dropout audits, handheld touch/gamepad UI testing. |

---

## 7. GPG Commit Signing Enforcement

Every git commit to `main` or release branches MUST be cryptographically signed with the designated GPG key:
```bash
git commit -S -m "..."
```
**Enforced Key ID**: `<CONFIGURED_GPG_KEY_ID>`
Unsigned commits or commits signed with unauthorized keys will be rejected by CI and council merge gates.
