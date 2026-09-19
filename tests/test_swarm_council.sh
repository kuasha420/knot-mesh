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
if ! echo "$cli_help" | grep -q "knot council <start|resume|status|reply|list|attach|reconcile"; then
  echo "FAILED (knot council --help missing command signature)"
  exit 1
fi
echo "PASSED"

# 8. Isolated Mesh DB CRUD & Delta Polling
echo -n "8. Testing Mesh DB engine (create, reply, delta, get_thread)... "
test_db="/tmp/test_council_$$.db"
trap 'rm -f "$test_db" "$test_db-wal" "$test_db-shm"' EXIT

create_res="$(python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" create --title "Unit Test Mission" --body "Mission Body" --run-id "test_mesh_$$")"
t_id="$(echo "$create_res" | jq -r '.id')"
t_url="$(echo "$create_res" | jq -r '.url')"
if [ "$t_id" != "test_mesh_$$" ] || [ "$t_url" != "knot://mesh/council/test_mesh_$$" ]; then
  echo "FAILED (Unexpected thread create response: $create_res)"
  exit 1
fi

reply_res="$(python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" reply --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --node-id "desktop" --status "50%" --body "Inspecting chunks")"
if ! echo "$reply_res" | jq -e '.id' >/dev/null; then
  echo "FAILED (Unexpected reply response: $reply_res)"
  exit 1
fi

delta_res="$(python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" poll_delta --discussion-id "test_mesh_$$" --last-count 0)"
delta_cnt="$(echo "$delta_res" | jq -r '.totalCount')"
if [ "$delta_cnt" -ne 1 ]; then
  echo "FAILED (Expected 1 delta comment, got $delta_cnt)"
  exit 1
fi

thread_res="$(python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" get_thread --discussion-id "test_mesh_$$")"
thread_title="$(echo "$thread_res" | jq -r '.title')"
if [ "$thread_title" != "Unit Test Mission" ]; then
  echo "FAILED (Thread title mismatch: $thread_title)"
  exit 1
fi
echo "PASSED"

# 9. Confluence Tiling Layouts, Zero-Token Interactive Mode & Resumption
echo -n "9. Testing Confluence tiling modes & zero-token agy interactive/resume... "
test_run_tiling="unit_test_tiling_$$"
python3 "$COUNCIL_SCRIPTS/confluence.py" --run-id "$test_run_tiling" --nodes desktop,laptop --tiling sidebyside --interactive --dry-run >/dev/null
tiling_conf="$HOME/.config/knot/missions/$test_run_tiling/kitty_session.conf"
if ! grep -q "layout horizontal" "$tiling_conf"; then
  echo "FAILED (Expected layout horizontal for sidebyside in session conf)"
  exit 1
fi
if ! grep -q "Interactive Mode: True" "$tiling_conf"; then
  echo "FAILED (Interactive mode not marked in session conf)"
  exit 1
fi
desktop_pane="$HOME/.config/knot/missions/$test_run_tiling/confluence_desktop.sh"
if grep -q "exec bash -i" "$desktop_pane"; then
  echo "FAILED (Found bare bash in interactive pane script - must be agy TUI)"
  exit 1
fi
if ! grep -q 'exec agy --project "knot-mesh" --dangerously-skip-permissions' "$desktop_pane"; then
  echo "FAILED (Expected zero-token agy invocation without prompt in pane script)"
  exit 1
fi
if grep -q -- ' -i ' "$desktop_pane"; then
  echo "FAILED (Found -i prompt in zero-token interactive pane script)"
  exit 1
fi
rm -rf "$HOME/.config/knot/missions/$test_run_tiling"

# Test resume mode
python3 "$COUNCIL_SCRIPTS/confluence.py" --run-id "$test_run_tiling" --nodes desktop,laptop --tiling tall --interactive --resume --dry-run >/dev/null
if ! grep -q "layout tall" "$tiling_conf"; then
  echo "FAILED (Expected layout tall in session conf)"
  exit 1
fi
if ! grep -q 'exec agy --project "knot-mesh" --dangerously-skip-permissions -c' "$desktop_pane"; then
  echo "FAILED (Expected agy -c in resume pane script)"
  exit 1
fi
rm -rf "$HOME/.config/knot/missions/$test_run_tiling"
echo "PASSED"

