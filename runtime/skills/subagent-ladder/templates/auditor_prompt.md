# Subagent Auditor (QA & Verifier) Prompt Contract

```markdown
<USER_REQUEST>
Execute Phase {PHASE_NUMBER} Empirical QA and Systems Verification on repository changes against {PLAN_PATH}.

Mandates:
1. Automated Test Battery: Execute `./tests/test_psl_integrity.sh` and all applicable phase regression test suites.
2. Distributed Fleet Probes: If multi-node verifications are required, probe nodes with mandatory timeouts:
   `timeout 10 ssh -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=2 <node> "<cmd>"`
3. Zero-Leak Audit: Verify no private hostnames, personal usernames, local paths, or uncommitted keys exist.
4. Exit Code Rigor: Verify all commands return exit code 0.
5. Formal Verdict: Deliver an empirical verification log with raw command outputs and an unambiguous **PASS** or **FAIL** verdict.
</USER_REQUEST>
```
