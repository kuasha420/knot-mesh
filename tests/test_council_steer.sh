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

# 3. Tournament pack scaffolding verification
echo -n "3. Testing tournament pack prompt scaffolding... "
scaffold_json="$(python3 "$KNOT_ROOT/skills/swarm-council/scripts/scaffolder.py" --pack tournament --dry-run)"
pack_name="$(echo "$scaffold_json" | jq -r '.pack')"
if [ "$pack_name" != "tournament" ]; then
  echo "FAILED (Expected pack 'tournament', got '$pack_name')"
  exit 1
fi
has_desktop="$(echo "$scaffold_json" | jq -r '.prompts_generated.desktop.preview_len')"
if [ -z "$has_desktop" ] || [ "$has_desktop" -le 0 ]; then
  echo "FAILED (Desktop tournament prompt not generated)"
  exit 1
fi
echo "PASSED"

# 4. Tournament referee syntax and calculation verification
echo -n "4. Testing tournament referee points calculation... "
referee_test="$(python3 -c "
import sys
sys.path.insert(0, '$KNOT_ROOT/skills/swarm-council/scripts')
from tournament_referee import calculate_volley_points, verify_proof

pts, ace, smash, elegance = calculate_volley_points(4200.0, True)
assert smash == True, 'Should be smash (<5s)'
assert pts == 250, f'Expected 250 pts, got {pts}'

pts2, ace2, smash2, elegance2 = calculate_volley_points(8200.0, False)
assert ace2 == True, 'Should be ace (<10s)'
assert smash2 == False
assert pts2 == 150, f'Expected 150 pts, got {pts2}'

assert verify_proof('test_proof', 'd3f0') == True, 'SHA256 verify failed'
print('OK')
")"

if [ "$referee_test" != "OK" ]; then
  echo "FAILED (Referee points calculation failed)"
  exit 1
fi
echo "PASSED"

# 5. Confluence Kitty session remote control config verification
echo -n "5. Testing confluence.py remote control socket configuration... "
conf_test="$(python3 -c "
import sys, os
sys.path.insert(0, '$KNOT_ROOT/skills/swarm-council/scripts')
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
