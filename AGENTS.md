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

## 2. Subagent Ladder Protocol

To ensure rigorous quality control and architectural compliance across multi-agent execution pipelines, contributions must progress through the **Subagent Ladder**:

```
┌───────────────────────────┐
│     Phase Executioner     │ ──► Implements approved phase plan tasks strictly within scope.
└─────────────┬─────────────┘     Zero scope creep; enforces PSL Gold Standard.
              │
              ▼
┌───────────────────────────┐
│ Verification / Hammer     │ ──► Subject changes to aggressive adversarial verification,
└─────────────┬─────────────┘     negative testing, and regression suites.
              │
              ▼
┌───────────────────────────┐
│      Audit & Signoff      │ ──► Validates repository boundaries, packaging integrity,
└───────────────────────────┘     confidentiality compliance, and exit criteria before merge.
```

1. **Phase Executioner**:
   * Strictly executes approved tasks defined in the phase plan.
   * Adheres to the PSL Gold Standard and enforces `set -euo pipefail`.
   * Introduces zero scope creep; touches only files relevant to the plan.
   * Delivers exact file diffs and raw command outputs back to the coordinator.
   * Self-remediates review defects reported by verification or audit nodes.

2. **Verification & Stress Hammer**:
   * Executes exhaustive automated test suites (`bash -n`, `py_compile`, unit/integration tests).
   * Validates negative paths, boundary inputs, failure recoveries, and timeout behaviors.
   * Rejects any test that violates Rule 2 (doing homework for the product).

3. **Integrity & Compliance Auditor**:
   * Validates packaging (`PKGBUILD`, systemd units, directory layouts).
   * Verifies documentation matches implementation.
   * Conducts leak detection (ensuring zero private IPs, personal usernames, or proprietary tokens exist in tree).
   * Confirms all phase exit criteria are satisfied before final signoff.

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
