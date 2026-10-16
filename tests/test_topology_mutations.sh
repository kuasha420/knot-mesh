#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Automated Verification Suite for Issue #83
# Declarative Spatial Topology Mutations (link, unlink, remove, set-anchor)
# Verifies:
# 1. CLI help flags (-h, --help) exit 0 across all subcommands
# 2. Valid directional links with automatic reciprocal edge generation
# 3. Fractional sliced spans (e.g. 0-50, 50-100) along same direction without clobbering siblings
# 4. Bounds validation rejection (0 <= MIN < MAX <= 100), negative bounds, malformed delimiters, and state invariance
# 5. Interval interior overlap rejection on source and reciprocal targets with zero state mutation
# 6. Self-link rejection with zero state mutation
# 7. Targeted unlink (specific destination slice) with symmetric reciprocal pruning
# 8. Full unlink (all links on direction) with symmetric reciprocal pruning
# 9. Active anchor removal protection with exact diagnostic error
# 10. Node removal purging screens, layout[node], and incoming references across entire topology
# 11. Set-anchor mutation and validation
# 12. Deskflow server configuration recompilation with explicit screens/links/options directives
# 13. Visual 2D ASCII layout rendering and link descriptor validation (knot topology show)
# 14. PSL Gold Standard: Zero error swallowing, zero || true, strict shell hygiene

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOT_BIN="$REPO_ROOT/bin/knot"

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #83 Declarative Topology Mutations Test Suite"
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

assert_output_contains() {
  local pattern="$1"
  local description="$2"
  shift 2
  local cmd=("$@")

  test_total=$((test_total + 1))
  local actual=0
  local output=""
  output="$("${cmd[@]}" 2>&1)" || actual=$?
  local clean_output
  clean_output="$(printf '%s\n' "$output" | sed -E 's/\x1b\[[0-9;]*[a-zA-Z]//g')"

  if printf '%s\n' "$clean_output" | grep -qF "$pattern"; then
    test_passed=$((test_passed + 1))
    echo "  [PASS] $description (contains '$pattern')"
  else
    echo "  [FAIL] $description (missing '$pattern')"
    echo "         Command: ${cmd[*]}"
    echo "         Output : $output"
    return 1
  fi
}

assert_state_invariant() {
  local description="$1"
  local expected_content="$2"

  test_total=$((test_total + 1))
  local actual_content
  actual_content="$(cat "$TOPO_FILE")"

  if [ "$actual_content" = "$expected_content" ]; then
    test_passed=$((test_passed + 1))
    echo "  [PASS] $description (state invariant)"
  else
    echo "  [FAIL] $description (topology.json modified unexpectedly)"
    diff -u <(printf '%s\n' "$expected_content") <(printf '%s\n' "$actual_content") || [ $? -eq 1 ]
    return 1
  fi
}

assert_reject_with_invariance() {
  local description="$1"
  shift
  local cmd=("$@")

  local state_before
  state_before="$(cat "$TOPO_FILE")"

  assert_exit_code 1 "$description" "${cmd[@]}"
  assert_state_invariant "$description (zero state mutation)" "$state_before"
}

# --- Setup Isolated Hermetic Test Environment ---
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export KNOT_RUNTIME_DIR="$TMP_DIR/run"
export KNOT_ACTIVE_SWARM="testswarm"
SWARM_DIR="$HOME/.config/knot/swarms/testswarm"
NODES_DIR="$SWARM_DIR/nodes"
TOPO_FILE="$SWARM_DIR/topology.json"
DESKFLOW_CFG_DIR="$HOME/.config/Deskflow"

mkdir -p "$NODES_DIR" "$DESKFLOW_CFG_DIR" "$KNOT_RUNTIME_DIR" "$HOME/.local/state/knot"

# Mock node manifests for Deskflow compilation
cat << 'EOF' > "$NODES_DIR/desktop.json"
{
  "id": "desktop",
  "hostname": "arch-desktop",
  "role": "anchor",
  "display": { "resolution": "2560x1440" }
}
EOF

cat << 'EOF' > "$NODES_DIR/laptop.json"
{
  "id": "laptop",
  "hostname": "arch-laptop",
  "role": "strand",
  "display": { "resolution": "1920x1080" }
}
EOF

cat << 'EOF' > "$NODES_DIR/steamdeck.json"
{
  "id": "steamdeck",
  "hostname": "deck-eos",
  "role": "strand",
  "display": { "resolution": "1280x800" }
}
EOF

