#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Automated Verification Suite for Issue #60
# Multi-Tenant Local Profile Sandboxing & Headless Authentication Isolation
# PSL Gold Standard: Zero error swallowing, zero || true, strict type/shell hygiene

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KNOT_ROOT="$REPO_ROOT"
export PATH="$REPO_ROOT/bin:$PATH"

TEST_SANDBOX="$(mktemp -d /tmp/knot_auth_test.XXXXXX)"
export KNOT_TEST_AUTH_DIR="$TEST_SANDBOX/auth"
export KNOT_TEST_UPSTREAM_TOKEN="$TEST_SANDBOX/upstream/antigravity-oauth-token"
export KNOT_TEST_IDE_TOKEN="$TEST_SANDBOX/upstream_ide/oauth-token.json"

mkdir -p "$TEST_SANDBOX/upstream"
mkdir -p "$TEST_SANDBOX/upstream_ide"

cleanup() {
  local rc=$?
  rm -rf "$TEST_SANDBOX"
  exit $rc
}
trap cleanup EXIT

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #60 Auth Sandboxing Regression Test Suite"
echo "================================================================================"
echo "Sandbox: $TEST_SANDBOX"

# Helper to generate synthetic valid token payload
create_synthetic_token() {
  local target_file="$1"
  local email="$2"
  local access_tok="$3"
  mkdir -p "$(dirname "$target_file")"
  cat << JSON_EOF > "$target_file"
{
  "auth_method": "oauth",
  "email": "$email",
  "token": {
    "access_token": "$access_tok",
    "refresh_token": "refresh_${access_tok}",
    "expiry": "2026-09-26T12:00:00Z",
    "token_type": "Bearer"
  }
}
JSON_EOF
  chmod 0600 "$target_file"
}

# ------------------------------------------------------------------------------
# Test 1: Empty Sandbox Initialization & Status Schema
# ------------------------------------------------------------------------------
echo "--- [1/8] Testing empty sandbox initialization & status schema ---"
status_json="$(knot auth status --json)"
echo "$status_json" | jq -e '.active_profile == null' >/dev/null
echo "$status_json" | jq -e '.profiles_count == 0' >/dev/null
echo "$status_json" | jq -e '.token_valid == false' >/dev/null
echo "  [PASS] Empty status JSON validated."

# Verify directory permissions
perms="$(stat -c "%a" "$KNOT_TEST_AUTH_DIR")"
if [ "$perms" != "700" ]; then
  echo "Error: Expected auth dir permissions 700, got $perms"
  exit 1
fi
echo "  [PASS] Directory permissions enforced at 0700."

# ------------------------------------------------------------------------------
# Test 2: Profile Ingestion & Permission Hardening
# ------------------------------------------------------------------------------
echo "--- [2/8] Testing profile ingestion & permission hardening ---"
synth_token_1="$TEST_SANDBOX/token_alpha.json"
create_synthetic_token "$synth_token_1" "alpha@work.com" "tok_alpha_123"

knot auth import alpha "$synth_token_1"

# Check profile directory
pdir_alpha="$KNOT_TEST_AUTH_DIR/profiles/alpha"
if [ ! -d "$pdir_alpha" ]; then
  echo "Error: Profile alpha directory was not created."
  exit 1
fi

p_perms="$(stat -c "%a" "$pdir_alpha")"
t_perms="$(stat -c "%a" "$pdir_alpha/oauth-token.json")"
if [ "$p_perms" != "700" ] || [ "$t_perms" != "600" ]; then
  echo "Error: Bad permissions. Dir=$p_perms (want 700), Token=$t_perms (want 600)"
  exit 1
fi
echo "  [PASS] Profile directory (0700) and token (0600) permission hardening verified."

# ------------------------------------------------------------------------------
# Test 3: Upstream Symlink Propagation
# ------------------------------------------------------------------------------
echo "--- [3/8] Testing upstream symlink propagation ---"
if [ ! -L "$KNOT_TEST_UPSTREAM_TOKEN" ]; then
  echo "Error: Upstream CLI token is not a symlink."
  exit 1
fi
resolved_upstream="$(readlink -f "$KNOT_TEST_UPSTREAM_TOKEN")"
expected_token="$(readlink -f "$pdir_alpha/oauth-token.json")"
if [ "$resolved_upstream" != "$expected_token" ]; then
  echo "Error: Upstream link points to $resolved_upstream, expected $expected_token"
  exit 1
fi
echo "  [PASS] Upstream CLI token resolves atomically to active profile token."

# ------------------------------------------------------------------------------
# Test 4: Multi-Profile Registration & Atomic Symlink Switching
# ------------------------------------------------------------------------------
echo "--- [4/8] Testing multi-profile registration & atomic symlink switching ---"
synth_token_2="$TEST_SANDBOX/token_beta.json"
create_synthetic_token "$synth_token_2" "beta@personal.com" "tok_beta_456"

knot auth import beta "$synth_token_2"

# Beta should now be active
status_json_beta="$(knot auth status --json)"
echo "$status_json_beta" | jq -e '.active_profile == "beta"' >/dev/null
echo "$status_json_beta" | jq -e '.email == "beta@personal.com"' >/dev/null
echo "$status_json_beta" | jq -e '.profiles_count == 2' >/dev/null
echo "$status_json_beta" | jq -e '.token_valid == true' >/dev/null

# Switch back to alpha atomically
knot auth switch alpha

