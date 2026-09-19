#!/usr/bin/env bash
set -euo pipefail

# Automated Test Suite for Swarm Council Engine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COUNCIL_SCRIPTS="$KNOT_ROOT/skills/swarm-council/scripts"

echo "=== Running Swarm Council Test Suite ==="

# 1. Zero Error Swallowing Audit
echo -n "1. Auditing codebase for zero error swallowing (Rule 02)... "
if grep -rn '|| true' "$COUNCIL_SCRIPTS" "$KNOT_ROOT/core/modules/council.sh"; then
  echo "FAILED (Found || true in council engine)"
  exit 1
fi
echo "PASSED"

# 2. Audit Tools Execution
echo -n "2. Testing Stage 0 tool audit script... "
audit_out="$(bash "$COUNCIL_SCRIPTS/audit_tools.sh" kuasha420/knot-mesh)"
target_repo="$(echo "$audit_out" | jq -r '.target_repo')"
if [ "$target_repo" != "kuasha420/knot-mesh" ]; then
  echo "FAILED (Target repo mismatch: $target_repo)"
  exit 1
fi
node_status="$(echo "$audit_out" | jq -r '.nodes.desktop.status // .nodes[keys[0]].status')"
if [ "$node_status" != "READY" ]; then
  echo "FAILED (Node status not READY: $node_status)"
  exit 1
fi
echo "PASSED"

# 3. Dynamic Project Discovery
echo -n "3. Testing Stage 1 dynamic project discovery... "
sync_out="$(cd "$KNOT_ROOT" && bash "$COUNCIL_SCRIPTS/project_sync.sh")"
proj_name="$(echo "$sync_out" | jq -r '.project_name')"
if [ "$proj_name" != "knot-mesh" ]; then
  echo "FAILED (Expected project_name knot-mesh, got $proj_name)"
  exit 1
fi
folder_count="$(echo "$sync_out" | jq -r '.folders | length')"
if [ "$folder_count" -lt 1 ]; then
  echo "FAILED (Expected at least 1 discovered folder, got $folder_count)"
  exit 1
fi
echo "PASSED"

# 4. Scaffolder 1.5x Coverage Calculation
echo -n "4. Testing Stage 3 prompt scaffolder 1.5x coverage... "
scaffold_out="$(python3 "$COUNCIL_SCRIPTS/scaffolder.py" --dry-run --nodes desktop,laptop,rog-ally,steamdeck --coverage 1.5)"
actual_cov="$(echo "$scaffold_out" | jq -r '.actual_coverage')"
if (( $(echo "$actual_cov < 1.4 || $actual_cov > 1.6" | bc -l) )); then
  echo "FAILED (Actual coverage $actual_cov out of range 1.4-1.6)"
  exit 1
fi
echo "PASSED (Coverage: ${actual_cov}x)"

# 5. Dual Ensemble Classifier
echo -n "5. Testing Stage 4 dual ensemble classifier... "
class_audit="$(python3 "$COUNCIL_SCRIPTS/classifier.py" --prompt "Audit all nodes across fleet with parallel coverage" --json)"
s_mode_audit="$(echo "$class_audit" | jq -r '.suggested_mode')"
if [ "$s_mode_audit" != "confluence" ]; then
  echo "FAILED (Expected confluence for multi-node audit, got $s_mode_audit)"
  exit 1
fi

class_ui="$(python3 "$COUNCIL_SCRIPTS/classifier.py" --prompt "Create Tailwind CSS frontend dashboard with Glassmorphism" --json)"
s_mode_ui="$(echo "$class_ui" | jq -r '.suggested_mode')"
if [ "$s_mode_ui" != "gui" ]; then
  echo "FAILED (Expected gui for UI design, got $s_mode_ui)"
  exit 1
fi

class_cron="$(python3 "$COUNCIL_SCRIPTS/classifier.py" --prompt "Run unattended nightly batch regression at midnight" --json)"
s_mode_cron="$(echo "$class_cron" | jq -r '.suggested_mode')"
if [ "$s_mode_cron" != "headless" ]; then
  echo "FAILED (Expected headless for unattended nightly, got $s_mode_cron)"
  exit 1
fi
echo "PASSED"

# 6. Confluence Session Layout Generation
echo -n "6. Testing Stage 5 Confluence session config generator... "
test_run_id="unit_test_run_$$"
python3 "$COUNCIL_SCRIPTS/confluence.py" --run-id "$test_run_id" --nodes desktop,laptop,rog-ally,steamdeck --dry-run >/dev/null
session_file="$HOME/.config/knot/missions/$test_run_id/kitty_session.conf"
if [ ! -f "$session_file" ]; then
  echo "FAILED (Session file not created at $session_file)"
  exit 1
fi
if ! grep -q -E "layout (splits|grid)" "$session_file"; then
  echo "FAILED (Missing layout grid or splits in session file)"
  exit 1
fi
if ! grep -q "trap '' HUP" "$session_file"; then
  echo "FAILED (Missing SIGHUP protection trap in session file)"
  exit 1
fi
rm -rf "$HOME/.config/knot/missions/$test_run_id"
echo "PASSED"

# 7. First-Class knot council CLI Integration
echo -n "7. Testing knot council CLI integration... "
cli_help="$("$KNOT_ROOT/bin/knot" council --help)"
if ! echo "$cli_help" | grep -q "knot council <start|status|attach|reconcile"; then
  echo "FAILED (knot council --help missing command signature)"
  exit 1
fi
echo "PASSED"

echo ""
echo "=== All Swarm Council Tests PASSED Successfully! ==="
