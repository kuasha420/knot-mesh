#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Automated Verification Suite for Issue #70
# Normalization of -h and --help exit codes to 0 across all subcommands
# Verification of exit code 1 on invalid subcommands
# PSL Gold Standard: Zero error swallowing, zero || true, strict type/shell hygiene

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOT_BIN="$REPO_ROOT/bin/knot"

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #70 CLI Help & Exit Code Verification Suite"
echo "================================================================================"

test_passed=0
test_total=0

assert_exit_code() {
  local expected="$1"
  local description="$2"
  shift 2
  local cmd=("$@")
  
  test_total=$((test_total + 1))
  local actual=0
  local output=""
  output="$("${cmd[@]}" 2>&1)" || actual=$?

  if [ "$actual" -eq "$expected" ]; then
    test_passed=$((test_passed + 1))
    echo "  [PASS] $description (exit $actual, expected $expected)"
  else
    echo "  [FAIL] $description (exit $actual, expected $expected)"
    echo "         Command: ${cmd[*]}"
    echo "         Output : $output"
    return 1
  fi
}

echo ""
echo "--- 1. Root Command Help & Default Invocation (Exit 0) ---"
assert_exit_code 0 "knot (bare invocation)" "$KNOT_BIN"
assert_exit_code 0 "knot -h" "$KNOT_BIN" -h
assert_exit_code 0 "knot --help" "$KNOT_BIN" --help
assert_exit_code 0 "knot help" "$KNOT_BIN" help
assert_exit_code 0 "knot -v" "$KNOT_BIN" -v
assert_exit_code 0 "knot --version" "$KNOT_BIN" --version
assert_exit_code 0 "knot version" "$KNOT_BIN" version

echo ""
echo "--- 2. Subcommands Help: -h and --help (Exit 0) ---"
SUBCOMMANDS=(
  "onboard"
  "update"
  "sync"
  "resolve"
  "status"
  "exec"
  "kvm"
  "screen"
  "unlock"
  "lock"
  "login"
  "autologin"
  "kdeconnect"
  "display"
  "council"
  "swarm"
  "color"
  "quota"
  "auth"
  "hub"
  "agent"
  "task"
  "project"
  "worktree"
  "chat"
  "artifact"
  "sleep"
  "kafe"
  "web"
  "memory"
  "doctor"
  "repair"
  "restart"
  "shutdown"
  "reboot"
  "topology"
  "mcp"
)

for sub in "${SUBCOMMANDS[@]}"; do
  assert_exit_code 0 "knot $sub -h" "$KNOT_BIN" "$sub" -h
  assert_exit_code 0 "knot $sub --help" "$KNOT_BIN" "$sub" --help
done

echo ""
echo "--- 3. Nested Subcommand Help (Exit 0) ---"
NESTED_COMMANDS=(
  "council start"
  "council steer"
  "council status"
  "council reply"
  "council db"
  "council list"
  "council resume"
  "council attach"
  "council reconcile"
  "council kill"
  "council heal"
  "council clean"
  "council copy"
  "swarm switch"
  "swarm exec"
  "swarm test"
  "kdeconnect vmon"
  "auth login"
  "auth import"
  "auth switch"
  "auth remove"
  "auth status"
  "auth list"
  "worktree add"
  "worktree remove"
  "worktree list"
  "worktree normalize"
  "worktree provision"
  "topology show"
  "topology refresh"
  "topology align-internal"
  "topology identify"
  "screen unlock"
  "screen lock"
  "screen login"
  "screen status"
)

for nested in "${NESTED_COMMANDS[@]}"; do
  # shellcheck disable=SC2086
  assert_exit_code 0 "knot $nested -h" "$KNOT_BIN" $nested -h
  # shellcheck disable=SC2086
  assert_exit_code 0 "knot $nested --help" "$KNOT_BIN" $nested --help
done

echo ""
echo "--- 4. Invalid Commands & Subcommands (Exit 1) ---"
assert_exit_code 1 "knot unknown-root-cmd" "$KNOT_BIN" unknown-root-cmd
assert_exit_code 1 "knot council unknown-action" "$KNOT_BIN" council unknown-action
assert_exit_code 1 "knot swarm unknown-action" "$KNOT_BIN" swarm unknown-action
assert_exit_code 1 "knot kdeconnect unknown-action" "$KNOT_BIN" kdeconnect unknown-action
assert_exit_code 1 "knot kdeconnect vmon unknown-action" "$KNOT_BIN" kdeconnect vmon unknown-action
assert_exit_code 1 "knot display unknown-action" "$KNOT_BIN" display unknown-action
assert_exit_code 1 "knot screen unknown-action" "$KNOT_BIN" screen unknown-action
assert_exit_code 1 "knot worktree unknown-action" "$KNOT_BIN" worktree unknown-action
assert_exit_code 1 "knot hub unknown-action" "$KNOT_BIN" hub unknown-action
assert_exit_code 1 "knot agent unknown-action" "$KNOT_BIN" agent unknown-action
assert_exit_code 1 "knot task unknown-action" "$KNOT_BIN" task unknown-action
assert_exit_code 1 "knot project unknown-action" "$KNOT_BIN" project unknown-action
assert_exit_code 1 "knot chat unknown-action" "$KNOT_BIN" chat unknown-action
assert_exit_code 1 "knot artifact unknown-action" "$KNOT_BIN" artifact unknown-action
assert_exit_code 1 "knot kafe unknown-action" "$KNOT_BIN" kafe unknown-action
assert_exit_code 1 "knot sleep unknown-action" "$KNOT_BIN" sleep unknown-action
assert_exit_code 1 "knot restart unknown-target" "$KNOT_BIN" restart unknown-target
assert_exit_code 1 "knot topology unknown-sub" "$KNOT_BIN" topology unknown-sub

echo ""
echo "--- 5. Unknown Flags (Exit 1) ---"
assert_exit_code 1 "knot --unknown-flag" "$KNOT_BIN" --unknown-flag
assert_exit_code 1 "knot council --unknown-flag" "$KNOT_BIN" council --unknown-flag
assert_exit_code 1 "knot worktree --unknown-flag" "$KNOT_BIN" worktree --unknown-flag
assert_exit_code 1 "knot auth --unknown-flag" "$KNOT_BIN" auth --unknown-flag
assert_exit_code 1 "knot mcp --unknown-flag" "$KNOT_BIN" mcp --unknown-flag
assert_exit_code 1 "knot swarm --unknown-flag" "$KNOT_BIN" swarm --unknown-flag
assert_exit_code 1 "knot display --unknown-flag" "$KNOT_BIN" display --unknown-flag
assert_exit_code 1 "knot kdeconnect --unknown-flag" "$KNOT_BIN" kdeconnect --unknown-flag

echo ""
echo "================================================================================"
echo ">>> Results: $test_passed / $test_total tests passed."
echo "================================================================================"
[ "$test_passed" -eq "$test_total" ]
