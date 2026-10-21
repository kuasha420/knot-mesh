#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Swarm Sync Module & CLI Orchestration (Issue #38)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/modules/swarm_sync.sh"
bash -n "$KNOT_ROOT/bin/knot"
echo "  -> swarm_sync.sh & bin/knot syntax: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
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
echo "  -> PSL Rule 1 Zero Error Swallowing compliance: OK"

echo "=== [Test 2b] Legacy Registry Cleanliness Audit ==="
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
if [ "${MOCK_SSH_FAIL:-0}" -eq 1 ]; then
  exit 1
fi
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
  if [ "${MOCK_ENABLE_RSYNC:-0}" -eq 1 ]; then
    echo "/usr/bin/rsync"
    exit 0
  else
    exit 1 # simulate minimal system without rsync
  fi
fi

if [[ "$cmd" =~ knot.*sync ]]; then
  echo "[✓] Mock remote knot sync executed on $target"
  exit 0
fi

if [[ "$cmd" =~ mirrorlist ]]; then
  mkdir -p "$MOCK_REMOTE_HOME/etc/pacman.d"
  cat > "$MOCK_REMOTE_HOME/etc/pacman.d/mirrorlist"
  exit 0
fi

if [[ "$cmd" =~ infocmp ]]; then
  exit 1 # simulate missing terminfo on remote strand
fi

if [[ "$cmd" =~ tic ]]; then
  mkdir -p "$MOCK_REMOTE_HOME/.terminfo"
  exit 0
fi

export HOME="$MOCK_REMOTE_HOME"
cd "$MOCK_REMOTE_HOME"
eval "$cmd"
exit 0
MOCK_SSH_EOF
chmod +x "$MOCK_BIN/ssh"

cat << 'MOCK_RSYNC_EOF' > "$MOCK_BIN/rsync"
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${RSYNC_LOG:-}" ]; then
  echo "$*" >> "$RSYNC_LOG"
fi
if [ -x /usr/bin/rsync ]; then
  exec /usr/bin/rsync "$@"
fi
exit 0
MOCK_RSYNC_EOF
chmod +x "$MOCK_BIN/rsync"

cat << 'MOCK_CURL_EOF' > "$MOCK_BIN/curl"
#!/usr/bin/env bash
set -euo pipefail
url=""
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done

if [[ "$url" =~ /topology ]]; then
  cat << 'TOPO' > "${out:-/dev/stdout}"
{
  "anchor": "desktop",
  "screens": ["desktop", "laptop"]
}
TOPO
  exit 0
fi

if [[ "$url" =~ /nodes ]]; then
  cat << 'NODES' > "${out:-/dev/stdout}"
[
  {
    "id": "desktop",
    "hostname": "test-anchor",
    "role": "anchor",
    "port": 42069,
    "user": "anchoruser"
  },
  {
    "id": "laptop",
    "hostname": "test-strand",
    "role": "strand",
    "port": 22,
    "user": "stranduser"
  }
]
NODES
  exit 0
fi

exit 1
MOCK_CURL_EOF
chmod +x "$MOCK_BIN/curl"

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
if ! echo "$HELP_OUT" | grep -F -q "knot sync [--all | <node_id>]"; then
  echo "Error: knot sync usage not found in help text!" >&2
  exit 1
fi
echo "  -> CLI usage output contains 'knot sync [--all | <node_id>]': OK"

echo "=== [Test 5] knot sync --mirrors Verification (Issue #79) ==="
export HOME="$TMP_DIR/home"
MOCK_MIRRORLIST="$TMP_DIR/mirrorlist_test"
echo "Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch" > "$MOCK_MIRRORLIST"
export KNOT_PACMAN_MIRRORLIST="$MOCK_MIRRORLIST"

# 1. Success case
swarm_sync_mirrors "laptop"
if [ ! -f "$MOCK_REMOTE_HOME/etc/pacman.d/mirrorlist" ]; then
  echo "Error: mirrorlist was not pushed to remote strand!" >&2
  exit 1
fi
if ! grep -q "rackspace" "$MOCK_REMOTE_HOME/etc/pacman.d/mirrorlist"; then
  echo "Error: remote mirrorlist contents do not match source!" >&2
  exit 1
fi

# 2. Failure case: missing mirrorlist source must return non-zero exit code
KNOT_PACMAN_MIRRORLIST="$TMP_DIR/nonexistent_mirrorlist"
if swarm_sync_mirrors "laptop"; then
  echo "Error: swarm_sync_mirrors must exit non-zero when source is missing!" >&2
  exit 1
fi
export KNOT_PACMAN_MIRRORLIST="$MOCK_MIRRORLIST"

echo "  -> swarm_sync_mirrors successfully distributed mirrorlist and enforced failure transparency: OK"

