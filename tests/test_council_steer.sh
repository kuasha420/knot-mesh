#!/usr/bin/env bash
set -euo pipefail

# Test Suite for Cockpit Bridge Remote (knot council steer)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KNOT_BIN="$KNOT_ROOT/bin/knot"

echo "=== Running Cockpit Bridge Remote (knot council steer) Test Suite ==="

# 1. Argument validation: Missing args
echo -n "1. Testing usage and missing argument validation... "
out=""
set +e
out="$("$KNOT_BIN" council steer 2>&1)"
rc=$?
set -e
if [ $rc -eq 0 ]; then
  echo "FAILED (Expected non-zero exit code when called with no arguments)"
  exit 1
fi
if [[ "$out" != *"Usage: knot council steer"* ]]; then
  echo "FAILED (Usage string not returned: $out)"
  exit 1
fi
echo "PASSED"

# 2. Socket missing error handling
echo -n "2. Testing missing Kitty control socket reporting... "
set +e
out="$("$KNOT_BIN" council steer laptop "test prompt" "nonexistent_run_12345" 2>&1)"
rc=$?
set -e
if [ $rc -eq 0 ]; then
  echo "FAILED (Expected failure when socket does not exist)"
  exit 1
fi
if [[ "$out" != *"Kitty control socket not found"* ]]; then
  echo "FAILED (Expected socket error message, got: $out)"
  exit 1
fi
echo "PASSED"

# 3. Core pack scaffolding verification
echo -n "3. Testing audit-parity pack prompt scaffolding... "
scaffold_json="$(python3 "$KNOT_ROOT/runtime/skills/swarm-council/scripts/scaffolder.py" --pack audit-parity --dry-run)"
pack_name="$(echo "$scaffold_json" | jq -r '.pack')"
if [ "$pack_name" != "audit-parity" ]; then
  echo "FAILED (Expected pack 'audit-parity', got '$pack_name')"
  exit 1
fi
has_desktop="$(echo "$scaffold_json" | jq -r '.prompts_generated.desktop.preview_len')"
if [ -z "$has_desktop" ] || [ "$has_desktop" -le 0 ]; then
  echo "FAILED (Desktop audit-parity prompt not generated)"
  exit 1
fi
echo "PASSED"

# 4. Council hook dynamic role resolution verification
echo -n "4. Testing council hook dynamic role resolution... "
hook_test="$(python3 -c "
import sys
sys.path.insert(0, '$KNOT_ROOT/runtime/skills/swarm-council/scripts')
from council_hook import resolve_node_role

role = resolve_node_role('desktop')
assert role == 'Mesh Anchor & Coordinator', f'Expected Mesh Anchor & Coordinator, got {role}'
fallback_role = resolve_node_role('unknown-node')
assert fallback_role == 'Strand Worker', f'Expected Strand Worker, got {fallback_role}'
print('OK')
")"

if [ "$hook_test" != "OK" ]; then
  echo "FAILED (Council hook dynamic role resolution failed)"
  exit 1
fi
echo "PASSED"

# 5. Confluence Kitty session remote control config verification
echo -n "5. Testing confluence.py remote control socket configuration... "
conf_test="$(python3 -c "
import sys, os
sys.path.insert(0, '$KNOT_ROOT/runtime/skills/swarm-council/scripts')
from confluence import generate_session_conf

conf = generate_session_conf(
    run_id='test_run_123',
    nodes=['desktop', 'laptop'],
    missions_dir='/tmp',
    knot_root='$KNOT_ROOT',
    project_name='knot-mesh',
    tiling='grid',
    interactive=True
)

assert 'title' in conf, 'Session config should configure pane titles'
assert 'desktop' in conf, 'Session config should include desktop'
assert 'laptop' in conf, 'Session config should include laptop'
print('OK')
")"

if [ "$conf_test" != "OK" ]; then
  echo "FAILED (Confluence session config failed)"
  exit 1
fi
echo "PASSED"

echo "=== All Cockpit Bridge Remote Tests PASSED ==="
