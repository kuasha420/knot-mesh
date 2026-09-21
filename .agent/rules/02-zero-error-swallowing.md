# Zero Error Swallowing & Strict Failure Transparency

## 🚨 MANDATORY ZERO-TOLERANCE GUARDRAIL

Silent error swallowing—such as `2>/dev/null`, `|| true`, `|| :`, or unhandled command redirection—is **strictly forbidden** across the entire Knot codebase. This applies unconditionally to:
- Production scripts and modules
- CLI orchestrators and tools
- Tests and verification scripts
- Scratch and one-off commands
- Agent-generated execution workflows

**Swallowing errors masks broken states, creates phantom successes, turns debugging into guesswork, and is completely unacceptable.**

---

## 🚫 Prohibited Anti-Patterns

### 1. The Blanket Stderr Black Hole
```bash
# FORBIDDEN:
ip neigh 2>/dev/null | grep ...
cat "$FILE" 2>/dev/null
sudo -n ufw status 2>/dev/null
```
*Why*: Masks missing permissions, missing binaries, filesystem corruptions, kernel errors, and syntax faults.

### 2. The Zombie Pass (`|| true` / `|| :`)
```bash
# FORBIDDEN:
sudo gcc -shared ... -o ... || true
systemctl --user restart ... || true
cmd 2>/dev/null || true
```
*Why*: Guarantees that subsequent lines run even if compilation failed, daemons crashed, or writes were rejected. Scripts falsely report success (`[✓] Deployed!`) when the system is actually broken.

### 3. Blind Grepping Without Source Verification
```bash
# FORBIDDEN:
p="$(sshd -T 2>/dev/null | awk ... || true)"
```
*Why*: Returns empty string without indicating whether `sshd` failed validation, permission was denied, or the option was missing.

---

## ✅ Mandatory Required Patterns

### 1. Precondition Testing Before Command Invocation
Always verify existence and read permissions before reading or running:
```bash
# CORRECT:
if [ -r "$FILE" ]; then
  CONTENT="$(< "$FILE")"
else
  knot_log_warn "Configuration file $FILE does not exist or is not readable"
  CONTENT=""
fi
```

### 2. Explicit Exit Status Checking & Failure Propagation
Commands that mutate system state, compile code, or manage services MUST check exit codes and fail fast on error:
```bash
# CORRECT:
if ! sudo gcc -Wall -Wextra -O2 -shared -fPIC "$SRC" $(pkg-config --cflags --libs libportal) -ldl -o "$OUT"; then
  knot_log_err "Failed to compile persistence shim from $SRC to $OUT"
  return 1
fi
```

### 3. Diagnostic Logging Instead of Stderr Suppression
If stderr should not clutter user-facing stdout, redirect it to an explicit diagnostic log or capture it for inspection:
```bash
# CORRECT:
local err_output
if ! err_output="$(sudo -n ufw status 2>&1)"; then
  knot_log_warn "UFW query failed: $err_output"
fi
```

### 4. Intentional Probes Handled via Clean Branching
For probing commands where non-zero is an expected condition (e.g. port scan, ping check, regex test), handle the boolean branching explicitly without `|| true`:
```bash
# CORRECT:
if nc -z -n -w 1 "$ip" "$port"; then
  # Port is open
  return 0
else
  # Port is closed - explicitly handle return code without || true
  return 1
fi
```
*(Note: even when probing network sockets, never append `|| true` to the function or pipeline).*

### 5. Canonical Command Probing
Detect command availability using POSIX standard `command -v` redirecting only stdout:
```bash
# CORRECT:
if command -v agy >/dev/null; then
  # Binary is present in PATH
  return 0
fi
```
*(Note: POSIX specifies that `command -v` writes to stdout on match and emits nothing on stderr. Never use `command -v <cmd> >/dev/null 2>&1`).*

### 6. Native Systemd Unit Inspection
Query systemd units using native quiet flags:
```bash
# CORRECT:
if systemctl --user is-active --quiet knot-agent.service; then
  local stop_err=""
  if ! stop_err="$(systemctl --user stop knot-agent.service 2>&1)"; then
    knot_log_warn "Failed to stop knot-agent.service: $stop_err"
  fi
fi

if systemctl is-enabled --quiet plasmalogin.service; then
  # plasmalogin is active
fi
```

### 7. Canonical DBus Invocations (`busctl` / `qdbus`)
Capture both stdout/stderr and exit codes explicitly, logging transparent notices on failure:
```bash
# CORRECT:
local en_out="" en_rc=0
en_out="$(busctl --user call "$svc" "$path" "$iface" isEnabled 2>&1)" || en_rc=$?
if [ $en_rc -eq 0 ]; then
  # Process successful DBus response
  :
else
  knot_log_warn "Notice: DBus call $svc isEnabled failed (exit code $en_rc): $en_out"
fi
```

### 8. Subprocess Execution & Remote SSH
Never append `|| true` to remote SSH calls (`ssh ... cmd || true`). Inspect remote exit codes cleanly and provide accurate diagnostics:
```bash
# CORRECT:
local remote_out="" rc=0
remote_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 -p "$port" "$target" "knot auth sync" 2>&1)" || rc=$?
if [ $rc -ne 0 ]; then
  knot_log_warn "Failed to sync credentials to node '$target' (exit code $rc): $remote_out"
fi
```

---

## 🔍 Code Review Checklist & Automated Enforcement

Every script, module, tool, and test must satisfy the Universal PSL Integrity Suite before merge:

1. **Automated Enforcement Tool**:
   Run `tests/test_psl_integrity.sh` to execute the universal 5-stage automated audit:
   - Audit 1: Zero error swallowing audit (scans 100% of files for forbidden patterns).
   - Audit 2: Strict shell hygiene audit (`set -euo pipefail`).
   - Audit 3: Shell syntax verification (`bash -n`).
   - Audit 4: Python syntax (`py_compile`) and exception hygiene (no bare `except:` or swallowed `except: pass`).
   - Audit 5: Executable permission verification (`+x`).
2. `grep -rn "2>/dev/null" .` must return ZERO matches across all production code.
3. `grep -rn "|| true" .` must return ZERO matches across all production code.
4. `grep -rn "|| :" .` must return ZERO matches across all production code.
5. Any failure in compilation, systemd units, package managers, or file generation must halt execution and report the root cause transparently.