# 10. Hermetic Reconciler Report Generation from Mesh DB
echo -n "10. Testing reconciler report generation from Mesh DB... "
python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" reply --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --node-id "desktop" --status "FINAL" --body "All checks passed. READY FOR GA." >/dev/null
python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" reply --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --node-id "laptop" --status "FINAL" --body "CUDA verified. READY FOR GA." >/dev/null

report_out="$(python3 "$COUNCIL_SCRIPTS/reconcile.py" --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --db-backend mesh)"
if ! echo "$report_out" | grep -q "READY FOR GA"; then
  echo "FAILED (Reconciled report missing READY FOR GA verdict)"
  exit 1
fi
if ! echo "$report_out" | grep -Fq '**`desktop`**'; then
  echo "FAILED (Reconciled report missing desktop row)"
  exit 1
fi
echo "PASSED"

# 11. End-to-End knot council start --db mesh --dry-run & reply
echo -n "11. Testing knot council start --db mesh --dry-run and reply... "
dry_out="$("$KNOT_ROOT/bin/knot" council start --db mesh --pack audit-parity --nodes desktop,laptop --dry-run)"
if ! echo "$dry_out" | grep -q "Dry run completed successfully"; then
  echo "FAILED (Dry run execution failed: $dry_out)"
  exit 1
fi
run_id_found="$(echo "$dry_out" | grep -o 'run_[0-9_]*[a-zA-Z0-9]*' | head -n1)"
if [ -n "$run_id_found" ]; then
  "$KNOT_ROOT/bin/knot" council reply "$run_id_found" --node desktop --status "50%" --body "Hermetic dry run reply test" >/dev/null
  status_check="$("$KNOT_ROOT/bin/knot" council status "$run_id_found")"
  if ! echo "$status_check" | grep -q "Hermetic dry run reply test"; then
    echo "FAILED (Reply not reflected in status check)"
    exit 1
  fi
  rm -rf "$HOME/.config/knot/missions/$run_id_found"
  if [ -f "$HOME/.config/knot/hub.db" ]; then
    sqlite3 "$HOME/.config/knot/hub.db" "DELETE FROM council_messages WHERE run_id='$run_id_found';" 2>/dev/null
  fi
fi
echo "PASSED"

# 12. Antigravity Lifecycle Hook Arena Isolation & Turn-1 Gating (council_hook.py)
echo -n "12. Testing council_hook.py arena isolation and Turn-1 gating... "
hook_script="$COUNCIL_SCRIPTS/council_hook.py"

# Case A: Normal developer session (KNOT_COUNCIL_RUN_ID unset) -> must be empty injectSteps
hook_out_normal="$(env -u KNOT_COUNCIL_RUN_ID python3 "$hook_script" <<< '{"invocationNum": 1}')"
if [ "$hook_out_normal" != '{"injectSteps": []}' ]; then
  echo "FAILED (Expected empty injectSteps for normal session, got: $hook_out_normal)"
  exit 1
fi

# Case B: Council session Turn 1 (KNOT_COUNCIL_RUN_ID set, invocationNum=1) -> must inject ephemeralMessage
hook_out_turn1="$(KNOT_COUNCIL_RUN_ID="test_run_hook_$$" KNOT_NODE_ID="desktop" KNOT_PEERS="desktop,laptop" python3 "$hook_script" <<< '{"invocationNum": 1}')"
if ! echo "$hook_out_turn1" | jq -e '.injectSteps[0].ephemeralMessage' >/dev/null; then
  echo "FAILED (Expected ephemeralMessage in Turn 1 hook output: $hook_out_turn1)"
  exit 1
fi
if ! echo "$hook_out_turn1" | grep -Fq '@[desktop]'; then
  echo "FAILED (Missing node id in ephemeralMessage: $hook_out_turn1)"
  exit 1
fi

# Case C: Council session Turn 2 (invocationNum=2) -> must be empty injectSteps (zero repetition)
hook_out_turn2="$(KNOT_COUNCIL_RUN_ID="test_run_hook_$$" KNOT_NODE_ID="desktop" python3 "$hook_script" <<< '{"invocationNum": 2}')"
if [ "$hook_out_turn2" != '{"injectSteps": []}' ]; then
  echo "FAILED (Expected empty injectSteps for Turn 2, got: $hook_out_turn2)"
  exit 1
