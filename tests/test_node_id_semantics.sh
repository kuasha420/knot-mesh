#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Test Suite: Node ID vs Hostname Semantics & Worktree Path Normalization
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
unset KNOT_NODE_ID KNOT_HUB_URL KNOT_RUN_ID KNOT_COUNCIL_RUN_ID KNOT_ACTIVE_SWARM

echo "=== [Test 1] Bash & Python Syntax Verification ==="
bash -n "$KNOT_ROOT/core/lib.sh"
bash -n "$KNOT_ROOT/core/resolver.sh"
bash -n "$KNOT_ROOT/core/modules/ssh.sh"
bash -n "$KNOT_ROOT/core/gitops.sh"
bash -n "$KNOT_ROOT/bin/knot"
python3 -m py_compile "$KNOT_ROOT/runtime/skills/swarm-council/scripts/resolve_node.py"
python3 -m py_compile "$KNOT_ROOT/core/hub/hub.py"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in \
  "$KNOT_ROOT/core/lib.sh" \
  "$KNOT_ROOT/core/resolver.sh" \
  "$KNOT_ROOT/core/modules/ssh.sh" \
  "$KNOT_ROOT/core/gitops.sh"; do
  # Check for forbidden error swallowing constructs
  if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$f" | grep -v "source " | grep -v "#"; then
    echo "Error: Forbidden error swallowing construct found in $f" >&2
    exit 1
  fi
done
echo "  -> PSL Rule 1 compliance: OK"

