#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Swarm Sync Module & CLI Orchestration (Issue #38)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/modules/swarm_sync.sh"
bash -n "$KNOT_ROOT/bin/knot"
echo "  -> swarm_sync.sh & bin/knot syntax: OK"

echo "=== [Test 2] Rule 02 Zero Error Swallowing Code Audit ==="
# Verify no 2>/dev/null, || true, or || : in new swarm_sync.sh
if grep -rn "2>/dev/null" "$KNOT_ROOT/core/modules/swarm_sync.sh"; then
  echo "Error: Forbidden 2>/dev/null found in swarm_sync.sh" >&2
  exit 1
fi
if grep -rn "|| true" "$KNOT_ROOT/core/modules/swarm_sync.sh"; then
  echo "Error: Forbidden || true found in swarm_sync.sh" >&2
  exit 1
fi
if grep -rn "|| :" "$KNOT_ROOT/core/modules/swarm_sync.sh"; then
  echo "Error: Forbidden || : found in swarm_sync.sh" >&2
  exit 1
fi
echo "  -> Rule 02 Zero Error Swallowing compliance: OK"

echo "=== [Test 2b] Rule 01 Legacy Registry Cleanliness Audit ==="
if grep -rn "registry/nodes" "$KNOT_ROOT/bin/" "$KNOT_ROOT/core/"; then
  echo "Error: Forbidden legacy registry/nodes reference found in codebase" >&2
  exit 1
fi
echo "  -> Zero legacy registry/nodes references: OK"

echo "=== [Test 3] Swarm Sync Anchor Push & Strand Pull Logic ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
export KNOT_RUNTIME_DIR="$TMP_DIR/run"
export MOCK_REMOTE_HOME="$TMP_DIR/remote_home"
mkdir -p "$HOME/.config/knot/swarms/testswarm/nodes" "$HOME/.local/state/knot" "$KNOT_RUNTIME_DIR" "$MOCK_REMOTE_HOME"

sudo() {
  return 1
}
export -f sudo

# Setup test swarm profile & topology on Anchor
cat << 'SWARM_EOF' > "$HOME/.config/knot/swarms/testswarm/swarm.conf"
SWARM_ID="testswarm"
SWARM_NAME="Test Swarm"
ANCHOR_ID="desktop"
ANCHOR_HOST="test-anchor"
HUB_PORT=4242
SWARM_EOF
cp "$HOME/.config/knot/swarms/testswarm/swarm.conf" "$HOME/.config/knot/swarms/testswarm.conf"

cat << 'TOPO_EOF' > "$HOME/.config/knot/swarms/testswarm/topology.json"
{
  "anchor": "desktop",
  "screens": ["desktop", "laptop"],
  "layout": {
    "desktop": {
      "left": {
        "node": "laptop",
        "span": [0, 100]
      }
    }
  }
}
TOPO_EOF

cat << 'NODE_ANC_EOF' > "$HOME/.config/knot/swarms/testswarm/nodes/desktop.json"
{
  "id": "desktop",
  "hostname": "test-anchor",
  "role": "anchor",
  "port": 42069,
  "user": "anchoruser"
}
NODE_ANC_EOF

cat << 'NODE_STR_EOF' > "$HOME/.config/knot/swarms/testswarm/nodes/laptop.json"
{
  "id": "laptop",
  "hostname": "test-strand",
  "role": "strand",
  "port": 22,
  "user": "stranduser"
}
NODE_STR_EOF

echo "testswarm" > "$HOME/.local/state/knot/active_swarm"

# Mock ssh, rsync, and systemctl in test PATH
MOCK_BIN="$TMP_DIR/mock_bin"
mkdir -p "$MOCK_BIN"
export PATH="$MOCK_BIN:$PATH"

cat << 'MOCK_SSH_EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
set -euo pipefail
target=""
cmd=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-e|-p|-i) shift 2 ;;
    -*) shift ;;
    *)
      if [ -z "$target" ]; then
        target="$1"
        shift
      else
        cmd="$*"
        break
      fi
      ;;
  esac
done

if [ -z "$cmd" ] || [ "$cmd" = "echo ok" ] || [ "$cmd" = "echo ping" ]; then
  echo "ok"
  exit 0
fi