echo "=== [Test 6] knot sync --terminfo Verification (Issue #64) ==="
swarm_sync_terminfo "laptop"
if [ ! -d "$MOCK_REMOTE_HOME/.terminfo" ]; then
  echo "Error: terminfo directory was not created on remote strand!" >&2
  exit 1
fi
echo "=== [Test 7] Transport A: Primary Rsync Push Deletion Parity (Issue #84) ==="
export HOME="$TMP_DIR/home"
export MOCK_REMOTE_HOME="$TMP_DIR/remote_home"
REMOTE_SWARM_DIR="$MOCK_REMOTE_HOME/.config/knot/swarms/testswarm"
mkdir -p "$REMOTE_SWARM_DIR/nodes"

# Seed a decommissioned node manifest on remote strand
echo '{"id":"decommissioned_a","role":"strand"}' > "$REMOTE_SWARM_DIR/nodes/decommissioned_a.json"

# Ensure Anchor nodes directory does NOT contain the decommissioned node
if [ -f "$HOME/.config/knot/swarms/testswarm/nodes/decommissioned_a.json" ]; then
  rm -f "$HOME/.config/knot/swarms/testswarm/nodes/decommissioned_a.json"
fi

export MOCK_ENABLE_RSYNC=1
export RSYNC_LOG="$TMP_DIR/rsync_args.log"
if [ -f "$RSYNC_LOG" ]; then
  rm -f "$RSYNC_LOG"
fi

swarm_sync_anchor_push "laptop" "testswarm" "$HOME/.config/knot/swarms/testswarm/nodes" "$HOME/.config/knot/swarms/testswarm/topology.json" "$HOME/.config/knot/swarms/testswarm/swarm.conf"

# Assertion 1: Assert --delete flag was passed to rsync
if [ ! -f "$RSYNC_LOG" ] || ! grep -q -- "--delete" "$RSYNC_LOG"; then
  echo "Error: rsync push was not invoked with --delete flag!" >&2
  exit 1
fi

# Assertion 2: Stale manifest must be deleted on remote strand
if [ -f "$REMOTE_SWARM_DIR/nodes/decommissioned_a.json" ]; then
  echo "Error: stale manifest 'decommissioned_a.json' was not pruned by rsync push on remote strand!" >&2
  exit 1
fi

# Assertion 3: Active manifests must be present on remote strand
if [ ! -f "$REMOTE_SWARM_DIR/nodes/desktop.json" ] || [ ! -f "$REMOTE_SWARM_DIR/nodes/laptop.json" ]; then
  echo "Error: active manifests missing on remote strand after rsync push!" >&2
  exit 1
fi

export MOCK_ENABLE_RSYNC=0
echo "  -> Primary rsync push deletion parity verified (--delete passed & remote manifest removed): OK"

echo "=== [Test 8] Transport B: Streaming Tar Fallback Push Deletion Parity (Issue #84) ==="
export HOME="$TMP_DIR/home"
export MOCK_REMOTE_HOME="$TMP_DIR/remote_home"
REMOTE_SWARM_DIR="$MOCK_REMOTE_HOME/.config/knot/swarms/testswarm"

# Seed a decommissioned node manifest on remote strand
echo '{"id":"decommissioned_b","role":"strand"}' > "$REMOTE_SWARM_DIR/nodes/decommissioned_b.json"

# Disable rsync to force streaming tar fallback
export MOCK_ENABLE_RSYNC=0

swarm_sync_anchor_push "laptop" "testswarm" "$HOME/.config/knot/swarms/testswarm/nodes" "$HOME/.config/knot/swarms/testswarm/topology.json" "$HOME/.config/knot/swarms/testswarm/swarm.conf"

# Assertion 1: Stale manifest must be deleted on remote strand
if [ -f "$REMOTE_SWARM_DIR/nodes/decommissioned_b.json" ]; then
  echo "Error: stale manifest 'decommissioned_b.json' was not pruned by streaming tar fallback push!" >&2
  exit 1
fi

# Assertion 2: Active manifests must be present on remote strand
if [ ! -f "$REMOTE_SWARM_DIR/nodes/desktop.json" ] || [ ! -f "$REMOTE_SWARM_DIR/nodes/laptop.json" ]; then
  echo "Error: active manifests missing on remote strand after tar fallback push!" >&2
  exit 1
fi

echo "  -> Streaming tar fallback push deletion parity verified (stale node manifest removed on strand): OK"

echo "=== [Test 9] Transport C: Strand SSH Tar Pull Deletion Parity (Issue #84) ==="
export HOME="$TMP_DIR/strand_home"
export MOCK_REMOTE_HOME="$TMP_DIR/home"
STRAND_SWARM_DIR="$HOME/.config/knot/swarms/testswarm"
mkdir -p "$STRAND_SWARM_DIR/nodes"

# Seed a decommissioned node manifest locally on strand
echo '{"id":"decommissioned_c","role":"strand"}' > "$STRAND_SWARM_DIR/nodes/decommissioned_c.json"