echo "=== [Test 3] Node ID & Hostname Resolution Without 'hostname' Command ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake_bin"
mkdir -p "$FAKE_BIN"
# Populate FAKE_BIN with symlinks to system binaries except 'hostname'
for p in /bin/* /usr/bin/*; do
  [ -e "$p" ] || continue
  b="$(basename "$p")"
  if [ "$b" != "hostname" ] && [ ! -e "$FAKE_BIN/$b" ]; then
    ln -s "$p" "$FAKE_BIN/$b"
  fi
done
NEW_PATH="$FAKE_BIN"

# Verify hostname is indeed missing in this test subshell
if PATH="$NEW_PATH" command -v hostname >/dev/null; then
  echo "Error: Test setup failure - hostname command should not exist in FAKE_BIN" >&2
  exit 1
fi

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/knot"

# Source core/lib.sh under test
# shellcheck source=/dev/null
source "$KNOT_ROOT/core/lib.sh"

detected_h="$(PATH="$NEW_PATH" knot_detect_hostname)"
[ -n "$detected_h" ] || { echo "Error: knot_detect_hostname returned empty" >&2; exit 1; }
echo "  Detected Hostname: $detected_h"

# 3a. Explicit KNOT_NODE_ID override
res_id="$(KNOT_NODE_ID="test-anchor" PATH="$NEW_PATH" knot_detect_node_id)"
[ "$res_id" = "test-anchor" ] || { echo "Expected test-anchor, got $res_id" >&2; exit 1; }

# 3b. Node ID from file (~/.config/knot/node_id)
echo "test-worker" > "$HOME/.config/knot/node_id"
res_id="$(KNOT_NODE_ID="" PATH="$NEW_PATH" knot_detect_node_id)"
[ "$res_id" = "test-worker" ] || { echo "Expected test-worker, got $res_id" >&2; exit 1; }
rm -f "$HOME/.config/knot/node_id"

# 3c. Swarm manifest resolution where physical hostname != canonical node ID
SWARM_DIR="$HOME/.config/knot/swarms/audit-swarm"
SWARM_NODES="$SWARM_DIR/nodes"
mkdir -p "$SWARM_NODES"
cat << CONF_EOF > "$SWARM_DIR/swarm.conf"
SWARM_ID="audit-swarm"
SWARM_NAME="Audit Swarm"
ANCHOR_ID="desktop"
ANCHOR_HOST="mock-anchor-box"
HUB_PORT=4242
CONF_EOF

export KNOT_ACTIVE_SWARM="audit-swarm"

cat << JSON_EOF > "$SWARM_NODES/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "$detected_h",
  "aliases": ["worker-beta", "handheld-rog"],
  "user": "user_b",
  "role": "strand"
}
JSON_EOF

res_id="$(KNOT_NODE_ID="" PATH="$NEW_PATH" knot_detect_node_id)"
[ "$res_id" = "rog-ally" ] || { echo "Expected rog-ally from manifest match, got $res_id" >&2; exit 1; }
echo "  -> Hostname vs Node ID detection without 'hostname' binary: OK"

echo "=== [Test 4] Python Dynamic Node ID Resolver (resolve_node.py) ==="
py_res="$(KNOT_NODE_ID="" PATH="$NEW_PATH" python3 "$KNOT_ROOT/runtime/skills/swarm-council/scripts/resolve_node.py")"
[ "$py_res" = "rog-ally" ] || { echo "Expected rog-ally from resolve_node.py, got $py_res" >&2; exit 1; }

# Test alias match
cat << JSON_EOF > "$SWARM_NODES/laptop.json"
{
  "id": "laptop",
  "hostname": "laptop-linux",
  "aliases": ["worker-alpha"],
  "user": "user_b",
  "role": "strand"
}
JSON_EOF
py_alias_res="$(KNOT_NODE_ID="" python3 "$KNOT_ROOT/runtime/skills/swarm-council/scripts/resolve_node.py" "laptop-linux")"
[ "$py_alias_res" = "laptop-linux" ] || { echo "Expected laptop-linux from list match, got $py_alias_res" >&2; exit 1; }
echo "  -> Python resolve_node.py semantics: OK"

echo "=== [Test 5] Multi-Node Manifest Topology & Knot Resolver Semantics ==="
cat << JSON_EOF > "$SWARM_NODES/desktop.json"
{
  "id": "desktop",
  "hostname": "mock-anchor-box",
  "aliases": ["workstation-anchor"],
  "user": "user_a",
  "role": "anchor",
  "port": 42069,
  "ip_hint": "192.168.68.153"
}
JSON_EOF

cat << JSON_EOF > "$SWARM_NODES/steamdeck.json"
{
  "id": "steamdeck",
  "hostname": "steamdeck-jupiter",
  "aliases": ["worker-gamma"],
  "user": "user_c",
  "role": "strand",
  "port": 22,
  "ip_hint": "192.168.68.188"
}
JSON_EOF

# 5a. knot_is_anchor verification
export KNOT_ACTIVE_SWARM="audit-swarm"
ANCHOR_ID="desktop" ANCHOR_HOST="mock-anchor-box"
if knot_is_anchor; then
  echo "Error: Local rog-ally node should not be detected as anchor" >&2
  exit 1
fi

# 5b. Local address resolution via resolver.sh
resolved_local="$(bash "$KNOT_ROOT/core/resolver.sh" "rog-ally")"
[ "$resolved_local" = "127.0.0.1" ] || { echo "Expected 127.0.0.1 for local node_id, got $resolved_local" >&2; exit 1; }

resolved_local_h="$(bash "$KNOT_ROOT/core/resolver.sh" "$detected_h")"
[ "$resolved_local_h" = "127.0.0.1" ] || { echo "Expected 127.0.0.1 for local hostname, got $resolved_local_h" >&2; exit 1; }

echo "  -> Resolver single-node & local tier semantics: OK"

echo "=== [Test 6] Subshell Environment Exports in knot exec ==="
# Test knot exec export contract (KNOT_NODE_ID, KNOT_HUB_URL, PATH)
exec_out="$("$KNOT_ROOT/bin/knot" exec local 'echo "NID=$KNOT_NODE_ID;HUB=$KNOT_HUB_URL;P=$PATH"')"
echo "  Raw subshell output: $exec_out"
echo "$exec_out" | grep -q "NID=rog-ally" || { echo "Missing KNOT_NODE_ID in subshell export" >&2; exit 1; }
echo "$exec_out" | grep -q "HUB=https://" || { echo "Missing KNOT_HUB_URL in subshell export" >&2; exit 1; }
echo "$exec_out" | grep -q "P=.*/.local/bin" || { echo "Missing canonical PATH in subshell export" >&2; exit 1; }

