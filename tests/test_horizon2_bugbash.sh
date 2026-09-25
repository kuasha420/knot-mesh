#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Horizon 2 Bug Bash Regression Test Suite
# Validates fixes for BUG-014, BUG-015, BUG-016, and BUG-017 under PSL Gold Standard

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export KNOT_ROOT
export PATH="$KNOT_ROOT/bin:$PATH"

PASS_COUNT=0
FAIL_COUNT=0

test_pass() {
  echo -e "  \033[1;32m[✓] PASS:\033[0m $*"
  PASS_COUNT=$((PASS_COUNT + 1))
}

test_fail() {
  echo -e "  \033[1;31m[✗] FAIL:\033[0m $*"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo -e "\033[1;34m============================================================\033[0m"
echo -e "\033[1;34m  KNOT MESH: HORIZON 2 BUG BASH REGRESSION TEST SUITE        \033[0m"
echo -e "\033[1;34m============================================================\033[0m"

# ------------------------------------------------------------------------------
# Test 1: BUG-016 - knot doctor --help and -h handling
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 1/7] Verifying 'knot doctor --help' and '-h' CLI routing...\033[0m"

doc_help_out=""
doc_help_rc=0
if doc_help_out="$(knot doctor --help 2>&1)"; then
  doc_help_rc=0
else
  doc_help_rc=$?
fi

if [ $doc_help_rc -eq 0 ] && echo "$doc_help_out" | grep -q "Usage: knot doctor"; then
  if echo "$doc_help_out" | grep -qiE "unknown option|ssh"; then
    test_fail "knot doctor --help printed usage but still triggered SSH warnings"
  else
    test_pass "knot doctor --help exited 0 with usage and no SSH dispatch"
  fi
else
  test_fail "knot doctor --help failed with exit $doc_help_rc: $doc_help_out"
fi

doc_h_out=""
doc_h_rc=0
if doc_h_out="$(knot doctor -h 2>&1)"; then
  doc_h_rc=0
else
  doc_h_rc=$?
fi

if [ $doc_h_rc -eq 0 ] && echo "$doc_h_out" | grep -q "Usage: knot doctor"; then
  test_pass "knot doctor -h exited 0 with usage"
else
  test_fail "knot doctor -h failed with exit $doc_h_rc: $doc_h_out"
fi

# ------------------------------------------------------------------------------
# Test 2: BUG-016 - knot repair --help and -h handling
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 2/7] Verifying 'knot repair --help' and '-h' CLI routing...\033[0m"

rep_help_out=""
rep_help_rc=0
if rep_help_out="$(knot repair --help 2>&1)"; then
  rep_help_rc=0
else
  rep_help_rc=$?
fi

if [ $rep_help_rc -eq 0 ] && echo "$rep_help_out" | grep -q "Usage: knot repair"; then
  if echo "$rep_help_out" | grep -qiE "unknown option|ssh"; then
    test_fail "knot repair --help printed usage but still triggered SSH warnings"
  else
    test_pass "knot repair --help exited 0 with usage and no SSH dispatch"
  fi
else
  test_fail "knot repair --help failed with exit $rep_help_rc: $rep_help_out"
fi

rep_h_out=""
rep_h_rc=0
if rep_h_out="$(knot repair -h 2>&1)"; then
  rep_h_rc=0
else
  rep_h_rc=$?
fi

if [ $rep_h_rc -eq 0 ] && echo "$rep_h_out" | grep -q "Usage: knot repair"; then
  test_pass "knot repair -h exited 0 with usage"
else
  test_fail "knot repair -h failed with exit $rep_h_rc: $rep_h_out"
fi

# ------------------------------------------------------------------------------
# Test 3: Argument parsing & local routing for doctor/repair
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 3/7] Verifying 'knot doctor --repair local' argument parsing...\033[0m"

doc_local_out=""
doc_local_rc=0
if doc_local_out="$(knot doctor --repair local 2>&1)"; then
  doc_local_rc=0
else
  doc_local_rc=$?
fi

if [ $doc_local_rc -eq 0 ] && echo "$doc_local_out" | grep -q "Diagnostics for Node"; then
  if echo "$doc_local_out" | grep -qiE "unknown option|Querying node: --repair"; then
    test_fail "knot doctor --repair local misparsed target as --repair or failed SSH"
  else
    test_pass "knot doctor --repair local parsed 'local' correctly without remote recursion"
  fi
else
  test_fail "knot doctor --repair local failed with exit $doc_local_rc: $doc_local_out"
fi

# ------------------------------------------------------------------------------
# Test 4: BUG-014 - autologin_ensure_dm definition & non-fatal execution
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 4/7] Verifying autologin_ensure_dm implementation...\033[0m"

ensure_dm_out=""
ensure_dm_rc=0
if ensure_dm_out="$(bash -c "source '$KNOT_ROOT/core/modules/autologin.sh' && autologin_ensure_dm" 2>&1)"; then
  ensure_dm_rc=0
else
  ensure_dm_rc=$?
fi

if [ $ensure_dm_rc -eq 0 ]; then
  test_pass "autologin_ensure_dm executes cleanly with exit code 0"
else
  test_fail "autologin_ensure_dm failed with exit $ensure_dm_rc: $ensure_dm_out"
fi

# ------------------------------------------------------------------------------
# Test 5: BUG-017 - Hostname detection standardization
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 5/7] Verifying knot_detect_hostname fallback hierarchy...\033[0m"

detected_host=""
detected_host="$(bash -c "source '$KNOT_ROOT/core/lib.sh' && knot_detect_hostname")"

if [ -n "$detected_host" ] && [ "$detected_host" != "unknown" ]; then
  test_pass "knot_detect_hostname resolved valid host: '$detected_host'"
else
  test_fail "knot_detect_hostname returned empty or unknown"
fi

# ------------------------------------------------------------------------------
# Test 6: BUG-015 - knot swarm status eliminates false positive timeouts
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 6/7] Verifying 'knot swarm status' telemetry & versioning...\033[0m"

swarm_out=""
swarm_rc=0
if swarm_out="$(knot swarm status 2>&1)"; then
  swarm_rc=0
else
  swarm_rc=$?
fi

if [ $swarm_rc -ne 0 ]; then
  test_fail "knot swarm status failed with exit code $swarm_rc: $swarm_out"
else
  # Check for false-positive strings
  if echo "$swarm_out" | grep -q "KEYRING LOCKED / TIMED OUT"; then
    test_fail "knot swarm status contains false-positive 'KEYRING LOCKED / TIMED OUT'"
  elif echo "$swarm_out" | grep -q "missing"; then
    test_fail "knot swarm status contains 'missing' for CLI version"
  else
    test_pass "knot swarm status reported valid versions and zero false-positive timeouts"
  fi
fi

# ------------------------------------------------------------------------------
# Test 7: Standalone runner syntax validation (deskflow & guard heredocs)
# ------------------------------------------------------------------------------
echo -e "\n\033[1m[Test 7/7] Verifying standalone runner syntax (bash -n on heredocs)...\033[0m"

deskflow_runner_err=""
deskflow_runner_rc=0
if ! deskflow_runner_err="$(sed -n '/cat << .RUNNER_EOF. > "\$user_bin\/knot-deskflow"/,/RUNNER_EOF/p' "$KNOT_ROOT/core/modules/deskflow.sh" | sed '1d;$d' | bash -n 2>&1)"; then
  deskflow_runner_rc=1
fi

if [ $deskflow_runner_rc -eq 0 ]; then
  test_pass "knot-deskflow standalone runner passes 'bash -n' syntax verification"
else
  test_fail "knot-deskflow standalone runner syntax error: $deskflow_runner_err"
fi

guard_runner_err=""
guard_runner_rc=0
if ! guard_runner_err="$(sed -n '/cat << .SCRIPT_EOF. | sudo tee \/usr\/local\/bin\/knot-guard/,/SCRIPT_EOF/p' "$KNOT_ROOT/core/modules/guard.sh" | sed '1d;$d' | bash -n 2>&1)"; then
  guard_runner_rc=1
fi

if [ $guard_runner_rc -eq 0 ]; then
  test_pass "knot-guard standalone script passes 'bash -n' syntax verification"
else
  test_fail "knot-guard standalone script syntax error: $guard_runner_err"
fi

# ------------------------------------------------------------------------------
# Summary & Exit
# ------------------------------------------------------------------------------
echo -e "\n\033[1;34m============================================================\033[0m"
if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "\033[1;32m✔ ALL $PASS_COUNT REGRESSION TESTS PASSED (0 failures)\033[0m"
  echo -e "\033[1;34m============================================================\033[0m"
  exit 0
else
  echo -e "\033[1;31m✖ REGRESSION SUITE FAILED ($FAIL_COUNT failures, $PASS_COUNT passes)\033[0m"
  echo -e "\033[1;34m============================================================\033[0m"
  exit 1
fi
