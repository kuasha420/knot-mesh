#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Automated Verification for Worktree Rebase-Mesh Arbiter (Strand C: #75)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BIN_KNOT="$KNOT_ROOT/bin/knot"
GITOPS_SCRIPT="$KNOT_ROOT/core/gitops.sh"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$GITOPS_SCRIPT"
bash -n "$BIN_KNOT"
echo "  -> gitops.sh & bin/knot syntax: OK"

echo "=== [Test 2] Zero Error Swallowing Audit (PSL Rule 1) ==="
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
matches=""
if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$GITOPS_SCRIPT" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
  matches=""
fi
if [ -n "$matches" ]; then
  echo "Error: Forbidden error swallowing detected in gitops.sh:" >&2
  echo "$matches" >&2
  exit 1
fi
echo "  -> Zero error swallowing in gitops.sh: OK"

echo "=== [Test 3] Multi-Worktree Upstream Rebase ==="
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

# Initialize a base test repo
REPO_DIR="$TEST_TMP/test_repo"
mkdir -p "$REPO_DIR"
git -C "$REPO_DIR" init -b main
git -C "$REPO_DIR" config user.name "Test Committer"
git -C "$REPO_DIR" config user.email "test@knot.mesh"

echo "initial base" > "$REPO_DIR/base.txt"
git -C "$REPO_DIR" add base.txt
git -C "$REPO_DIR" commit -m "feat(base): initial base commit"

# Provision two worktrees using knot worktree add
bash "$BIN_KNOT" worktree add "$REPO_DIR" "wt_alpha" --branch "alpha" --no-psl-link
bash "$BIN_KNOT" worktree add "$REPO_DIR" "wt_beta" --branch "beta" --no-psl-link

WT_ALPHA="$REPO_DIR/worktrees/wt_alpha"
WT_BETA="$REPO_DIR/worktrees/wt_beta"

# Add branch commits in worktrees
echo "alpha change" > "$WT_ALPHA/alpha.txt"
git -C "$WT_ALPHA" add alpha.txt
git -C "$WT_ALPHA" commit -m "feat(alpha): add alpha feature"

echo "beta change" > "$WT_BETA/beta.txt"
git -C "$WT_BETA" add beta.txt
git -C "$WT_BETA" commit -m "feat(beta): add beta feature"

# Advance main
echo "main update" > "$REPO_DIR/main_update.txt"
git -C "$REPO_DIR" add main_update.txt
git -C "$REPO_DIR" commit -m "feat(main): upstream commit on main"

MAIN_HEAD="$(git -C "$REPO_DIR" rev-parse HEAD)"

# Execute knot worktree rebase-mesh
bash "$BIN_KNOT" worktree rebase-mesh "$REPO_DIR" --upstream main

# Verify both worktrees contain the main update
if [ ! -f "$WT_ALPHA/main_update.txt" ]; then
  echo "Error: wt_alpha was not rebased onto main!" >&2
  exit 1
fi
if [ ! -f "$WT_BETA/main_update.txt" ]; then
  echo "Error: wt_beta was not rebased onto main!" >&2
  exit 1
fi

echo "  -> Clean parallel rebase across multiple worktrees: OK"

echo "=== [Test 4] Barrel Conflict Detection & Auto-Resolution ==="
# Provision a barrel worktree
bash "$BIN_KNOT" worktree add "$REPO_DIR" "wt_barrel" --branch "barrel-feature" --no-psl-link
WT_BARREL="$REPO_DIR/worktrees/wt_barrel"

mkdir -p "$REPO_DIR/src"
mkdir -p "$WT_BARREL/src"

echo "export * from './initial';" > "$REPO_DIR/src/index.ts"
git -C "$REPO_DIR" add src/index.ts
git -C "$REPO_DIR" commit -m "feat(barrel): add base barrel exports"

# Advance barrel-feature worktree
echo "export * from './feature_alpha';" >> "$WT_BARREL/src/index.ts"
git -C "$WT_BARREL" add src/index.ts
git -C "$WT_BARREL" commit -m "feat(barrel): add feature_alpha export"

# Concurrently advance main with another additive export
echo "export * from './feature_beta';" >> "$REPO_DIR/src/index.ts"
git -C "$REPO_DIR" add src/index.ts
git -C "$REPO_DIR" commit -m "feat(barrel): add feature_beta export"

# Run knot worktree rebase-mesh to resolve barrel conflict
bash "$BIN_KNOT" worktree rebase-mesh "$REPO_DIR" --upstream main

BARREL_CONTENT="$(cat "$WT_BARREL/src/index.ts")"
if ! echo "$BARREL_CONTENT" | grep -q "feature_alpha"; then
  echo "Error: feature_alpha export missing after barrel conflict resolution!" >&2
  exit 1
fi
if ! echo "$BARREL_CONTENT" | grep -q "feature_beta"; then
  echo "Error: feature_beta export missing after barrel conflict resolution!" >&2
  exit 1
fi
if echo "$BARREL_CONTENT" | grep -q "<<<<<<<"; then
  echo "Error: Conflict markers still remain in barrel file!" >&2
  exit 1
fi
echo "  -> Additive barrel conflict auto-detected, resolved, and rebased: OK"