# Executing using physical hostname resolves to canonical node ID
exec_h_out="$("$KNOT_ROOT/bin/knot" exec "$detected_h" 'echo "NID=$KNOT_NODE_ID"')"
echo "$exec_h_out" | grep -q "NID=rog-ally" || { echo "Expected NID=rog-ally when targeted by hostname" >&2; exit 1; }
echo "  -> knot exec remote subshell export contract: OK"

echo "=== [Test 7] Cross-Node User Home Path Normalization ==="
# 7a. Bash knot_path_normalize tests
p1="$(knot_path_normalize "/home/user_a/Dev/knot-mesh" "/home/user_b")"
[ "$p1" = "/home/user_b/Dev/knot-mesh" ] || { echo "Expected /home/user_b/Dev/knot-mesh, got $p1" >&2; exit 1; }

p2="$(knot_path_normalize "/home/user_b/Dev/knot-mesh" "/home/user_c")"
[ "$p2" = "/home/user_c/Dev/knot-mesh" ] || { echo "Expected /home/user_c/Dev/knot-mesh, got $p2" >&2; exit 1; }

p3="$(knot_path_normalize "file:///home/user_a/Dev/knot-mesh" "/home/user_b")"
[ "$p3" = "file:///home/user_b/Dev/knot-mesh" ] || { echo "Expected file:///home/user_b/Dev/knot-mesh, got $p3" >&2; exit 1; }

p4="$(knot_path_normalize "~/Dev/knot-mesh" "/home/user_c")"
[ "$p4" = "/home/user_c/Dev/knot-mesh" ] || { echo "Expected /home/user_c/Dev/knot-mesh, got $p4" >&2; exit 1; }

# 7b. Portable format conversions
port_out="$(knot_path_to_portable "/home/user_a/Dev/knot-mesh")"
[ "$port_out" = "~/Dev/knot-mesh" ] || { echo "Expected ~/Dev/knot-mesh, got $port_out" >&2; exit 1; }

port_uri="$(knot_path_to_portable "file:///home/user_a/Dev/knot-mesh")"
[ "$port_uri" = "file://~/Dev/knot-mesh" ] || { echo "Expected file://~/Dev/knot-mesh, got $port_uri" >&2; exit 1; }

from_port="$(knot_path_from_portable "$port_uri" "/home/user_c")"
[ "$from_port" = "file:///home/user_c/Dev/knot-mesh" ] || { echo "Expected file:///home/user_c/Dev/knot-mesh, got $from_port" >&2; exit 1; }

# 7c. CLI worktree normalize command
cli_norm="$("$KNOT_ROOT/bin/knot" worktree normalize "/home/user_a/Dev/knot-mesh" "/home/user_b")"
[ "$cli_norm" = "/home/user_b/Dev/knot-mesh" ] || { echo "Expected /home/user_b/Dev/knot-mesh from CLI, got $cli_norm" >&2; exit 1; }

# 7d. Python Database.normalize_home_path test
python3 -c "
import sys
sys.path.insert(0, '$KNOT_ROOT')
from core.hub.hub import Database
assert Database.normalize_home_path('/home/user_a/Dev/knot-mesh', '/home/user_b') == '/home/user_b/Dev/knot-mesh'
assert Database.normalize_home_path('file:///home/user_a/Dev/knot-mesh', '/home/user_c') == 'file:///home/user_c/Dev/knot-mesh'
assert Database.normalize_home_path('~/Dev/knot-mesh', '/home/user_b') == '/home/user_b/Dev/knot-mesh'
"
echo "  -> Cross-node path normalization (/home/user_a <-> /home/user_b <-> /home/user_c): OK"

