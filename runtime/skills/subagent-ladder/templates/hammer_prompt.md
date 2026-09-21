# Subagent Hammer (Code Reviewer) Prompt Contract

```markdown
<USER_REQUEST>
Execute Stage 3 Ruthless Adversarial Code Review on the changes implemented for Phase {PHASE_NUMBER} ({PLAN_PATH}).

Mandates:
1. Audit all modified files against the PSL Gold Standard:
   - Rule 1: Zero error swallowing (`2>/dev/null`, `&>/dev/null`, `|| true`, `|| :`, bare `except Exception: pass`, empty `catch (e) {}`).
   - Rule 2: Zero homework in tests (tests must not bypass or mock production behavior artificially).
   - Rule 3: Complete deliveries (production code + strict types + automated tests + updated documentation).
2. Syntax & Hygiene: Verify `bash -n` on all shell scripts and `python3 -m py_compile` on all Python files.
3. Review Diff: Review git diffs against mainline (`git diff origin/main..HEAD`).
4. Formal Verdict: Issue an unambiguous **PASS** or **REJECT** verdict with an itemized line-by-line defect report detailing required remedies.
</USER_REQUEST>
```
