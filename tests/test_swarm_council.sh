#!/usr/bin/env bash
set -euo pipefail

# Automated Test Suite for Swarm Council Engine

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COUNCIL_SCRIPTS="$KNOT_ROOT/runtime/skills/swarm-council/scripts"

echo "=== Running Swarm Council Test Suite ==="

# 1. Zero Error Swallowing Audit
echo -n "1. Auditing codebase for zero error swallowing (PSL Rule 1)... "
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
if ! python3 -c "import sys; cov = float('$actual_cov'); sys.exit(0 if 1.4 <= cov <= 1.6 else 1)"; then
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
desktop_pane="$HOME/.config/knot/missions/$test_run_id/confluence_desktop.sh"
if [ ! -f "$desktop_pane" ] || ! grep -q "sleep 5 || break" "$desktop_pane"; then
  echo "FAILED (Missing persistent reconnection supervisor loop in $desktop_pane)"
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
if ! grep -q 'agy --project "knot-mesh" --dangerously-skip-permissions' "$desktop_pane"; then
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
if ! grep -q 'agy --project "knot-mesh" --dangerously-skip-permissions -c' "$desktop_pane"; then
  echo "FAILED (Expected agy -c in resume pane script)"
  exit 1
fi
rm -rf "$HOME/.config/knot/missions/$test_run_tiling"
echo "PASSED"

# 10. Hermetic Reconciler Report Generation from Mesh DB
echo -n "10. Testing reconciler report generation from Mesh DB... "
python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" reply --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --node-id "desktop" --status "FINAL" --body "All checks passed. READY FOR GA." >/dev/null
python3 "$COUNCIL_SCRIPTS/mesh_db.py" --db-path "$test_db" reply --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --node-id "laptop" --status "FINAL" --body "CUDA verified. READY FOR GA." >/dev/null

report_out="$(python3 "$COUNCIL_SCRIPTS/reconcile.py" --discussion-id "test_mesh_$$" --run-id "test_mesh_$$" --db-backend mesh --db-path "$test_db")"
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
    sqlite3 "$HOME/.config/knot/hub.db" "DELETE FROM council_messages WHERE run_id='$run_id_found';"
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
    hook_test="$(echo '{"invocationNum": 1}' | env -u KNOT_COUNCIL_RUN_ID bash -c "$hook_cmd")"
    if [ "$hook_test" != '{"injectSteps": []}' ]; then
      echo "FAILED (Global hook failed arena isolation check: $hook_test)"
      exit 1
    fi
  fi
fi
echo "PASSED"

# 15. Multi-Project Portability & Dynamic Codebase Chunking
echo -n "15. Testing dynamic chunking and repo auto-detection on external project... "
purr_dir="${PURR_DIR:-$HOME/Dev/purr}"
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
  if ! python3 -c "import sys; cov = float('$purr_cov'); sys.exit(0 if 1.4 <= cov <= 1.6 else 1)"; then
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

# 16. Dynamic Node Identifier Resolution & Active Tournament Server Delivery
echo -n "16. Testing dynamic node resolution & active tournament server delivery... "
resolved_nid="$(python3 "$COUNCIL_SCRIPTS/resolve_node.py")"
if [ -z "$resolved_nid" ]; then
  echo "FAILED (Empty node id from resolve_node.py)"
  exit 1
fi

ring_test="$(python3 -c '
import sys; sys.path.insert(0, "runtime/skills/swarm-council/scripts")
from scaffolder import build_tournament_ring
nodes = ["laptop", "rog-ally", "steamdeck", "desktop"]
ring = build_tournament_ring(nodes)
print(",".join(ring))
')"
first_ring_node="$(echo "$ring_test" | cut -d',' -f1)"
if [ "$first_ring_node" != "$resolved_nid" ]; then
  echo "FAILED (Expected first ring node to be $resolved_nid, got $first_ring_node)"
  exit 1
fi

# Test tournament launcher delivery for active server vs standby
test_tourn_run="unit_test_tourn_$$"
mkdir -p "$HOME/.config/knot/missions/$test_tourn_run"
trap 'rm -rf "$HOME/.config/knot/missions/$test_tourn_run"' EXIT