if [ "$cmd" = 'echo $HOME' ]; then
  echo "$MOCK_REMOTE_HOME"
  exit 0
fi

if [[ "$cmd" =~ which\ knot ]]; then
  echo "$MOCK_REMOTE_HOME/.local/share/knot-mesh/bin/knot"
  exit 0
fi

if [[ "$cmd" =~ readlink\ -f ]]; then
  echo "$MOCK_REMOTE_HOME/.local/share/knot-mesh/bin/knot"
  exit 0
fi

if [[ "$cmd" =~ command\ -v\ rsync ]]; then
  exit 1 # simulate minimal system without rsync
fi

if [[ "$cmd" =~ knot\ sync ]]; then
  echo "[✓] Mock remote knot sync executed on $target"
  exit 0
fi

export HOME="$MOCK_REMOTE_HOME"
cd "$MOCK_REMOTE_HOME"
eval "$cmd"
exit 0
MOCK_SSH_EOF
chmod +x "$MOCK_BIN/ssh"

cat << 'MOCK_SYS_EOF' > "$MOCK_BIN/systemctl"
#!/usr/bin/env bash
exit 0
MOCK_SYS_EOF
chmod +x "$MOCK_BIN/systemctl"

# Source modules with stubs
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/swarm_sync.sh"

# Mock functions that would touch local desktop environment
deskflow_configure() { return 0; }
kdeconnect_sync_mesh() { return 0; }
ssh_sync_authorized_keys() { return 0; }
ssh_sync_client_config() { return 0; }
sudo() { return 0; }

# Test Anchor Push
swarm_sync_anchor_push "laptop" "testswarm" "$HOME/.config/knot/swarms/testswarm/nodes" "$HOME/.config/knot/swarms/testswarm/topology.json" "$HOME/.config/knot/swarms/testswarm/swarm.conf"

REMOTE_SWARM_DIR="$MOCK_REMOTE_HOME/.config/knot/swarms/testswarm"
if [ ! -f "$REMOTE_SWARM_DIR/topology.json" ]; then
  echo "Error: topology.json was not pushed to remote strand!" >&2
  exit 1
fi

if [ ! -f "$REMOTE_SWARM_DIR/nodes/desktop.json" ] || [ ! -f "$REMOTE_SWARM_DIR/nodes/laptop.json" ]; then
  echo "Error: node manifests were not pushed to remote strand!" >&2
  exit 1
fi

if [ ! -f "$REMOTE_SWARM_DIR/swarm.conf" ]; then
  echo "Error: swarm.conf was not pushed to remote strand!" >&2
  exit 1
fi

echo "  -> swarm_sync_anchor_push distributed manifests, topology, and profile: OK"

# Test Strand Pull
# Switch HOME to simulate Strand pulling from Anchor
export HOME="$TMP_DIR/strand_home"
mkdir -p "$HOME/.local/state/knot" "$HOME/.config/knot/swarms/testswarm"
echo "testswarm" > "$HOME/.local/state/knot/active_swarm"

# Re-point MOCK_REMOTE_HOME to Anchor's directory ($TMP_DIR/home)
export MOCK_REMOTE_HOME="$TMP_DIR/home"

swarm_sync_strand_pull

STRAND_PULL_DIR="$HOME/.config/knot/swarms/testswarm"
if [ ! -f "$STRAND_PULL_DIR/topology.json" ]; then
  echo "Error: strand pull did not retrieve topology.json!" >&2
  exit 1
fi

if [ ! -f "$STRAND_PULL_DIR/nodes/desktop.json" ]; then
  echo "Error: strand pull did not retrieve node manifests!" >&2
  exit 1
fi

echo "  -> swarm_sync_strand_pull retrieved topology and node manifests: OK"

echo "=== [Test 4] CLI Help & Option Dispatch Verification ==="
HELP_OUT="$("$KNOT_ROOT/bin/knot" --help)"
if ! echo "$HELP_OUT" | grep -q "knot sync \[--all | <node_id>\]"; then
  echo "Error: knot sync usage not found in help text!" >&2
  exit 1
fi
echo "  -> CLI usage output contains 'knot sync [--all | <node_id>]': OK"

echo "=== [✓] ALL SWARM SYNC TESTS PASSED! ==="
