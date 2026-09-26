#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Wayland Virtual Monitor Fabric Automated Test Suite
# Validates PSL Gold Standard integrity, CLI routing, firewall configuration,
# DBus capability discovery, and doctor diagnostics.

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export KNOT_ROOT
export PATH="$KNOT_ROOT/bin:$PATH"

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

pass() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  PASSED_TESTS=$((PASSED_TESTS + 1))
  echo -e "  \033[1;32m[✓] PASS:\033[0m $1"
}

fail() {
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  FAILED_TESTS=$((FAILED_TESTS + 1))
  echo -e "  \033[1;31m[✗] FAIL:\033[0m $1"
}

echo -e "\033[1;34m============================================================\033[0m"
echo -e "\033[1;34m  KNOT MESH: WAYLAND VIRTUAL MONITOR TEST SUITE             \033[0m"
echo -e "\033[1;34m============================================================\033[0m"

# -------------------------------------------------------------
# Test 1: PSL Rule 1 Zero Error-Swallowing Audit
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 1] PSL Rule 1 Audit on Virtual Monitor Modules...\033[0m"
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
TARGET_FILES=(
  "$KNOT_ROOT/core/modules/kdeconnect.sh"
  "$KNOT_ROOT/core/modules/firewall.sh"
  "$KNOT_ROOT/core/modules/doctor.sh"
  "$KNOT_ROOT/bin/knot"
)

psl_clean=1
for f in "${TARGET_FILES[@]}"; do
  [ -f "$f" ] || continue
  matches=""
  if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$f" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
    matches=""
  fi
  if [ -n "$matches" ]; then
    echo "    Found forbidden patterns in $f:"
    echo "$matches"
    psl_clean=0
  fi
done

if [ $psl_clean -eq 1 ]; then
  pass "Zero error-swallowing patterns found in Virtual Monitor code"
else
  fail "Forbidden error-swallowing pattern found"
fi

# -------------------------------------------------------------
# Test 2: Bash Syntax Check (bash -n)
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 2] Bash Syntax Verification...\033[0m"
syntax_clean=1
for f in "${TARGET_FILES[@]}"; do
  [ -f "$f" ] || continue
  syn_out="" syn_rc=0
  syn_out=$(bash -n "$f" 2>&1) || syn_rc=$?
  if [ $syn_rc -ne 0 ]; then
    echo "    Syntax error in $f: $syn_out"
    syntax_clean=0
  fi
done

if [ $syntax_clean -eq 1 ]; then
  pass "All modified scripts pass bash -n without syntax errors"
else
  fail "Syntax check failed on one or more scripts"
fi

# -------------------------------------------------------------
# Test 3: CLI Usage & Help Routing
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 3] CLI Command Dispatch & Usages...\033[0m"

# knot kdeconnect vmon usage check
vmon_help_out="" vmon_help_rc=0
vmon_help_out=$("$KNOT_ROOT/bin/knot" kdeconnect vmon invalid_action 2>&1) || vmon_help_rc=$?
if [ $vmon_help_rc -ne 0 ] && echo "$vmon_help_out" | grep -q "Usage: knot kdeconnect vmon"; then
  pass "knot kdeconnect vmon displays correct usage on invalid subaction"
else
  fail "knot kdeconnect vmon usage routing failed ($vmon_help_rc): $vmon_help_out"
fi

# knot display usage check
disp_help_out="" disp_help_rc=0
disp_help_out=$("$KNOT_ROOT/bin/knot" display invalid_action 2>&1) || disp_help_rc=$?
if [ $disp_help_rc -ne 0 ] && echo "$disp_help_out" | grep -q "Usage: knot display"; then
  pass "knot display displays correct usage on invalid subaction"
else
  fail "knot display usage routing failed ($disp_help_rc): $disp_help_out"
fi

# -------------------------------------------------------------
# Test 4: Host & Client Engine Availability
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 4] Package Engine Availability...\033[0m"
if command -v krdpserver >/dev/null; then
  pass "Host engine 'krdpserver' (krdp) is present in PATH"
else
  fail "Host engine 'krdpserver' (krdp) missing"
fi

if command -v krdc >/dev/null; then
  pass "Client engine 'krdc' (freerdp) is present in PATH"
else
  fail "Client engine 'krdc' (freerdp) missing"
fi

# -------------------------------------------------------------
# Test 5: Firewall Rule Verification Function
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 5] Firewall Verification Module...\033[0m"
fw_rc=0 fw_out=""
fw_out=$(bash -c "source '$KNOT_ROOT/core/modules/firewall.sh' && firewall_verify_vmon" 2>&1) || fw_rc=$?
if [ $fw_rc -eq 0 ] && echo "$fw_out" | grep -q "Virtual Monitor"; then
  pass "firewall_verify_vmon executes and succeeds with clean zero exit code"
else
  fail "firewall_verify_vmon failed ($fw_rc): $fw_out"
fi

# -------------------------------------------------------------
# Test 6: Virtual Monitor Status Command Execution
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 6] knot kdeconnect vmon status Execution...\033[0m"
vmon_status_out="" vmon_status_rc=0
vmon_status_out=$("$KNOT_ROOT/bin/knot" kdeconnect vmon status 2>&1) || vmon_status_rc=$?
if [ $vmon_status_rc -eq 0 ] && echo "$vmon_status_out" | grep -q "Host Engine (krdp / krdpserver) :"; then
  pass "knot kdeconnect vmon status runs cleanly and displays engine headers"
else
  fail "knot kdeconnect vmon status failed ($vmon_status_rc): $vmon_status_out"
fi

# -------------------------------------------------------------
# Test 7: knot display status Alias Execution
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 7] knot display status Alias Execution...\033[0m"
disp_status_out="" disp_status_rc=0
disp_status_out=$("$KNOT_ROOT/bin/knot" display status 2>&1) || disp_status_rc=$?
if [ $disp_status_rc -eq 0 ] && echo "$disp_status_out" | grep -q "Host Engine (krdp / krdpserver) :"; then
  pass "knot display status alias functions identically to vmon status"
else
  fail "knot display status failed ($disp_status_rc): $disp_status_out"
fi

# -------------------------------------------------------------
# Test 8: DBus Interface Introspection & Device Resolution
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 8] DBus Device Resolution & Capability...\033[0m"
dev_res_out="" dev_res_rc=0
dev_res_out=$(bash -c "
  source '$KNOT_ROOT/core/lib.sh'
  source '$KNOT_ROOT/core/modules/kdeconnect.sh'
  kdeconnect_resolve_device_id laptop 2>&1
" 2>&1) || dev_res_rc=$?

if [ $dev_res_rc -eq 0 ] && [ -n "$dev_res_out" ]; then
  pass "kdeconnect_resolve_device_id successfully resolved laptop to $dev_res_out"
else
  fail "kdeconnect_resolve_device_id failed ($dev_res_rc): $dev_res_out"
fi

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
echo -e "\n\033[1;34m============================================================\033[0m"
echo -e "Total Tests : $TOTAL_TESTS"
echo -e "Passed      : \033[1;32m$PASSED_TESTS\033[0m"
echo -e "Failed      : \033[1;31m$FAILED_TESTS\033[0m"
echo -e "\033[1;34m============================================================\033[0m"

if [ $FAILED_TESTS -eq 0 ]; then
  exit 0
else
  exit 1
fi
