#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Automated Verification Suite for Issue #69
# PSL Project Configuration Linkage and .git/info/exclude Hygiene in knot worktree add
# PSL Gold Standard: Zero error swallowing, zero || true, strict type/shell hygiene

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOT_BIN="$REPO_ROOT/bin/knot"

TEST_SANDBOX="$(mktemp -d /tmp/knot_gitops_test.XXXXXX)"
cleanup() {
  local rc=$?
  rm -rf "$TEST_SANDBOX"
  exit $rc
}
trap cleanup EXIT

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #69 GitOps Worktree PSL Linkage Test Suite"
echo "================================================================================"
echo "Sandbox: $TEST_SANDBOX"

# 1. Setup mock git repository with PSL directories
echo -n "1. Setting up synthetic parent repository with .agents/ and .psl/... "
PARENT_REPO="$TEST_SANDBOX/repo_main"
mkdir -p "$PARENT_REPO"
git -C "$PARENT_REPO" init -b main >/dev/null
git -C "$PARENT_REPO" config user.name "Knot Test"
git -C "$PARENT_REPO" config user.email "test@knot.mesh"

mkdir -p "$PARENT_REPO/.agents"
echo "role: anchor" > "$PARENT_REPO/.agents/role.yaml"
mkdir -p "$PARENT_REPO/.psl"
echo "harness: active" > "$PARENT_REPO/.psl/config.yaml"

echo "Initial README" > "$PARENT_REPO/README.md"
git -C "$PARENT_REPO" add README.md
git -C "$PARENT_REPO" commit -m "feat: initial commit" >/dev/null
echo "PASSED"

# 2. Provision worktree with default PSL linkage
echo -n "2. Provisioning worktree with default PSL linkage... "
WT_1="$TEST_SANDBOX/wt_agent_feature"
"$KNOT_BIN" worktree add "$PARENT_REPO" "$WT_1" --branch feat-agent-1 >/dev/null

if [ ! -d "$WT_1" ]; then
  echo "FAILED (Worktree directory $WT_1 not created)"
  exit 1
fi
echo "PASSED"

# 3. Verify .git/info/exclude hygiene
echo -n "3. Verifying .git/info/exclude patterns in common and worktree gitdir... "
COMMON_GITDIR="$(git -C "$WT_1" rev-parse --git-common-dir)"
if [[ "$COMMON_GITDIR" != /* ]]; then
  COMMON_GITDIR="$(cd "$WT_1" && cd "$COMMON_GITDIR" && pwd)"
fi

EXCLUDE_FILE="$COMMON_GITDIR/info/exclude"
if [ ! -f "$EXCLUDE_FILE" ]; then
  echo "FAILED (Common exclude file $EXCLUDE_FILE not found)"
  exit 1
fi

REQUIRED_PATTERNS=(
  ".agents/"
  ".psl/"
  ".gemini/"
  ".cache/"
  "scratch/"
)

for pat in "${REQUIRED_PATTERNS[@]}"; do
  if ! grep -qxF "$pat" "$EXCLUDE_FILE"; then
    echo "FAILED (Pattern '$pat' missing from $EXCLUDE_FILE)"
    exit 1
  fi
done
echo "PASSED"

# 4. Verify PSL symlinks created
echo -n "4. Verifying symlinked PSL configuration directories... "
if [ ! -L "$WT_1/.agents" ]; then
  echo "FAILED (.agents is not a symlink in $WT_1)"
  exit 1
fi
if [ ! -L "$WT_1/.psl" ]; then
  echo "FAILED (.psl is not a symlink in $WT_1)"
  exit 1
fi

target_agents="$(readlink -f "$WT_1/.agents")"
expected_agents="$(readlink -f "$PARENT_REPO/.agents")"
if [ "$target_agents" != "$expected_agents" ]; then
  echo "FAILED (.agents points to $target_agents, expected $expected_agents)"
  exit 1
fi

target_psl="$(readlink -f "$WT_1/.psl")"
expected_psl="$(readlink -f "$PARENT_REPO/.psl")"
if [ "$target_psl" != "$expected_psl" ]; then
  echo "FAILED (.psl points to $target_psl, expected $expected_psl)"
  exit 1
fi
echo "PASSED"

# 5. Verify dirty working tree pollution immunity
echo -n "5. Testing dirty working tree pollution immunity... "
mkdir -p "$WT_1/.gemini/antigravity"
echo "session log" > "$WT_1/.gemini/antigravity/transcript.jsonl"
mkdir -p "$WT_1/.cache"
echo "cache data" > "$WT_1/.cache/temp.bin"
mkdir -p "$WT_1/scratch"
echo "scratch file" > "$WT_1/scratch/test.py"

status_out="$(git -C "$WT_1" status --porcelain)"
if [ -n "$status_out" ]; then
  echo "FAILED (Working tree is dirty despite exclude patterns: $status_out)"
  exit 1
fi
echo "PASSED"

# 6. Test --no-psl-link flag
echo -n "6. Testing worktree provisioning with --no-psl-link... "
WT_2="$TEST_SANDBOX/wt_no_psl"
"$KNOT_BIN" worktree add "$PARENT_REPO" "$WT_2" --branch feat-no-psl --no-psl-link >/dev/null

if [ ! -d "$WT_2" ]; then
  echo "FAILED (Worktree directory $WT_2 not created)"
  exit 1
fi

if [ -e "$WT_2/.agents" ] || [ -L "$WT_2/.agents" ]; then
  echo "FAILED (.agents was linked despite --no-psl-link)"
  exit 1
fi
if [ -e "$WT_2/.psl" ] || [ -L "$WT_2/.psl" ]; then
  echo "FAILED (.psl was linked despite --no-psl-link)"
  exit 1
fi
echo "PASSED"

# 7. Test worktree removal (unforced clean removal)
echo -n "7. Testing worktree unforced removal and pruning... "
"$KNOT_BIN" worktree remove "$PARENT_REPO" "$WT_1" >/dev/null
if [ -d "$WT_1" ]; then
  echo "FAILED (Worktree directory $WT_1 still exists after unforced removal)"
  exit 1
fi
"$KNOT_BIN" worktree remove "$PARENT_REPO" "$WT_2" >/dev/null
if [ -d "$WT_2" ]; then
  echo "FAILED (Worktree directory $WT_2 still exists after unforced removal)"
  exit 1
fi
echo "PASSED"

# 8. Test provision with --no-psl-link string flag
echo -n "8. Testing provision with --no-psl-link string flag... "
WT_3="$TEST_SANDBOX/wt_provision_no_psl"
"$KNOT_BIN" worktree provision "$PARENT_REPO" "$WT_3" feat-prov-no-psl local HEAD --no-psl-link >/dev/null
if [ ! -d "$WT_3" ]; then
  echo "FAILED (Worktree directory $WT_3 not created)"
  exit 1
fi
if [ -e "$WT_3/.agents" ] || [ -L "$WT_3/.agents" ]; then
  echo "FAILED (.agents was linked in provision despite --no-psl-link)"
  exit 1
fi
"$KNOT_BIN" worktree remove "$PARENT_REPO" "$WT_3" >/dev/null
echo "PASSED"

echo "================================================================================"
echo ">>> All Issue #69 GitOps Worktree Tests PASSED Successfully!"
echo "================================================================================"