echo "=== [Test 5] Ambiguous Conflict Detection & Branch Quarantine ==="
# Provision an ambiguous conflict worktree
bash "$BIN_KNOT" worktree add "$REPO_DIR" "wt_quarantine" --branch "quarantine-feature" --no-psl-link
WT_QUARANTINE="$REPO_DIR/worktrees/wt_quarantine"

mkdir -p "$REPO_DIR/pkg"
mkdir -p "$WT_QUARANTINE/pkg"

cat << 'EOF' > "$REPO_DIR/pkg/core.py"
def compute():
    return 1
EOF
git -C "$REPO_DIR" add pkg/core.py
git -C "$REPO_DIR" commit -m "feat(core): initial compute function"

cat << 'EOF' > "$WT_QUARANTINE/pkg/core.py"
def compute():
    return "branch_result"
EOF
git -C "$WT_QUARANTINE" add pkg/core.py
git -C "$WT_QUARANTINE" commit -m "feat(core): branch compute modification"

cat << 'EOF' > "$REPO_DIR/pkg/core.py"
def compute():
    return "upstream_conflict"
EOF
git -C "$REPO_DIR" add pkg/core.py
git -C "$REPO_DIR" commit -m "feat(core): upstream compute modification"

# Expect knot worktree rebase-mesh to exit non-zero and quarantine
set +e
bash "$BIN_KNOT" worktree rebase-mesh "$REPO_DIR" --upstream main > "$TEST_TMP/quarantine_out.log" 2>&1
quarantine_rc=$?
set -euo pipefail

if [ "$quarantine_rc" -eq 0 ]; then
  echo "Error: Expected non-zero exit code when ambiguous conflicts occur!" >&2
  exit 1
fi

if [ ! -f "$WT_QUARANTINE/.knot_quarantine" ]; then
  echo "Error: .knot_quarantine marker not found in quarantined worktree!" >&2
  exit 1
fi

if ! grep -q "QUARANTINE" "$TEST_TMP/quarantine_out.log"; then
  echo "Error: [QUARANTINE] diagnostic not output in orchestrator log!" >&2
  exit 1
fi

# Ensure git rebase was safely aborted (not left in rebase-merge state)
if [ -d "$WT_QUARANTINE/.git/rebase-merge" ] || [ -d "$REPO_DIR/.git/worktrees/wt_quarantine/rebase-merge" ]; then
  echo "Error: Worktree left in dirty rebase-merge state!" >&2
  exit 1
fi

echo "  -> Ambiguous conflict safely aborted, quarantined, and diagnostic reported: OK"

echo "=== [Test 6] React/TSX Barrel Conflict Detection & Auto-Resolution (index.tsx) ==="
# Provision a TSX barrel worktree
bash "$BIN_KNOT" worktree add "$REPO_DIR" "wt_tsx" --branch "tsx-feature" --no-psl-link
WT_TSX="$REPO_DIR/worktrees/wt_tsx"

mkdir -p "$REPO_DIR/components"
mkdir -p "$WT_TSX/components"

echo "export * from './Button';" > "$REPO_DIR/components/index.tsx"
git -C "$REPO_DIR" add components/index.tsx
git -C "$REPO_DIR" commit -m "feat(tsx): add base Button export"

echo "export * from './Card';" >> "$WT_TSX/components/index.tsx"
git -C "$WT_TSX" add components/index.tsx
git -C "$WT_TSX" commit -m "feat(tsx): add Card export in branch"

echo "export * from './Modal';" >> "$REPO_DIR/components/index.tsx"
git -C "$REPO_DIR" add components/index.tsx
git -C "$REPO_DIR" commit -m "feat(tsx): add Modal export in main"

# Run knot worktree rebase-mesh
bash "$BIN_KNOT" worktree rebase-mesh "$REPO_DIR" --upstream main

TSX_CONTENT="$(cat "$WT_TSX/components/index.tsx")"
if ! echo "$TSX_CONTENT" | grep -q "Card"; then
  echo "Error: Card export missing from resolved index.tsx!" >&2
  exit 1
fi
if ! echo "$TSX_CONTENT" | grep -q "Modal"; then
  echo "Error: Modal export missing from resolved index.tsx!" >&2
  exit 1
fi
echo "  -> Additive .tsx barrel conflict auto-detected, resolved, and rebased: OK"

echo "=== [Test 7] Remote Rebase Failure Propagation (Zero Error Swallowing) ==="
# Test that a failing remote node rebase is propagated as a non-zero exit code
MOCK_BIN="$TEST_TMP/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/knot"
#!/usr/bin/env bash
if [ "$1" = "exec" ]; then
  echo "Simulated remote rebase failure" >&2
  exit 1
fi
exec "$KNOT_ROOT/bin/knot" "$@"
EOF
chmod +x "$MOCK_BIN/knot"

set +e
PATH="$MOCK_BIN:$PATH" bash "$BIN_KNOT" worktree rebase-mesh "$REPO_DIR" --upstream main --nodes remote_worker > "$TEST_TMP/remote_fail.log" 2>&1
remote_fail_rc=$?
set -euo pipefail

if [ "$remote_fail_rc" -eq 0 ]; then
  echo "Error: Expected non-zero exit code when remote node rebase fails!" >&2
  exit 1
fi
echo "  -> Remote node rebase failure propagated as non-zero exit code: OK"

echo "=== [✓] ALL WORKTREE REBASE-MESH TESTS PASSED! ==="
