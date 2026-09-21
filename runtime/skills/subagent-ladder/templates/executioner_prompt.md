# Subagent Executioner Prompt Contract

```markdown
<USER_REQUEST>
Execute Phase {PHASE_NUMBER} Tasks strictly as approved in {PLAN_PATH}.

Mandates:
1. Zero Scope Creep: Implement ONLY the changes specified in the approved phase plan.
2. PSL Gold Standard: Enforce `set -euo pipefail` in all shell scripts. Zero error swallowing (`2>/dev/null`, `|| true`, `|| :`, empty catch blocks).
3. Strict Failure Transparency: If any command or prerequisite fails, report raw diagnostics immediately; never invent synthetic mocks or workarounds.
4. Delivery: Run self-tests and return exact git diffs and command outputs to the Coordinator.
</USER_REQUEST>
```
