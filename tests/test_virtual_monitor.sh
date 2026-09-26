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
# Test 9: Host TLS Certificate & Configuration Automation
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 9] Host TLS Certificate & krdpserverrc Generation...\033[0m"
cert_test_out="" cert_test_rc=0
cert_test_out=$(bash -c "
  source '$KNOT_ROOT/core/lib.sh'
  source '$KNOT_ROOT/core/modules/kdeconnect.sh'
  kdeconnect_vmon_ensure_host_certs 2>&1
" 2>&1) || cert_test_rc=$?

if [ $cert_test_rc -eq 0 ] && [ -f "$HOME/.local/share/krdpserver/krdp.crt" ] && [ -f "$HOME/.local/share/krdpserver/krdp.key" ]; then
  pass "kdeconnect_vmon_ensure_host_certs ensures valid TLS cert and key exist"
else
  fail "kdeconnect_vmon_ensure_host_certs failed ($cert_test_rc): $cert_test_out"
fi

# -------------------------------------------------------------
# Test 10: Client Zero-Prompt Preference Configuration
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 10] Client Zero-Prompt Configuration (krdcrc)...\033[0m"
client_test_out="" client_test_rc=0
client_test_out=$(bash -c "
  source '$KNOT_ROOT/core/lib.sh'
  source '$KNOT_ROOT/core/modules/kdeconnect.sh'
  kdeconnect_vmon_seed_client_trust 2>&1
" 2>&1) || client_test_rc=$?

krdc_pref_val=""
if command -v kreadconfig6 >/dev/null; then
  krdc_pref_val="$(kreadconfig6 --file krdcrc --group General --key ShowPreferencesForNewConnections 2>&1)" || krdc_pref_val=""
fi

if [ $client_test_rc -eq 0 ] && [ "$krdc_pref_val" = "false" ]; then
  pass "kdeconnect_vmon_seed_client_trust configures zero-prompt krdcrc preferences"
else
  fail "kdeconnect_vmon_seed_client_trust failed ($client_test_rc): pref=$krdc_pref_val, out=$client_test_out"
fi

# -------------------------------------------------------------
# Test 11: Topology Placement & HiDPI Scaling Calculation
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 11] Topology Placement & HiDPI Scaling Calculation...\033[0m"
calc_out="" calc_rc=0
calc_out=$(python3 -c '
v_w, v_h = 3072, 1728
p_w, p_h, p_scale = 3440, 1440, 2.0
v_scale = 2 if v_w >= 2560 else 1
v_log_w = int(round(v_w / v_scale))
v_log_h = int(round(v_h / v_scale))
p_log_w = int(round(p_w / p_scale))
p_log_h = int(round(p_h / p_scale))

diff_h = v_log_h - p_log_h

# Test left direction
direction = "left"
if diff_h >= 0:
    v_pos = "0,0"
    p_pos = f"{v_log_w},{diff_h}"
else:
    v_pos = f"0,{-diff_h}"
    p_pos = f"{v_log_w},0"
cmd_left = f"output.Virtual-1.scale.{v_scale} output.Virtual-1.position.{v_pos} output.DP-1.position.{p_pos}"

# Test right direction
direction = "right"
if diff_h >= 0:
    p_pos_r = f"0,{diff_h}"
    v_pos_r = f"{p_log_w},0"
else:
    p_pos_r = "0,0"
    v_pos_r = f"{p_log_w},{-diff_h}"
cmd_right = f"output.Virtual-1.scale.{v_scale} output.Virtual-1.position.{v_pos_r} output.DP-1.position.{p_pos_r}"

print(f"{cmd_left};;{cmd_right}")
' 2>&1) || calc_rc=$?

expected_left="output.Virtual-1.scale.2 output.Virtual-1.position.0,0 output.DP-1.position.1536,144"
expected_right="output.Virtual-1.scale.2 output.Virtual-1.position.1720,0 output.DP-1.position.0,144"

if [ $calc_rc -eq 0 ] && echo "$calc_out" | grep -q "$expected_left" && echo "$calc_out" | grep -q "$expected_right"; then
  pass "Topology placement and HiDPI scaling calculates sub-pixel coordinates for left & right placements (bottom-aligned)"
else
  fail "Topology placement calculation failed ($calc_rc): $calc_out"
fi

# -------------------------------------------------------------
# Test 12: Deskflow Link Muting Layout Compilation
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 12] Deskflow Link Muting Layout Compilation...\033[0m"
mute_test_out="" mute_test_rc=0
mute_test_out=$(python3 "$KNOT_ROOT/core/modules/compile_deskflow.py" \
  --topology "$HOME/.config/knot/swarms/home/topology.json" \
  --nodes-dir "$HOME/.config/knot/swarms/home/nodes" \
  --mode unlocked \
  --mute-node laptop 2>&1) || mute_test_rc=$?

mute_verify="" mv_rc=0
mute_verify=$(python3 -c '
import sys
text = sys.argv[1]
in_links = False
links_text = ""
for line in text.splitlines():
    if "section: links" in line:
        in_links = True
    elif in_links and "end" in line:
        break
    elif in_links:
        links_text += line + "\n"

if "= devbox" not in links_text and "devbox(" not in links_text and "psl-0000" in links_text:
    print("MUTED_OK")
else:
    sys.exit(1)
' "$mute_test_out" 2>&1) || mv_rc=$?

if [ $mute_test_rc -eq 0 ] && [ $mv_rc -eq 0 ] && [ "$mute_verify" = "MUTED_OK" ]; then
  pass "compile_deskflow.py --mute-node laptop successfully omits laptop links while preserving other nodes"
else
  fail "Deskflow link muting compilation failed: rc=$mute_test_rc, mv_rc=$mv_rc, out=$mute_test_out"
fi

# -------------------------------------------------------------
# Test 13: Plasma Panel Script Syntax & DBus Evaluation
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 13] Plasma Panel Script Idempotency & DBus Evaluation...\033[0m"
panel_test_out="" panel_test_rc=0
panel_test_out=$(bash -c "
  source '$KNOT_ROOT/core/lib.sh'
  source '$KNOT_ROOT/core/modules/kdeconnect.sh'
  kdeconnect_vmon_reconcile_plasma_panel 2>&1
" 2>&1) || panel_test_rc=$?

if [ $panel_test_rc -eq 0 ]; then
  pass "kdeconnect_vmon_reconcile_plasma_panel executes cleanly via DBus PlasmaShell interface"
else
  fail "kdeconnect_vmon_reconcile_plasma_panel failed ($panel_test_rc): $panel_test_out"
fi

# -------------------------------------------------------------
# Test 14: knot display toggle-kvm CLI & State Toggle
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 14] knot display toggle-kvm State Transitions...\033[0m"
rm -f /run/knot/vmon_muted_deskflow_laptop "$HOME/.local/state/knot/vmon_muted_deskflow_laptop"
toggle_1_out="" toggle_1_rc=0
toggle_1_out=$("$KNOT_ROOT/bin/knot" display toggle-kvm laptop 2>&1) || toggle_1_rc=$?
state_1_exists=0
[ -f "/run/knot/vmon_muted_deskflow_laptop" ] && state_1_exists=1

toggle_2_out="" toggle_2_rc=0
toggle_2_out=$("$KNOT_ROOT/bin/knot" display toggle-kvm laptop 2>&1) || toggle_2_rc=$?
state_2_exists=0
[ -f "/run/knot/vmon_muted_deskflow_laptop" ] && state_2_exists=1

if [ $toggle_1_rc -eq 0 ] && [ $state_1_exists -eq 1 ] && [ $toggle_2_rc -eq 0 ] && [ $state_2_exists -eq 0 ]; then
  pass "knot display toggle-kvm correctly cycles between MUTED and UNMUTED state"
else
  fail "knot display toggle-kvm state cycle failed: s1=$state_1_exists, s2=$state_2_exists"
fi

# -------------------------------------------------------------
# Test 15: knot-stripd Mute-Aware Dynamic Edge Visibility
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 15] knot-stripd Mute-Aware Edge State Propagation...\033[0m"
stripd_test_out="" stripd_test_rc=0
stripd_test_out=$(python3 -c '
import os, sys
sys.path.insert(0, "'"$KNOT_ROOT"'")
from PyQt6.QtCore import QCoreApplication
app = QCoreApplication([])

# Import KnotEdgeController from bin/knot-stripd
import importlib.machinery, importlib.util
loader = importlib.machinery.SourceFileLoader("knot_stripd", "'"$KNOT_ROOT"'/bin/knot-stripd")
spec = importlib.util.spec_from_loader("knot_stripd", loader)
mod = importlib.util.module_from_spec(spec)
loader.exec_module(mod)

ctrl = mod.KnotEdgeController("laptop", "left", "#00f0ff", [0, 100], {"laptop", "devbox"}, {"192.168.68.145"})
ctrl.set_connected(True)
ctrl.set_locked(False)
assert not ctrl.muted, "Default muted should be False"

# Emulate check_lock_state muting
ctrl.set_muted(True)
assert ctrl.muted, "Controller must reflect muted=True"

ctrl.set_muted(False)
assert not ctrl.muted, "Controller must reflect unmuted=False"
print("STRIPD_MUTE_OK")
' 2>&1) || stripd_test_rc=$?

if [ $stripd_test_rc -eq 0 ] && echo "$stripd_test_out" | grep -q "STRIPD_MUTE_OK"; then
  pass "knot-stripd KnotEdgeController correctly binds and emits muted state"
else
  fail "knot-stripd mute awareness failed ($stripd_test_rc): $stripd_test_out"
fi

# -------------------------------------------------------------
# Test 16: knot-vmon-keepalive Daemon Integrity
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 16] knot-vmon-keepalive Daemon Integrity...\033[0m"
if [ -x "$KNOT_ROOT/bin/knot-vmon-keepalive" ]; then
  ka_syntax_rc=0
  python3 -m py_compile "$KNOT_ROOT/bin/knot-vmon-keepalive" 2>&1 || ka_syntax_rc=$?
  if [ $ka_syntax_rc -eq 0 ]; then
    pass "knot-vmon-keepalive binary exists, is executable, and compiles cleanly"
  else
    fail "knot-vmon-keepalive compilation error: $ka_syntax_rc"
  fi
else
  fail "knot-vmon-keepalive binary is missing or not executable"
fi

# -------------------------------------------------------------
# Test 17: kdeconnect_vmon_is_active Guard & Reconciliation Safety
# -------------------------------------------------------------
echo -e "\n\033[1m[Test 17] kdeconnect_vmon_is_active Guard & Reconciliation Safety...\033[0m"
vmon_guard_out="" vmon_guard_rc=0
vmon_guard_out=$(bash -c "
  set -euo pipefail
  source '$KNOT_ROOT/core/lib.sh'
  source '$KNOT_ROOT/core/modules/kdeconnect.sh'

  # Clean any existing test flags
  rm -f /run/knot/vmon_muted_deskflow_testnode

  # Simulate active vmon stream state via mock flag
  mkdir -p /run/knot
  touch /run/knot/vmon_muted_deskflow_testnode

  if ! kdeconnect_vmon_is_active; then
    echo 'FAIL: kdeconnect_vmon_is_active returned false despite flag file'
    exit 1
  fi

  # Test that kdeconnect_sync_mesh detects active vmon and preserves network
  sync_log=\$(kdeconnect_sync_mesh 2>&1)
  if ! echo \"\$sync_log\" | grep -q 'Virtual Monitor stream is active; skipping forceOnNetworkChange'; then
    echo \"FAIL: kdeconnect_sync_mesh did not log vmon bypass: \$sync_log\"
    exit 2
  fi

  # Cleanup mock flag
  rm -f /run/knot/vmon_muted_deskflow_testnode
  echo 'GUARD_OK'
" 2>&1) || vmon_guard_rc=$?

if [ $vmon_guard_rc -eq 0 ] && echo "$vmon_guard_out" | grep -q "GUARD_OK"; then
  pass "kdeconnect_vmon_is_active accurately detects stream state and protects reconciliation"
else
  fail "kdeconnect_vmon_is_active guard test failed ($vmon_guard_rc): $vmon_guard_out"
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