python3 "$COUNCIL_SCRIPTS/scaffolder.py" --run-id "$test_tourn_run" --pack tournament --db mesh --nodes "$resolved_nid,mock-peer" --project-dir "$KNOT_ROOT" >/dev/null

meta_tourn="$HOME/.config/knot/missions/$test_tourn_run/meta.json"
meta_opening="$(jq -r '.opening_node // empty' "$meta_tourn")"
if [ "$meta_opening" != "$resolved_nid" ]; then
  echo "FAILED (Opening node in meta.json is $meta_opening, expected $resolved_nid)"
  exit 1
fi

# Stage delivery without launching
LAUNCH=0 bash "$COUNCIL_SCRIPTS/deliver.sh" confluence "$test_tourn_run" "knot-mesh" grid 0 "$resolved_nid,mock-peer" 0 0 >/dev/null

active_launch="$HOME/.config/knot/missions/$test_tourn_run/${resolved_nid}_launch.sh"
peer_launch="$HOME/.config/knot/missions/$test_tourn_run/mock-peer_launch.sh"

if [ ! -f "$active_launch" ] || [ ! -f "$peer_launch" ]; then
  echo "FAILED (Launch scripts not generated)"
  exit 1
fi

if ! grep -q -- '-i "\$(< "\$PROMPT_FILE")"' "$active_launch"; then
  echo "FAILED (Active opening server launcher missing prompt execution flag - was generated in Standby!)"
  exit 1
fi

if ! grep -q "Zero-Token Standby" "$peer_launch"; then
  echo "FAILED (Peer node launcher not generated in Zero-Token Standby mode)"
  exit 1
fi

rm -rf "$HOME/.config/knot/missions/$test_tourn_run"
echo "PASSED"

# 17. Cryptographic Challenge Tool (knot council challenge)
echo -n "17. Testing knot council challenge (generate, verify, solve)... "
gen_out="$("$KNOT_ROOT/bin/knot" council challenge generate --difficulty 3 --keyword TEST --prefix KNOT-UNIT)"
if ! echo "$gen_out" | grep -q "Target: Find a string starting with 'KNOT-UNIT-'"; then
  echo "FAILED (Challenge generate format unexpected: $gen_out)"
  exit 1
fi

solve_out="$(python3 "$COUNCIL_SCRIPTS/challenge_tool.py" solve --difficulty 3 --keyword TEST --prefix KNOT-UNIT)"
if ! echo "$solve_out" | grep -q "\[✓\] SOLVED"; then
  echo "FAILED (Challenge solve failed: $solve_out)"
  exit 1
fi
solved_str="$(echo "$solve_out" | grep -o "String='[^']*'" | cut -d"'" -f2)"

ver_out="$("$KNOT_ROOT/bin/knot" council challenge verify --string "$solved_str" --difficulty 3 --keyword TEST)"
if ! echo "$ver_out" | grep -q "\[✓\] VALID"; then
  echo "FAILED (Challenge verify failed for valid solution: $ver_out)"
  exit 1
fi

if "$KNOT_ROOT/bin/knot" council challenge verify --string "INVALID_NONCE" --difficulty 3 --keyword TEST 2>&1 | grep -q "\[✓\] VALID"; then
  echo "FAILED (Challenge verify succeeded on invalid candidate)"
  exit 1
fi
echo "PASSED"

# 18. Mesh DB CLI Ergonomics (knot council db inspect, tail)
echo -n "18. Testing knot council db (inspect, tail)... "
inspect_out="$("$KNOT_ROOT/bin/knot" council db inspect "test_mesh_$$")"
if ! echo "$inspect_out" | jq -e '.comments.totalCount >= 2' >/dev/null; then
  echo "FAILED (Inspect output missing expected comments count: $inspect_out)"
  exit 1
fi