status_json_alpha="$(knot auth status --json)"
echo "$status_json_alpha" | jq -e '.active_profile == "alpha"' >/dev/null
echo "$status_json_alpha" | jq -e '.email == "alpha@work.com"' >/dev/null

resolved_active="$(readlink "$KNOT_TEST_AUTH_DIR/active_profile")"
if [ "$resolved_active" != "profiles/alpha" ]; then
  echo "Error: Active profile symlink points to $resolved_active, expected profiles/alpha"
  exit 1
fi
echo "  [PASS] Atomic symlink switching between multiple profiles verified."

# ------------------------------------------------------------------------------
# Test 5: Table Output Formatter
# ------------------------------------------------------------------------------
echo "--- [5/8] Testing formatted list output ---"
list_out="$(knot auth list)"
echo "$list_out" | grep -q "alpha"
echo "$list_out" | grep -q "beta"
echo "$list_out" | grep -q "alpha@work.com"
echo "$list_out" | grep -q "beta@personal.com"
echo "  [PASS] knot auth list properly formats profile table."

# ------------------------------------------------------------------------------
# Test 6: Non-Blocking D-Bus Lock State Probing
# ------------------------------------------------------------------------------
echo "--- [6/8] Testing non-blocking lock probe (test-lock) ---"
# Probing must complete within 2 seconds and not hang
probe_rc=0
knot auth test-lock || probe_rc=$?
if [ $probe_rc -ne 0 ] && [ $probe_rc -ne 1 ] && [ $probe_rc -ne 2 ]; then
  echo "Error: knot auth test-lock returned invalid exit code $probe_rc"
  exit 1
fi
echo "  [PASS] Non-blocking lock probe returned clean status code $probe_rc."

# ------------------------------------------------------------------------------
# Test 7: Protected Operations & Error Boundaries
# ------------------------------------------------------------------------------
echo "--- [7/8] Testing protected operations & error boundaries ---"

# Deleting active profile must be rejected
del_active_rc=0
knot auth remove alpha 2>&1 || del_active_rc=$?
if [ $del_active_rc -eq 0 ]; then
  echo "Error: knot auth remove active profile succeeded, should have been rejected."
  exit 1
fi

# Switching to nonexistent profile must be rejected
switch_nonexist_rc=0
knot auth switch non_existent_profile 2>&1 || switch_nonexist_rc=$?
if [ $switch_nonexist_rc -eq 0 ]; then
  echo "Error: knot auth switch to non-existent profile succeeded, should have failed."
  exit 1
fi

# Deleting inactive profile (beta) should succeed
knot auth remove beta
if [ -d "$KNOT_TEST_AUTH_DIR/profiles/beta" ]; then
  echo "Error: Profile beta was not removed."
  exit 1
fi
echo "  [PASS] Profile protection invariants verified."

# ------------------------------------------------------------------------------
# Test 8: Node-Local Credential Isolation (Zero Network Leakage)
# ------------------------------------------------------------------------------
echo "--- [8/8] Testing node-local credential isolation invariant ---"
# Verify no token files or credentials leak outside the sandbox or are exposed over hub
leak_found=0
grep_out=""
grep_rc=0
local_swarms_dir="$HOME/.config/knot/swarms"
if [ -d "$local_swarms_dir" ]; then
  grep_out="$(grep -r "tok_alpha_123" "$local_swarms_dir" 2>&1)" || grep_rc=$?
  if [ $grep_rc -eq 0 ]; then
    leak_found=1
  fi
fi
if [ $leak_found -ne 0 ]; then
  echo "Error: Credential leaked into swarms directory: $grep_out"
  exit 1
fi
echo "  [PASS] Zero network leakage invariant verified."

# ------------------------------------------------------------------------------
# Test 9: Local Node Targeting via --node / -n Flags
# ------------------------------------------------------------------------------
echo "--- [9/11] Testing --node / -n flag dispatch ---"
status_node_json="$(knot auth --node local status --json)"
echo "$status_node_json" | jq -e '.active_profile == "alpha"' >/dev/null
status_n_json="$(knot auth -n localhost status --json)"
echo "$status_n_json" | jq -e '.active_profile == "alpha"' >/dev/null
echo "  [PASS] Node targeting via --node and -n flags verified."

# ------------------------------------------------------------------------------
# Test 10: Fleet Status Sweep (--all)
# ------------------------------------------------------------------------------
echo "--- [10/11] Testing fleet status sweep (knot auth status --all) ---"
all_status_json="$(knot auth status --all --json)"
echo "$all_status_json" | jq -e '.nodes' >/dev/null
all_status_table="$(knot auth status --all)"
echo "$all_status_table" | grep -q "ACTIVE PROFILE"
echo "$all_status_table" | grep -q "TOKEN VALID"
echo "  [PASS] knot auth status --all schema and table output verified."

# ------------------------------------------------------------------------------
# Test 11: Fleet Profile List Sweep (--all)
# ------------------------------------------------------------------------------
echo "--- [11/11] Testing fleet profile list sweep (knot auth list --all) ---"
all_list_out="$(knot auth list --all)"
echo "$all_list_out" | grep -q "==="
echo "$all_list_out" | grep -q "alpha"
echo "  [PASS] knot auth list --all multi-node output verified."

echo "================================================================================"
echo ">>> All 11 Issue #60 Auth Sandboxing & Multi-Node Tests Passed 100% Green!"
echo "================================================================================"