cat << 'EOF' > "$NODES_DIR/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "ally-arch",
  "role": "strand",
  "display": { "resolution": "1920x1080" }
}
EOF

# Initialize clean base topology
cat << 'EOF' > "$TOPO_FILE"
{
  "anchor": "desktop",
  "screens": [
    "desktop",
    "laptop",
    "steamdeck",
    "rog-ally"
  ],
  "layout": {},
  "locked": false
}
EOF

echo ""
echo "--- 1. CLI Help and Usage Flags (Exit 0 / Exit 1) ---"
assert_exit_code 0 "knot topology -h" "$KNOT_BIN" topology -h
assert_exit_code 0 "knot topology --help" "$KNOT_BIN" topology --help
assert_exit_code 0 "knot topology link -h" "$KNOT_BIN" topology link -h
assert_exit_code 0 "knot topology link --help" "$KNOT_BIN" topology link --help
assert_exit_code 0 "knot topology unlink -h" "$KNOT_BIN" topology unlink -h
assert_exit_code 0 "knot topology unlink --help" "$KNOT_BIN" topology unlink --help
assert_exit_code 0 "knot topology remove -h" "$KNOT_BIN" topology remove -h
assert_exit_code 0 "knot topology remove --help" "$KNOT_BIN" topology remove --help
assert_exit_code 0 "knot topology set-anchor -h" "$KNOT_BIN" topology set-anchor -h
assert_exit_code 0 "knot topology set-anchor --help" "$KNOT_BIN" topology set-anchor --help

# Missing arguments
assert_exit_code 1 "knot topology link (missing args)" "$KNOT_BIN" topology link
assert_exit_code 1 "knot topology unlink (missing args)" "$KNOT_BIN" topology unlink
assert_exit_code 1 "knot topology remove (missing args)" "$KNOT_BIN" topology remove
assert_exit_code 1 "knot topology set-anchor (missing args)" "$KNOT_BIN" topology set-anchor
assert_exit_code 1 "knot topology unknown-sub" "$KNOT_BIN" topology unknown-sub

echo ""
echo "--- 2. Valid Directional Link Creation & Reciprocal Generation ---"
assert_exit_code 0 "knot topology link desktop right laptop" "$KNOT_BIN" topology link desktop right laptop