tail_out="$("$KNOT_ROOT/bin/knot" council db tail "test_mesh_$$" --limit 5)"
if ! echo "$tail_out" | grep -q "@desktop"; then
  echo "FAILED (Tail output missing comments: $tail_out)"
  exit 1
fi
echo "PASSED"

# 19. Steer Option Validation
echo -n "19. Testing knot council steer argument validation... "
usage_out=""
if ! usage_out="$("$KNOT_ROOT/bin/knot" council steer 2>&1)"; then
  : # Expected non-zero exit code for missing arguments
fi
if ! echo "$usage_out" | grep -q "Usage: knot council steer"; then
  echo "FAILED (Steer missing usage instructions: $usage_out)"
  exit 1
fi
echo "PASSED"

# 20. Cockpit Self-Healing & Topology Guard (knot council heal)
echo -n "20. Testing knot council heal in mock Kitty environment... "
heal_test_run="test_heal_$$"
heal_missions_dir="$HOME/.config/knot/missions/$heal_test_run"
mkdir -p "$heal_missions_dir"
mock_sock="/tmp/test_kitty_sock_$$.sock"
python3 -c "import socket; s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind('$mock_sock')"

cat <<EOF > "$heal_missions_dir/meta.json"
{
  "run_id": "$heal_test_run",
  "nodes": "desktop,laptop,rog-ally",
  "socket": "$mock_sock",
  "status": "ACTIVE"
}
EOF

echo '#!/usr/bin/env bash' > "$heal_missions_dir/confluence_desktop.sh"
echo '#!/usr/bin/env bash' > "$heal_missions_dir/confluence_laptop.sh"
echo '#!/usr/bin/env bash' > "$heal_missions_dir/confluence_rog-ally.sh"
chmod +x "$heal_missions_dir"/confluence_*.sh

cat <<EOF > "$heal_missions_dir/kitty_session.conf"
title 🟣 desktop (Anchor)
launch $heal_missions_dir/confluence_desktop.sh
title 🔵 laptop (Worker)
launch $heal_missions_dir/confluence_laptop.sh
title 🔴 rog-ally (Worker)
launch $heal_missions_dir/confluence_rog-ally.sh
EOF

mock_bin_dir="/tmp/mock_bin_$$"
mkdir -p "$mock_bin_dir"
mock_log="/tmp/mock_kitty_heal_$$.log"
rm -f "$mock_log"

cat <<'EOF' > "$mock_bin_dir/kitty"
#!/usr/bin/env bash
if [ "${1:-}" = "@" ]; then
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) shift 2 ;;
      ls)
        echo '[{"tabs": [{"windows": [{"id": 1, "title": "🟣 desktop (Anchor)"}, {"id": 2, "title": "🔵 laptop (Worker)"}]}]}]'
        exit 0
        ;;
      launch)
        shift
        echo "LAUNCH: $*" >> "$MOCK_LOG"
        exit 0
        ;;
      *)
        shift
        ;;
    esac
  done
fi
exit 1
EOF
chmod +x "$mock_bin_dir/kitty"

heal_out="$(MOCK_LOG="$mock_log" PATH="$mock_bin_dir:$PATH" "$KNOT_ROOT/bin/knot" council heal "$heal_test_run")"

if ! echo "$heal_out" | grep -q "Restored pane for @\[rog-ally\] in cockpit"; then
  echo "FAILED (knot council heal did not report restoring rog-ally: $heal_out)"
  rm -rf "$heal_missions_dir" "$mock_bin_dir" "$mock_sock" "$mock_log"
  exit 1
fi

if [ ! -f "$mock_log" ] || ! grep -q "confluence_rog-ally.sh" "$mock_log"; then
  echo "FAILED (Mock kitty did not receive launch call for confluence_rog-ally.sh)"
  rm -rf "$heal_missions_dir" "$mock_bin_dir" "$mock_sock" "$mock_log"
  exit 1
fi

rm -rf "$heal_missions_dir" "$mock_bin_dir" "$mock_sock" "$mock_log"
echo "PASSED"

echo ""
echo "=== All 20 Swarm Council Tests PASSED Successfully! ==="
