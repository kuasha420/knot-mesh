#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Subagent Ladder Skill Automated Verification Suite
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SKILL_DIR="$KNOT_ROOT/runtime/skills/subagent-ladder"
WORKSPACE_SKILL="$KNOT_ROOT/.agents/skills/subagent-ladder"

echo "=== [Test 1] Syntax & Zero Error Swallowing Verification ==="
# Verify python compilation
python3 -m py_compile "$SKILL_DIR/scripts/bridge_artifacts.py"
python3 -m py_compile "$SKILL_DIR/scripts/scaffold_ladder.py"
python3 -m py_compile "$SKILL_DIR/scripts/verify_ladder_state.py"
echo "  -> Python scripts compile successfully: OK"

# Check for forbidden error swallowing in runtime/skills/subagent-ladder
if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$SKILL_DIR"/scripts/*.py; then
  echo "Error: Detected forbidden error swallowing patterns in subagent-ladder scripts!" >&2
  exit 1
fi
echo "  -> Zero error swallowing in subagent-ladder: OK"

echo "=== [Test 2] Workspace Symlink & Packaging Integrity ==="
if [ ! -L "$WORKSPACE_SKILL" ]; then
  echo "Error: Workspace skill symlink $WORKSPACE_SKILL does not exist or is not a symlink!" >&2
  exit 1
fi

target_path="$(readlink -f "$WORKSPACE_SKILL")"
if [ "$target_path" != "$SKILL_DIR" ]; then
  echo "Error: Symlink target mismatch: $target_path != $SKILL_DIR" >&2
  exit 1
fi

# Verify frontmatter in workspace skill
if ! grep -q "name: subagent-ladder" "$WORKSPACE_SKILL/SKILL.md"; then
  echo "Error: SKILL.md missing 'name: subagent-ladder' frontmatter!" >&2
  exit 1
fi
if ! grep -q "Strictly user-invoked" "$WORKSPACE_SKILL/SKILL.md"; then
  echo "Error: SKILL.md missing strictly user-invoked contract!" >&2
  exit 1
fi
echo "  -> Workspace skill symlink and frontmatter: OK"

echo "=== [Test 3] Helper Script Functionality ==="
TMP_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT

# Test bridge_artifacts.py in isolated directory
mkdir -p "$TMP_TEST_DIR/repo/.agents"
mkdir -p "$TMP_TEST_DIR/brain"
touch "$TMP_TEST_DIR/brain/test_plan.md"
echo ".agents/artifacts" > "$TMP_TEST_DIR/repo/.gitignore"

python3 "$SKILL_DIR/scripts/bridge_artifacts.py" --setup "$TMP_TEST_DIR/brain" --root "$TMP_TEST_DIR/repo"
python3 "$SKILL_DIR/scripts/bridge_artifacts.py" --check --root "$TMP_TEST_DIR/repo"
python3 "$SKILL_DIR/scripts/bridge_artifacts.py" --clean --root "$TMP_TEST_DIR/repo"
echo "  -> bridge_artifacts.py --setup, --check, --clean: OK"

# Test scaffold_ladder.py outputs
exec_json="$(python3 "$SKILL_DIR/scripts/scaffold_ladder.py" --phase 1 --role executioner)"
echo "$exec_json" | grep -q '"Role": "subagent-1-executioner"'

hammer_json="$(python3 "$SKILL_DIR/scripts/scaffold_ladder.py" --phase 2 --role hammer)"
echo "$hammer_json" | grep -q '"Role": "subagent-2-hammer"'

auditor_json="$(python3 "$SKILL_DIR/scripts/scaffold_ladder.py" --phase 3 --role auditor)"
echo "$auditor_json" | grep -q '"Role": "subagent-3-auditor"'

all_json="$(python3 "$SKILL_DIR/scripts/scaffold_ladder.py" --phase 4 --role all)"
echo "$all_json" | grep -q '"phase": 4'
echo "  -> scaffold_ladder.py payload generation: OK"

# Test verify_ladder_state.py on synthetic logs
CLEAN_LOG="$TMP_TEST_DIR/clean_transcript.jsonl"
cat << 'EOF' > "$CLEAN_LOG"
{"step_index": 0, "created_at": "2026-09-21T01:00:00Z", "tool_calls": [{"name": "invoke_subagent", "args": {"Subagents": [{"Role": "subagent-1-executioner", "Model": "flash", "Prompt": "run"}]}}]}
{"step_index": 1, "created_at": "2026-09-21T01:05:00Z", "tool_calls": [{"name": "invoke_subagent", "args": {"Subagents": [{"Role": "subagent-1-hammer", "Model": "flash", "Prompt": "review"}]}}]}
{"step_index": 2, "created_at": "2026-09-21T01:10:00Z", "tool_calls": [{"name": "invoke_subagent", "args": {"Subagents": [{"Role": "subagent-1-auditor", "Model": "flash", "Prompt": "qa"}]}}]}
EOF

python3 "$SKILL_DIR/scripts/verify_ladder_state.py" --log "$CLEAN_LOG"
echo "  -> verify_ladder_state.py clean log verification: OK"

# Test verify_ladder_state.py catches bypass
BYPASS_LOG="$TMP_TEST_DIR/bypass_transcript.jsonl"
cat << 'EOF' > "$BYPASS_LOG"
{"step_index": 0, "created_at": "2026-09-21T01:00:00Z", "tool_calls": [{"name": "invoke_subagent", "args": {"Subagents": [{"Role": "subagent-1-executioner", "Model": "flash", "Prompt": "run"}]}}]}
{"step_index": 1, "created_at": "2026-09-21T01:10:00Z", "tool_calls": [{"name": "invoke_subagent", "args": {"Subagents": [{"Role": "subagent-1-auditor", "Model": "flash", "Prompt": "qa"}]}}]}
EOF

if python3 "$SKILL_DIR/scripts/verify_ladder_state.py" --log "$BYPASS_LOG" >/dev/null; then
  echo "Error: verify_ladder_state.py failed to catch Hammer bypass!" >&2
  exit 1
fi
echo "  -> verify_ladder_state.py caught state machine bypass: OK"

echo "=== [Test 4] De-duplication & Rule Consolidation Verification ==="
# Verify that AGENTS.md does NOT contain duplicated ASCII art or role definitions
if grep -q "Phase Executioner" "$KNOT_ROOT/AGENTS.md"; then
  echo "Error: Detected lingering 'Phase Executioner' duplication in AGENTS.md!" >&2
  exit 1
fi
if grep -q "Verification / Hammer" "$KNOT_ROOT/AGENTS.md"; then
  echo "Error: Detected lingering 'Verification / Hammer' duplication in AGENTS.md!" >&2
  exit 1
fi
if ! grep -q "subagent-ladder" "$KNOT_ROOT/AGENTS.md"; then
  echo "Error: AGENTS.md does not reference the consolidated subagent-ladder skill!" >&2
  exit 1
fi
echo "  -> AGENTS.md de-duplication: OK"

echo "=== [Test 5] Template Validation ==="
for t in executioner_prompt.md hammer_prompt.md auditor_prompt.md phase_plan_template.md; do
  if [ ! -s "$SKILL_DIR/templates/$t" ]; then
    echo "Error: Missing template $t in $SKILL_DIR/templates" >&2
    exit 1
  fi
done
echo "  -> Prompt templates verified: OK"

echo -e "\033[1;32m[PASS] All Subagent Ladder Skill verifications passed successfully!\033[0m"