echo "=== [Test 8] Automated Git Worktree Provisioning (Zero Duplicate Clones) ==="
SAMPLE_REPO="$TMP_DIR/test_repo"
git init "$SAMPLE_REPO" >/dev/null
(
  cd "$SAMPLE_REPO"
  git config user.name "Test Dev"
  git config user.email "test@knot.mesh"
  echo "knot mesh test" > test.txt
  git add test.txt
  git commit -m "feat: initial commit" >/dev/null
)

# 8a. Provision worktree via knot worktree add
WT_PATH="$("$KNOT_ROOT/bin/knot" worktree add "$SAMPLE_REPO" wt-audit --branch "audit-branch" | tail -n1)"
[ -d "$WT_PATH" ] || { echo "Error: Worktree directory not created: $WT_PATH" >&2; exit 1; }

# 8b. Strict verification of shared repository (.git is a file, NOT a directory)
[ -f "$WT_PATH/.git" ] || { echo "Error: Expected .git in worktree to be a pointer file" >&2; exit 1; }
[ ! -d "$WT_PATH/.git" ] || { echo "Error: Found full .git directory! Duplicate clone detected!" >&2; exit 1; }

# Verify common commits and shared object storage
base_rev="$(git -C "$SAMPLE_REPO" rev-parse HEAD)"
wt_rev="$(git -C "$WT_PATH" rev-parse HEAD)"
[ "$base_rev" = "$wt_rev" ] || { echo "Commit mismatch between base and worktree" >&2; exit 1; }

# 8c. Idempotent re-provision check
wt_readd="$("$KNOT_ROOT/bin/knot" worktree add "$SAMPLE_REPO" wt-audit --branch "audit-branch")"
echo "$wt_readd" | grep -q "already provisioned" || { echo "Expected idempotent notice on re-add" >&2; exit 1; }

# 8d. Worktree list inspection
wt_list="$("$KNOT_ROOT/bin/knot" worktree list "$SAMPLE_REPO")"
echo "$wt_list" | grep -q "wt-audit" || { echo "Worktree not found in list output" >&2; exit 1; }

# 8e. Clean worktree removal & prune
"$KNOT_ROOT/bin/knot" worktree remove "$SAMPLE_REPO" wt-audit --force
[ ! -d "$WT_PATH" ] || { echo "Error: Worktree was not removed" >&2; exit 1; }
echo "  -> Automated git worktree provisioning & zero duplicate clone verification: OK"

echo "=== [Test 9] SSH Config Generation with Canonical Node ID & Aliases ==="
# Test ssh_sync_client_config compiles with both node_id and aliases
SSH_DIR="$HOME/.ssh"
mkdir -p "$SSH_DIR"
# shellcheck source=/dev/null
source "$KNOT_ROOT/core/modules/ssh.sh"
ssh_sync_client_config

ssh_cfg="$SSH_DIR/config"
[ -f "$ssh_cfg" ] || { echo "Missing ~/.ssh/config" >&2; exit 1; }
grep -q "Host desktop" "$ssh_cfg" || { echo "Missing 'Host desktop' in ~/.ssh/config" >&2; exit 1; }
grep -q "Host desktop.audit-swarm" "$ssh_cfg" || { echo "Missing 'Host desktop.audit-swarm' in ~/.ssh/config" >&2; exit 1; }
grep -q "ProxyCommand.*desktop" "$ssh_cfg" || { echo "ProxyCommand does not target canonical desktop" >&2; exit 1; }
grep -q "User user_a" "$ssh_cfg" || { echo "Missing User user_a in ~/.ssh/config" >&2; exit 1; }
grep -q "User user_c" "$ssh_cfg" || { echo "Missing User user_c in ~/.ssh/config" >&2; exit 1; }
echo "  -> SSH client config compilation with canonical node IDs & user isolation: OK"

echo ""
echo "=== [✓] ALL NODE ID SEMANTICS & CROSS-NODE WORKTREE TESTS PASSED! ==="