# Ensure Anchor does NOT contain the decommissioned node
if [ -f "$MOCK_REMOTE_HOME/.config/knot/swarms/testswarm/nodes/decommissioned_c.json" ]; then
  rm -f "$MOCK_REMOTE_HOME/.config/knot/swarms/testswarm/nodes/decommissioned_c.json"
fi

export MOCK_SSH_FAIL=0

swarm_sync_strand_pull

# Assertion 1: Stale manifest must be pruned locally on the strand
if [ -f "$STRAND_SWARM_DIR/nodes/decommissioned_c.json" ]; then
  echo "Error: stale manifest 'decommissioned_c.json' was not pruned by strand SSH tar pull!" >&2
  exit 1
fi

# Assertion 2: Active manifests must be present on strand
if [ ! -f "$STRAND_SWARM_DIR/nodes/desktop.json" ] || [ ! -f "$STRAND_SWARM_DIR/nodes/laptop.json" ]; then
  echo "Error: active manifests missing on strand after SSH tar pull!" >&2
  exit 1
fi

echo "  -> Strand SSH tar pull deletion parity verified (stale node manifest removed locally): OK"

echo "=== [Test 10] Transport D: Anchor Hub API Pull Deletion Parity & Zero Ghost Status (Issue #84) ==="
export HOME="$TMP_DIR/strand_home"
STRAND_SWARM_DIR="$HOME/.config/knot/swarms/testswarm"

# Seed a decommissioned node manifest locally on strand
echo '{"id":"decommissioned_d","role":"strand"}' > "$STRAND_SWARM_DIR/nodes/decommissioned_d.json"

# Force SSH failure to trigger Anchor Hub API fallback
export MOCK_SSH_FAIL=1

swarm_sync_strand_pull

# Assertion 1: Stale manifest must be pruned locally by Hub API pull extractor
if [ -f "$STRAND_SWARM_DIR/nodes/decommissioned_d.json" ]; then
  echo "Error: stale manifest 'decommissioned_d.json' was not pruned by Anchor Hub API pull!" >&2
  exit 1
fi

# Assertion 2: Active manifests must be present on strand
if [ ! -f "$STRAND_SWARM_DIR/nodes/desktop.json" ] || [ ! -f "$STRAND_SWARM_DIR/nodes/laptop.json" ]; then
  echo "Error: active manifests missing on strand after Hub API pull!" >&2
  exit 1
fi

# Assertion 3: knot status must produce ZERO ghost or offline entries for decommissioned node
STATUS_OUT="$("$KNOT_ROOT/bin/knot" status 2>&1)"
if echo "$STATUS_OUT" | grep -q "decommissioned_d"; then
  echo "Error: knot status still displays decommissioned node 'decommissioned_d' as ghost or offline entry!" >&2
  exit 1
fi

export MOCK_SSH_FAIL=0
echo "  -> Anchor Hub API pull deletion parity & zero ghost status verified: OK"

echo "=== [Test 11] Compact / Non-Standard Manifest Discovery & Sync Resilience ==="
# Seed a compact single-line manifest with non-first id and custom attributes
echo '{"version": 1, "id": "compact-strand", "hostname": "compact-host", "role": "strand", "port": 2222, "user": "compactuser"}' > "$HOME/.config/knot/swarms/testswarm/nodes/compact-strand.json"

# Verify knot sync --mirrors correctly discovers compact-strand
MIRRORS_OUT="$(swarm_sync_mirrors --all 2>&1)"
if ! echo "$MIRRORS_OUT" | grep -q "Strand 'compact-strand'"; then
  echo "Error: swarm_sync_mirrors failed to discover compact-strand: $MIRRORS_OUT" >&2
  exit 1
fi
if echo "$MIRRORS_OUT" | grep -q "Strand 'id'"; then
  echo "Error: swarm_sync_mirrors targeted phantom node 'id' instead of compact-strand!" >&2
  exit 1
fi
echo "  -> swarm_sync_mirrors accurately discovers compact JSON manifest: OK"

# Verify knot sync --terminfo correctly discovers compact-strand
TERMINFO_OUT="$(swarm_sync_terminfo --all 2>&1)"
if ! echo "$TERMINFO_OUT" | grep -q "Strand 'compact-strand'"; then
  echo "Error: swarm_sync_terminfo failed to discover compact-strand: $TERMINFO_OUT" >&2
  exit 1
fi
if echo "$TERMINFO_OUT" | grep -q "Strand 'id'"; then
  echo "Error: swarm_sync_terminfo targeted phantom node 'id' instead of compact-strand!" >&2
  exit 1
fi
echo "  -> swarm_sync_terminfo accurately discovers compact JSON manifest: OK"

# Clean up compact-strand manifest
rm -f "$HOME/.config/knot/swarms/testswarm/nodes/compact-strand.json"

echo "=== [✓] ALL SWARM SYNC TESTS PASSED! ==="