fi
echo "PASSED"

# 13. Council List Output & Interactive Tagging
echo -n "13. Testing knot council list [filter] and interactive tagging... "
mock_run_interactive="run_unit_interactive_$$"
mkdir -p "$HOME/.config/knot/missions/$mock_run_interactive"
echo "{\"run_id\":\"$mock_run_interactive\",\"project\":\"knot-mesh\",\"db\":\"mesh\",\"interactive\":1,\"status\":\"ACTIVE\",\"nodes\":\"desktop,laptop\"}" > "$HOME/.config/knot/missions/$mock_run_interactive/meta.json"

list_out="$("$KNOT_ROOT/bin/knot" council list interactive)"
if ! echo "$list_out" | grep -q "$mock_run_interactive"; then
  echo "FAILED (knot council list interactive did not find mock run)"
  rm -rf "$HOME/.config/knot/missions/$mock_run_interactive"
  exit 1
fi
if ! echo "$list_out" | grep -q "INTERACTIVE | ACTIVE"; then
  echo "FAILED (knot council list missing INTERACTIVE badge)"
  rm -rf "$HOME/.config/knot/missions/$mock_run_interactive"
  exit 1
fi
rm -rf "$HOME/.config/knot/missions/$mock_run_interactive"
echo "PASSED"

# 14. Symlinked Skill Script Invocations & Global Hook Contract
echo -n "14. Testing symlinked skill scripts and global hooks.json contract... "
symlink_skill_dir="$HOME/.gemini/config/skills/swarm-council/scripts"
if [ -d "$symlink_skill_dir" ]; then
  sym_audit="$(bash "$symlink_skill_dir/audit_tools.sh" kuasha420/knot-mesh)"
  sym_desktop="$(echo "$sym_audit" | jq -r '.nodes.desktop.status // empty')"
  if [ "$sym_desktop" != "READY" ]; then
    echo "FAILED (Symlinked audit_tools.sh did not resolve fleet nodes: $sym_audit)"
    exit 1
  fi

  if [ -f "$HOME/.gemini/config/hooks.json" ]; then
    hook_cmd="$(jq -r '.["swarm-council-coordinator"].PreInvocation[0].command' "$HOME/.gemini/config/hooks.json")"
    hook_test="$(echo '{"invocationNum": 1}' | eval "$hook_cmd")"
    if [ "$hook_test" != '{"injectSteps": []}' ]; then
      echo "FAILED (Global hook failed arena isolation check: $hook_test)"
      exit 1
    fi
  fi
fi
echo "PASSED"

# 15. Multi-Project Portability & Dynamic Codebase Chunking
echo -n "15. Testing dynamic chunking and repo auto-detection on external project... "
purr_dir="/home/kuasha/Dev/purr"
if [ -d "$purr_dir" ]; then
  # Test auto-detection in audit_tools.sh
  purr_audit="$(cd "$purr_dir" && bash "$COUNCIL_SCRIPTS/audit_tools.sh")"
  purr_repo="$(echo "$purr_audit" | jq -r '.target_repo')"
  if [ "$purr_repo" != "kuasha420/purr" ]; then
    echo "FAILED (Expected target_repo kuasha420/purr, got: $purr_repo)"
    exit 1
  fi

  # Test dynamic chunking in scaffolder.py
  purr_scaffold="$(python3 "$COUNCIL_SCRIPTS/scaffolder.py" --project-dir "$purr_dir" --dry-run)"
  purr_cov="$(echo "$purr_scaffold" | jq -r '.actual_coverage')"
  if (( $(echo "$purr_cov < 1.4 || $purr_cov > 1.6" | bc -l) )); then
    echo "FAILED (Actual coverage on purr $purr_cov out of range 1.4-1.6)"
    exit 1
  fi
  # Verify no knot-mesh files leaked into purr chunks
  if echo "$purr_scaffold" | grep -q "Core Runtime & Network Resolution"; then
    echo "FAILED (knot-mesh chunk leaked into external project scaffolding)"
    exit 1
  fi
fi
echo "PASSED"

echo ""
echo "=== All 15 Swarm Council Tests PASSED Successfully! ==="
