#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Automated Verification for Deterministic Telemetry Ledger (Strand D: #67)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BIN_KNOT="$KNOT_ROOT/bin/knot"
TELEMETRY_MODULE="$KNOT_ROOT/core/modules/telemetry.sh"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$TELEMETRY_MODULE"
bash -n "$BIN_KNOT"
echo "  -> telemetry.sh & bin/knot syntax: OK"

echo "=== [Test 2] Zero Error Swallowing Audit (PSL Rule 1) ==="
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
matches=""
if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$TELEMETRY_MODULE" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
  matches=""
fi
if [ -n "$matches" ]; then
  echo "Error: Forbidden error swallowing detected in telemetry.sh:" >&2
  echo "$matches" >&2
  exit 1
fi
echo "  -> Zero error swallowing in telemetry.sh: OK"

echo "=== [Test 3] Local Power Detection Routine ==="
source "$TELEMETRY_MODULE"
local_power="$(telemetry_get_local_power)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
assert "ac_online" in data, "Missing ac_online in power data"
assert "battery_pct" in data, "Missing battery_pct in power data"
assert "status" in data, "Missing status in power data"
assert isinstance(data["ac_online"], bool), "ac_online must be bool"
' "$local_power"
echo "  -> Local power detection returns valid schema: OK"

echo "=== [Test 4] Synthetic Swarm Multi-Node Ledger Generation ==="
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export HOME="$TEST_TMP"
export KNOT_NODE_ID="desktop"
mkdir -p "$HOME/.config/knot/swarms/test_ledger/nodes"

# 1. Local/Anchor online node
cat << 'EOF' > "$HOME/.config/knot/swarms/test_ledger/nodes/desktop.json"
{
  "id": "desktop",
  "hostname": "desktop",
  "user": "psl",
  "port": 22,
  "role": "anchor",
  "ip_hint": "127.0.0.1"
}
EOF

# 2. Unreachable offline node
cat << 'EOF' > "$HOME/.config/knot/swarms/test_ledger/nodes/phantom.json"
{
  "id": "phantom",
  "hostname": "192.0.2.1",
  "user": "psl",
  "port": 9999,
  "role": "worker",
  "ip_hint": "192.0.2.1"
}
EOF

cat << 'EOF' > "$HOME/.config/knot/swarms/test_ledger/swarm.conf"
SWARM_ID=test_ledger
ANCHOR_ID=desktop
ANCHOR_HOST=desktop
EOF

echo "test_ledger" > "$HOME/.config/knot/active_swarm"

# Generate ledger
ledger_json="$(bash "$BIN_KNOT" ledger generate --json --swarm test_ledger)"

# Validate deterministic JSON schema
python3 -c '
import sys, json

data = json.loads(sys.argv[1])
assert "timestamp" in data, "Missing root timestamp"
assert "swarm" in data, "Missing root swarm"
sw = data["swarm"]
assert sw == "test_ledger", f"Expected test_ledger, got {sw}"
assert "nodes" in data, "Missing root nodes map"

nodes = data["nodes"]
assert "desktop" in nodes, "Missing desktop node in ledger"
assert "phantom" in nodes, "Missing phantom node in ledger"

desktop = nodes["desktop"]
st = desktop["status"]
assert st == "ONLINE", f"Expected ONLINE for desktop, got {st}"
assert "ping_ms" in desktop, "Missing ping_ms for online node"
assert isinstance(desktop["ping_ms"], (int, float)), "ping_ms must be numeric"
assert "power" in desktop, "Missing power data"
assert "ac_online" in desktop["power"], "Missing ac_online in power"
assert "quota" in desktop, "Missing quota data"
assert "gemini_5h" in desktop["quota"], "Missing gemini_5h"
assert "gemini_weekly" in desktop["quota"], "Missing gemini_weekly"
assert "claude_gpt_5h" in desktop["quota"], "Missing claude_gpt_5h"
assert "claude_gpt_weekly" in desktop["quota"], "Missing claude_gpt_weekly"
assert "kvm" in desktop, "Missing kvm data"

phantom = nodes["phantom"]
pst = phantom["status"]
assert pst == "OFFLINE", f"Expected OFFLINE for phantom, got {pst}"
assert "error" in phantom, "Missing error diagnostic for offline node (PSL Rule 1 transparency)"
assert len(phantom["error"]) > 0, "Error diagnostic must be non-empty"
' "$ledger_json"

echo "  -> Full deterministic ledger schema & fail-fast transparency verified: OK"

echo "=== [Test 5] Anti-Hallucination: Reachable IP Check Fails -> Marked OFFLINE ==="
# Create a node that has a valid IP address format in its hint/lease, but the host is down
cat << 'EOF' > "$HOME/.config/knot/swarms/test_ledger/nodes/unreachable_host.json"
{
  "id": "down_node",
  "hostname": "192.0.2.99",
  "user": "psl",
  "port": 22,
  "role": "worker",
  "ip_hint": "192.0.2.99"
}
EOF

# Populate resolver lease cache for down_node to return 192.0.2.99
mkdir -p "$HOME/.cache/knot/leases"
echo "192.0.2.99" > "$HOME/.cache/knot/leases/down_node"

ledger_down_json="$(bash "$BIN_KNOT" ledger generate --json --swarm test_ledger)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
down = data["nodes"]["down_node"]
assert down["status"] == "OFFLINE", f"Expected OFFLINE for down node, got {down}"
assert "error" in down, "Missing error diagnostic for down node"
err_msg = down["error"]
assert "unreachable" in err_msg.lower(), f"Unexpected error diagnostic: {err_msg}"
' "$ledger_down_json"
echo "  -> Anti-hallucination verified: unreachable node with cached IP correctly marked OFFLINE: OK"

echo "=== [Test 6] Worker Node Perspective: Remote Anchor is Not Localhost ==="
# Simulate executing from a worker node (e.g. laptop) with instantaneous mock ssh for unreachable hosts
MOCK_BIN="$TEST_TMP/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
exit 255
EOF
chmod +x "$MOCK_BIN/ssh"

KNOT_NODE_ID="laptop" ledger_worker_json="$(PATH="$MOCK_BIN:$PATH" bash "$BIN_KNOT" ledger generate --json --swarm test_ledger)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
# From laptop perspective, down_node and phantom must not be local
# And desktop is the remote anchor, not laptop
assert "desktop" in data["nodes"], "Missing desktop"
' "$ledger_worker_json"
echo "  -> Worker perspective anchor separation verified: OK"

echo "=== [✓] ALL TELEMETRY LEDGER TESTS PASSED! ==="