# Verify link and reciprocal in topology.json
test_total=$((test_total + 1))
link_verified="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert d['layout']['desktop']['right']['node'] == 'laptop', 'desktop.right node mismatch'
assert d['layout']['desktop']['right']['span'] == [0, 100], 'desktop.right span mismatch'
assert d['layout']['desktop']['right']['target_span'] == [0, 100], 'desktop.right target_span mismatch'
assert d['layout']['laptop']['left']['node'] == 'desktop', 'laptop.left reciprocal node mismatch'
assert d['layout']['laptop']['left']['span'] == [0, 100], 'laptop.left reciprocal span mismatch'
assert d['layout']['laptop']['left']['target_span'] == [0, 100], 'laptop.left reciprocal target_span mismatch'
print('OK')
")"
if [ "$link_verified" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Verified forward edge and reciprocal edge in topology.json"
else
  echo "  [FAIL] Link verification failed"
  exit 1
fi

echo ""
echo "--- 3. Link with --no-reciprocal ---"
assert_exit_code 0 "Clean link before no-reciprocal test" "$KNOT_BIN" topology unlink desktop right laptop
assert_exit_code 0 "knot topology link desktop right laptop --no-reciprocal" "$KNOT_BIN" topology link desktop right laptop --no-reciprocal

test_total=$((test_total + 1))
no_recip_verified="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert 'right' in d['layout']['desktop'], 'desktop.right should exist'
assert 'left' not in d['layout'].get('laptop', {}), 'laptop.left reciprocal should NOT exist'
print('OK')
")"
if [ "$no_recip_verified" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Verified forward edge created without reciprocal"
else
  echo "  [FAIL] No-reciprocal verification failed"
  exit 1
fi

echo ""
echo "--- 4. Fractional Sliced Spans (Preserving Sibling Links) ---"
assert_exit_code 0 "Clean right link" "$KNOT_BIN" topology unlink desktop right laptop
assert_exit_code 0 "knot topology link desktop down laptop --span 0-50 --target-span 0-100" "$KNOT_BIN" topology link desktop down laptop --span 0-50 --target-span 0-100
assert_exit_code 0 "knot topology link desktop down steamdeck --span 50-100 --target-span 0-100" "$KNOT_BIN" topology link desktop down steamdeck --span 50-100 --target-span 0-100

test_total=$((test_total + 1))
slices_verified="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
down_links = d['layout']['desktop']['down']
assert isinstance(down_links, list), 'desktop.down must be a list of links'
assert len(down_links) == 2, f'Expected 2 down links, got {len(down_links)}'
assert down_links[0]['node'] == 'laptop' and down_links[0]['span'] == [0, 50], 'Slice 0 mismatch'
assert down_links[1]['node'] == 'steamdeck' and down_links[1]['span'] == [50, 100], 'Slice 1 mismatch'
assert d['layout']['laptop']['up']['node'] == 'desktop' and d['layout']['laptop']['up']['target_span'] == [0, 50], 'Laptop up mismatch'
assert d['layout']['steamdeck']['up']['node'] == 'desktop' and d['layout']['steamdeck']['up']['target_span'] == [50, 100], 'Steamdeck up mismatch'
print('OK')
")"
if [ "$slices_verified" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Verified multiple sliced fractional spans coexist along same edge"
else
  echo "  [FAIL] Sliced spans verification failed"
  exit 1
fi

echo ""
echo "--- 5. Bounds Validation Rejection (0 <= MIN < MAX <= 100) & State Invariance ---"
sec5_before="$(cat "$TOPO_FILE")"
assert_reject_with_invariance "Reject MIN == MAX (50-50)" "$KNOT_BIN" topology link desktop right rog-ally --span 50-50
assert_reject_with_invariance "Reject MIN > MAX (100-0)" "$KNOT_BIN" topology link desktop right rog-ally --span 100-0
assert_reject_with_invariance "Reject negative MIN (-10-50)" "$KNOT_BIN" topology link desktop right rog-ally --span -10-50
assert_reject_with_invariance "Reject MAX > 100 (0-150)" "$KNOT_BIN" topology link desktop right rog-ally --span 0-150
assert_reject_with_invariance "Reject non-numeric span (abc-def)" "$KNOT_BIN" topology link desktop right rog-ally --span abc-def
assert_reject_with_invariance "Reject invalid target-span bounds (50-50)" "$KNOT_BIN" topology link desktop right rog-ally --target-span 50-50
assert_reject_with_invariance "Reject target-span > 100 (0-120)" "$KNOT_BIN" topology link desktop right rog-ally --target-span 0-120
assert_reject_with_invariance "Reject negative target-span (-10-50)" "$KNOT_BIN" topology link desktop right rog-ally --target-span -10-50
assert_reject_with_invariance "Reject inverted target-span (80-20)" "$KNOT_BIN" topology link desktop right rog-ally --target-span 80-20
assert_reject_with_invariance "Reject malformed span without delimiter (50)" "$KNOT_BIN" topology link desktop right rog-ally --span 50
assert_reject_with_invariance "Reject malformed span with multiple delimiters (0-50-100)" "$KNOT_BIN" topology link desktop right rog-ally --span 0-50-100
assert_reject_with_invariance "Reject malformed target-span without delimiter (50)" "$KNOT_BIN" topology link desktop right rog-ally --target-span 50
assert_reject_with_invariance "Reject malformed target-span with multiple delimiters (0-50-100)" "$KNOT_BIN" topology link desktop right rog-ally --target-span 0-50-100
assert_state_invariant "Section 5: State invariant across all bounds rejection tests" "$sec5_before"

echo ""
echo "--- 6. Interval Interior Overlap Rejection & State Invariance ---"
sec6_before="$(cat "$TOPO_FILE")"
# desktop.down currently has [0, 50] and [50, 100]
assert_reject_with_invariance "Reject span overlapping both slices (25-75)" "$KNOT_BIN" topology link desktop down rog-ally --span 25-75
assert_reject_with_invariance "Reject exact duplicate span (0-50)" "$KNOT_BIN" topology link desktop down rog-ally --span 0-50
assert_reject_with_invariance "Reject partial interior overlap (49-60)" "$KNOT_BIN" topology link desktop down rog-ally --span 49-60

# Reciprocal overlap: laptop.up has [0, 100] pointing to desktop
# Linking rog-ally down laptop with target-span 0-100 would overlap on laptop.up
assert_reject_with_invariance "Reject reciprocal interior overlap on target" "$KNOT_BIN" topology link rog-ally down laptop --target-span 0-100
assert_state_invariant "Section 6: State invariant across all interior overlap tests" "$sec6_before"

echo ""
echo "--- 7. Self-Link Rejection & State Invariance ---"
sec7_before="$(cat "$TOPO_FILE")"
assert_reject_with_invariance "Reject linking node to itself" "$KNOT_BIN" topology link desktop left desktop
assert_state_invariant "Section 7: State invariant across self-link rejection test" "$sec7_before"

echo ""
echo "--- 8. Targeted Unlink (Pruning Single Slice & Reciprocal) ---"
# desktop.down has [laptop 0-50, steamdeck 50-100]
assert_exit_code 0 "knot topology unlink desktop down laptop" "$KNOT_BIN" topology unlink desktop down laptop

test_total=$((test_total + 1))
targeted_unlink_verified="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
down_entry = d['layout']['desktop']['down']
assert isinstance(down_entry, dict), 'Single remaining link should be normalized to dict'
assert down_entry['node'] == 'steamdeck', 'Remaining link must be steamdeck'
assert down_entry['span'] == [50, 100], 'Span must be [50, 100]'
assert 'up' not in d['layout'].get('laptop', {}), 'Laptop reciprocal must be pruned'
assert d['layout']['steamdeck']['up']['node'] == 'desktop', 'Steamdeck reciprocal must be preserved'
print('OK')
")"
if [ "$targeted_unlink_verified" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Targeted slice pruned; sibling slice and reciprocal preserved"
else
  echo "  [FAIL] Targeted unlink verification failed"
  exit 1
fi

echo ""
echo "--- 9. Full Unlink (Pruning All Directional Links & Reciprocals) ---"
assert_exit_code 0 "knot topology unlink desktop down" "$KNOT_BIN" topology unlink desktop down

test_total=$((test_total + 1))
full_unlink_verified="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert 'down' not in d['layout']['desktop'], 'desktop.down must be pruned'
assert 'up' not in d['layout'].get('steamdeck', {}), 'steamdeck.up must be pruned'
print('OK')
")"
if [ "$full_unlink_verified" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] All directional links and reciprocals cleanly pruned"
else
  echo "  [FAIL] Full unlink verification failed"
  exit 1
fi

echo ""
echo "--- 10. Unlink Missing Links Rejection ---"
assert_exit_code 1 "Reject unlinking non-existent direction" "$KNOT_BIN" topology unlink desktop down
assert_exit_code 1 "Reject unlinking non-existent target" "$KNOT_BIN" topology unlink desktop left non_existent

echo ""
echo "--- 11. Active Anchor Removal Protection ---"
assert_exit_code 1 "Reject removing active anchor node 'desktop'" "$KNOT_BIN" topology remove desktop
assert_output_contains "Error: Cannot remove active Anchor node 'desktop' from topology." "Verify anchor diagnostic error" "$KNOT_BIN" topology remove desktop

test_total=$((test_total + 1))
anchor_intact="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert d['anchor'] == 'desktop', 'Anchor must remain desktop'
assert 'desktop' in d['screens'], 'desktop must remain in screens'
print('OK')
")"
if [ "$anchor_intact" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Active anchor node was not removed from topology"
else
  echo "  [FAIL] Anchor protection failed"
  exit 1
fi

echo ""
echo "--- 12. Node Removal with Cluster-wide Reference Purging ---"
# Setup links involving laptop
assert_exit_code 0 "Link desktop right laptop" "$KNOT_BIN" topology link desktop right laptop
assert_exit_code 0 "Link laptop down steamdeck --target-span 0-50" "$KNOT_BIN" topology link laptop down steamdeck --target-span 0-50
assert_exit_code 0 "Link desktop down steamdeck --target-span 50-100" "$KNOT_BIN" topology link desktop down steamdeck --target-span 50-100

# Remove laptop
assert_exit_code 0 "knot topology remove laptop" "$KNOT_BIN" topology remove laptop

test_total=$((test_total + 1))
remove_purged="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert 'laptop' not in d['screens'], 'laptop must be removed from screens'
assert 'laptop' not in d['layout'], 'layout.laptop must be deleted'
assert 'right' not in d['layout']['desktop'], 'desktop.right pointing to laptop must be pruned'
assert d['layout']['desktop']['down']['node'] == 'steamdeck', 'desktop.down to steamdeck must be intact'
assert d['layout']['steamdeck']['up']['node'] == 'desktop', 'steamdeck.up to desktop must be intact'
assert d['layout']['steamdeck']['up']['span'] == [50, 100], 'steamdeck.up span must be preserved at [50, 100]'
print('OK')
")"
if [ "$remove_purged" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Node removed and all incoming/outgoing links cluster-wide purged"
else
  echo "  [FAIL] Node remove verification failed"
  exit 1
fi

echo ""
echo "--- 13. Set-Anchor Mutation ---"
assert_exit_code 0 "knot topology set-anchor steamdeck" "$KNOT_BIN" topology set-anchor steamdeck

test_total=$((test_total + 1))
anchor_changed="$(python3 -c "
import json
with open('$TOPO_FILE') as f:
    d = json.load(f)
assert d['anchor'] == 'steamdeck', 'Anchor must be steamdeck'
assert 'steamdeck' in d['screens'], 'steamdeck must be in screens'
print('OK')
")"
if [ "$anchor_changed" = "OK" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Active anchor changed to steamdeck"
else
  echo "  [FAIL] Set-anchor verification failed"
  exit 1
fi

# Verify old anchor desktop can now be removed since steamdeck is anchor
assert_exit_code 0 "knot topology remove desktop" "$KNOT_BIN" topology remove desktop
# Verify new anchor steamdeck cannot be removed
assert_exit_code 1 "Reject removing current active anchor steamdeck" "$KNOT_BIN" topology remove steamdeck

echo ""
echo "--- 14. Deskflow Server Configuration Recompilation ---"
# Setup layout on current anchor steamdeck
assert_exit_code 0 "Link steamdeck left rog-ally" "$KNOT_BIN" topology link steamdeck left rog-ally

test_total=$((test_total + 1))
if [ -f "$DESKFLOW_CFG_DIR/deskflow-server.conf" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] Deskflow server configuration file created"
else
  echo "  [FAIL] deskflow-server.conf not created at $DESKFLOW_CFG_DIR/deskflow-server.conf"
  exit 1
fi

assert_output_contains "section: screens" "Deskflow config contains 'section: screens'" cat "$DESKFLOW_CFG_DIR/deskflow-server.conf"
assert_output_contains "section: links" "Deskflow config contains 'section: links'" cat "$DESKFLOW_CFG_DIR/deskflow-server.conf"
assert_output_contains "left(0,100) = ally-arch(0,100)" "Deskflow config contains 'left(0,100) = ally-arch(0,100)'" cat "$DESKFLOW_CFG_DIR/deskflow-server.conf"
assert_output_contains "right(0,100) = deck-eos(0,100)" "Deskflow config contains 'right(0,100) = deck-eos(0,100)'" cat "$DESKFLOW_CFG_DIR/deskflow-server.conf"
assert_output_contains "section: options" "Deskflow config contains 'section: options'" cat "$DESKFLOW_CFG_DIR/deskflow-server.conf"

echo ""
echo "--- 15. Visual 2D ASCII Layout Rendering (knot topology show) ---"
assert_exit_code 0 "knot topology show exits code 0" "$KNOT_BIN" topology show
assert_output_contains "Knot Multi-Screen Mesh Topology" "Verify header rendered" "$KNOT_BIN" topology show
assert_output_contains "Bidirectional Reciprocal Links" "Verify links rendered" "$KNOT_BIN" topology show
assert_output_contains "steamdeck" "Verify steamdeck anchor node rendered in layout" "$KNOT_BIN" topology show
assert_output_contains "rog-ally" "Verify rog-ally adjacent screen node rendered in layout" "$KNOT_BIN" topology show
assert_output_contains "steamdeck --[left span=0-100% -> rog-ally span=0-100%]--> rog-ally" "Verify directional reciprocal link descriptor rendered" "$KNOT_BIN" topology show

echo ""
echo "--- 16. PSL Gold Standard Integrity & Syntax Verifications ---"
test_total=$((test_total + 1))
bash -n "$REPO_ROOT/core/modules/topology.sh"
bash -n "$REPO_ROOT/bin/knot"
bash -n "${BASH_SOURCE[0]}"
test_passed=$((test_passed + 1))
echo "  [PASS] Bash syntax check passed"

test_total=$((test_total + 1))
python3 -m py_compile "$REPO_ROOT/core/modules/topology_mutate.py"
test_passed=$((test_passed + 1))
echo "  [PASS] Python compilation passed"

echo ""
echo "================================================================================"
echo ">>> Results: $test_passed / $test_total tests passed."
echo "================================================================================"
[ "$test_passed" -eq "$test_total" ]
