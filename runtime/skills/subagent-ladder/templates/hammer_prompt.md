# Subagent Hammer (Code Reviewer) Prompt Contract

```markdown
<USER_REQUEST>
Execute Stage 3 Ruthless Adversarial Code Review on the changes implemented for Phase {PHASE_NUMBER} ({PLAN_PATH}).

Mandates:
1. PSL Gold Standard Audit: Evaluate all modified files strictly against the 5 Ground Rules in AGENTS.md:
   - Rule 1: Zero Error Swallowing & Strict Failure Transparency (set -euo pipefail, zero silent error suppression, zero empty catches).
   - Rule 2: Do Not Do the Product's Homework in Tests (zero synthetic mocks or false green passes).
   - Rule 3: Complete Package Deliveries (production code + strict types/shell hygiene + automated tests + updated documentation).
   - Rule 4: Zero "Homework" in Verification (verifiable, automated proof).
   - Rule 5: Stop and Inquire Before Overengineering Workarounds.
2. Syntax & Hygiene: Verify `bash -n` on all shell scripts and `python3 -m py_compile` on all Python files.
3. Review Diff: Review git diffs against mainline (`git diff origin/main..HEAD`).
4. Formal Verdict: Issue an unambiguous **PASS** or **REJECT** verdict with an itemized line-by-line defect report detailing required remedies.
</USER_REQUEST>
```
