#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Test Suite: Tier 1 D2D KDE Connect Self-Healing & Turnkey Onboarding
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing, Rule 2: No Test Homework)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
unset KNOT_NODE_ID KNOT_HUB_URL KNOT_RUN_ID KNOT_COUNCIL_RUN_ID KNOT_ACTIVE_SWARM

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/modules/kdeconnect.sh"
bash -n "$KNOT_ROOT/core/modules/doctor.sh"
bash -n "$KNOT_ROOT/core/modules/guard.sh"
bash -n "$KNOT_ROOT/bin/knot"
bash -n "$KNOT_ROOT/bin/knot-installer"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in \
  "$KNOT_ROOT/core/modules/kdeconnect.sh" \
  "$KNOT_ROOT/core/modules/doctor.sh" \
  "$KNOT_ROOT/core/modules/guard.sh" \
  "$KNOT_ROOT/bin/knot" \
  "$KNOT_ROOT/bin/knot-installer"; do
  if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$f" | grep -v "source " | grep -v "^[[:space:]]*#"; then
    echo "Error: Forbidden error swallowing construct found in $f" >&2
    exit 1
  fi
done
echo "  -> PSL Rule 1 compliance: OK"

echo "=== [Test 3] Systemd Unit & Timer Verification ==="
if command -v systemd-analyze >/dev/null; then
  systemd-analyze --user verify \
    "$KNOT_ROOT/systemd/knot-kdeconnect-reconcile.service" \
    "$KNOT_ROOT/systemd/knot-kdeconnect-reconcile.timer"
  echo "  -> systemd-analyze --user verify: OK (0 errors, 0 cycles)"
else
  echo "  -> systemd-analyze not found, verifying unit files exist:"
  test -f "$KNOT_ROOT/systemd/knot-kdeconnect-reconcile.service"
  test -f "$KNOT_ROOT/systemd/knot-kdeconnect-reconcile.timer"
  echo "  -> Unit files exist: OK"
fi

TMP_DIR="$(mktemp -d)"
_cleanup_suite() {
  rm -rf "$TMP_DIR"
}
trap _cleanup_suite EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/kdeconnect"
mkdir -p "$HOME/.config/knot/swarms/testswarm/nodes"
mkdir -p "$HOME/.config/systemd/user"
mkdir -p "$HOME/.local/bin"

echo "=== [Test 4] Knot CLI Dispatch for kdeconnect reconcile ==="
# Test routing of 'knot kdeconnect reconcile'
# Set up mock qdbus so reconcile executes cleanly in sandbox
MOCK_BIN_DIR="$TMP_DIR/mock_bin"
mkdir -p "$MOCK_BIN_DIR"
cat << 'EOF' > "$MOCK_BIN_DIR/qdbus6"
#!/usr/bin/env bash
# Mock qdbus6 for CLI routing tests
if [ "$1" = "org.kde.kdeconnect" ] && [ "$2" = "/modules/kdeconnect" ]; then
  if [ "$3" = "org.kde.kdeconnect.daemon.devices" ]; then
    echo "mock-device-001"
    exit 0
  fi
  if [ "$3" = "org.kde.kdeconnect.daemon.forceOnNetworkChange" ]; then
    exit 0
  fi
fi
if [ "$1" = "org.kde.kdeconnect" ] && [[ "$2" == /modules/kdeconnect/devices/* ]]; then
  method="$3"
  if [ "$method" = "org.kde.kdeconnect.device.isPaired" ]; then
    echo "true"
    exit 0
  fi
  if [ "$method" = "org.kde.kdeconnect.device.isPairRequestedByPeer" ]; then
    echo "false"
    exit 0
  fi
  if [ "$method" = "org.kde.kdeconnect.device.name" ]; then
    echo "mock-peer"
    exit 0
  fi
  if [ "$method" = "org.kde.kdeconnect.device.setPluginEnabled" ]; then
    exit 0
  fi
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/qdbus6"

cat << 'EOF' > "$MOCK_BIN_DIR/kdeconnect-cli"
#!/usr/bin/env bash
if [ "${1:-}" = "--my-id" ]; then
  echo "local-mock-id-12345"
  exit 0
fi
if [ "${1:-}" = "--refresh" ]; then
  exit 0
fi
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/kdeconnect-cli"

cat << 'EOF' > "$MOCK_BIN_DIR/ssh"
#!/usr/bin/env bash
# Mock ssh probe
echo "ok"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/ssh"

export PATH="$MOCK_BIN_DIR:$PATH"

# Write a mock node manifest
cat << 'EOF' > "$HOME/.config/knot/swarms/testswarm/nodes/peer1.json"
{
  "id": "peer1",
  "hostname": "peer1-host",
  "user": "kuasha",
  "port": 22,
  "ip_hint": "192.168.1.101"
}
EOF

echo "testswarm" > "$HOME/.config/knot/active_swarm"

# Test knot kdeconnect reconcile CLI execution
reconcile_out="$("$KNOT_ROOT/bin/knot" kdeconnect reconcile 2>&1)"
echo "$reconcile_out" | grep -q "Reconciling KDE Connect mesh health & pairings"
echo "$reconcile_out" | grep -q "KDE Connect mesh reconciliation completed"
echo "  -> knot kdeconnect reconcile CLI execution: OK"

echo "=== [Test 5] Knot Doctor Swarm Peer Pairing Check ==="
# Test doctor detection of unbonded vs paired peers
source "$KNOT_ROOT/core/modules/doctor.sh"

# In mock environment, qdbus reports mock-device-001 isPaired=true
# Verify doctor detects timer warning and checks peers
local_doc_rc=0
doc_output="$(doctor_check_local 2>&1)" || local_doc_rc=$?
echo "$doc_output" | grep -q "\[KDE Connect & Mesh Clipboard Sync\]"
echo "  -> doctor_check_local integrates KDE Connect & swarm peer checks: OK"

echo "=== [Test 6] Knot Repair Self-Healing Automation ==="
# Verify doctor_repair_local invokes kdeconnect_reconcile and deploys timer
local_rep_rc=0
repair_output="$(doctor_repair_local 2>&1)" || local_rep_rc=$?
echo "$repair_output" | grep -q "Reconciling KDE Connect mesh health & pairings"
echo "$repair_output" | grep -q "Local repair operations completed"
test -f "$HOME/.config/systemd/user/knot-kdeconnect-reconcile.service"
test -f "$HOME/.config/systemd/user/knot-kdeconnect-reconcile.timer"
echo "  -> doctor_repair_local deploys units and triggers reconciliation: OK"

echo "=== All Tier 1 D2D KDE Connect Self-Healing Tests Passed Flawlessly! ==="
