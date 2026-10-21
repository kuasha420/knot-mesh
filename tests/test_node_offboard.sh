#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Automated Verification Suite for Issue #81
# Safe Cluster Decommissioning: Knot Node Offboard / Remove
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing, Rule 2: No Test Homework)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
KNOT_BIN="$KNOT_ROOT/bin/knot"

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #81 Node Offboard Verification Suite"
echo "================================================================================"

test_total=0
test_passed=0

# -------------------------------------------------------------
# Test Assertion Helpers (Strict PSL Rule 1 Compliant)
# -------------------------------------------------------------
assert_cmd_succeeds() {
  local desc="$1"
  shift 1
  local cmd=("$@")

  test_total=$((test_total + 1))
  local actual_rc=0
  local output=""
  output="$("${cmd[@]}" 2>&1)" || actual_rc=$?

  if [ "$actual_rc" -ne 0 ]; then
    echo "  [FAIL] $desc: Expected exit code 0, got $actual_rc" >&2
    echo "         Command: ${cmd[*]}" >&2
    echo "         Output : $output" >&2
    exit 1
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (exit 0)"
}

assert_cmd_fails_with_code() {
  local expected_rc="$1"
  local expected_err_substr="$2"
  local desc="$3"
  shift 3
  local cmd=("$@")

  test_total=$((test_total + 1))
  local actual_rc=0
  local output=""
  output="$("${cmd[@]}" 2>&1)" || actual_rc=$?

  if [ "$actual_rc" -ne "$expected_rc" ]; then
    echo "  [FAIL] $desc: Expected exit code $expected_rc, got $actual_rc" >&2
    echo "         Command: ${cmd[*]}" >&2
    echo "         Output : $output" >&2
    exit 1
  fi

  if [ -n "$expected_err_substr" ]; then
    if ! echo "$output" | grep -qF "$expected_err_substr"; then
      echo "  [FAIL] $desc: Output did not contain expected substring: '$expected_err_substr'" >&2
      echo "         Output : $output" >&2
      exit 1
    fi
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (exit $actual_rc as expected: matches '$expected_err_substr')"
}

assert_file_exists() {
  local file="$1"
  local desc="$2"
  test_total=$((test_total + 1))
  if [ ! -f "$file" ]; then
    echo "  [FAIL] $desc: Expected file does not exist: $file" >&2
    exit 1
  fi
  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (file exists: $(basename "$file"))"
}

assert_file_not_exists() {
  local file="$1"
  local desc="$2"
  test_total=$((test_total + 1))
  if [ -e "$file" ]; then
    echo "  [FAIL] $desc: File should have been removed: $file" >&2
    exit 1
  fi
  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (file cleanly deleted: $(basename "$file"))"
}

assert_topology_state() {
  local topo_file="$1"
  local expected_screens_csv="$2"
  local forbidden_node="$3"
  local desc="$4"

  test_total=$((test_total + 1))
  python3 - << 'PYEOF' "$topo_file" "$expected_screens_csv" "$forbidden_node" "$desc"
import json, sys

topo_file = sys.argv[1]
expected_screens = [s.strip() for s in sys.argv[2].split(",") if s.strip()]
forbidden_node = sys.argv[3]
desc = sys.argv[4]

try:
    with open(topo_file, "r", encoding="utf-8") as f:
        topo = json.load(f)
except Exception as e:
    sys.stderr.write(f"  [FAIL] {desc}: Failed to parse {topo_file}: {e}\n")
    sys.exit(1)

screens = topo.get("screens", [])
if screens != expected_screens:
    sys.stderr.write(f"  [FAIL] {desc}: Screens mismatch. Expected {expected_screens}, got {screens}\n")
    sys.exit(1)

if forbidden_node in screens:
    sys.stderr.write(f"  [FAIL] {desc}: Forbidden node '{forbidden_node}' still in screens: {screens}\n")
    sys.exit(1)

layout = topo.get("layout", {})
if forbidden_node in layout:
    sys.stderr.write(f"  [FAIL] {desc}: Forbidden node '{forbidden_node}' still present as top-level layout key\n")
    sys.exit(1)

for src, dirs in layout.items():
    if src == forbidden_node:
        sys.stderr.write(f"  [FAIL] {desc}: Forbidden source '{forbidden_node}' present in layout\n")
        sys.exit(1)
    if not isinstance(dirs, dict):
        continue
    for d, spec in dirs.items():
        specs = spec if isinstance(spec, list) else [spec]
        for s in specs:
            tgt = s.get("node") if isinstance(s, dict) else s
            if tgt == forbidden_node:
                sys.stderr.write(f"  [FAIL] {desc}: Forbidden target '{forbidden_node}' referenced in edge {src}.{d} -> {tgt}\n")
                sys.exit(1)

for link in topo.get("links", []):
    if link.get("from") == forbidden_node or link.get("to") == forbidden_node:
        sys.stderr.write(f"  [FAIL] {desc}: Forbidden node '{forbidden_node}' present in links list: {link}\n")
        sys.exit(1)

sys.exit(0)
PYEOF

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (screens=[$expected_screens_csv], '$forbidden_node' completely purged from topology)"
}

assert_ssh_clean() {
  local auth_file="$HOME/.ssh/authorized_keys"
  local conf_file="$HOME/.ssh/config"
  local forbidden_node="$1"
  local forbidden_key_substr="$2"
  local desc="$3"

  test_total=$((test_total + 1))
  if [ ! -f "$auth_file" ]; then
    echo "  [FAIL] $desc: Expected SSH authorized_keys file does not exist: $auth_file" >&2
    exit 1
  fi

  if [ ! -f "$conf_file" ]; then
    echo "  [FAIL] $desc: Expected SSH config file does not exist: $conf_file" >&2
    exit 1
  fi

  if grep -qF "$forbidden_key_substr" "$auth_file"; then
    echo "  [FAIL] $desc: Forbidden pubkey for '$forbidden_node' found in $auth_file" >&2
    exit 1
  fi

  if grep -qE "(^|[[:space:]])Host[[:space:]]+.*(^|[[:space:]])${forbidden_node}([[:space:]]|\.|$)" "$conf_file"; then
    echo "  [FAIL] $desc: Forbidden Host block for '$forbidden_node' found in $conf_file" >&2
    exit 1
  fi

  # Positive assertion: verify surviving node's pubkey ('laptop' / AAAAC3NzaC1lZDI1NTE5AAAAI_LAPTOP_KEY) remains present in $auth_file
  if ! grep -qF "AAAAC3NzaC1lZDI1NTE5AAAAI_LAPTOP_KEY" "$auth_file"; then
    echo "  [FAIL] $desc: Surviving pubkey for 'laptop' missing from $auth_file" >&2
    exit 1
  fi

  # Positive assertion: verify surviving Host block ('Host laptop') remains present in $conf_file
  if ! grep -qE "(^|[[:space:]])Host[[:space:]]+laptop([[:space:]]|$)" "$conf_file"; then
    echo "  [FAIL] $desc: Surviving Host block 'Host laptop' missing from $conf_file" >&2
    exit 1
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (SSH authorized_keys & ~/.ssh/config free of '$forbidden_node', surviving 'laptop' verified)"
}

assert_deskflow_clean() {
  local conf_file="$HOME/.config/Deskflow/deskflow-server.conf"
  local forbidden_node="$1"
  local forbidden_host="$2"
  local desc="$3"

  test_total=$((test_total + 1))
  if [ ! -f "$conf_file" ]; then
    echo "  [FAIL] $desc: Expected Deskflow server configuration file does not exist: $conf_file" >&2
    exit 1
  fi

  if grep -qE "(^|[[:space:]])${forbidden_node}:" "$conf_file" || \
     grep -qE "(^|[[:space:]])${forbidden_host}:" "$conf_file" || \
     grep -qE "to[[:space:]]+${forbidden_node}([[:space:]]|$)" "$conf_file" || \
     grep -qE "to[[:space:]]+${forbidden_host}([[:space:]]|$)" "$conf_file"; then
    echo "  [FAIL] $desc: Forbidden Deskflow routing entry for '$forbidden_node' ($forbidden_host) found in $conf_file" >&2
    exit 1
  fi

  # Positive assertion: verify surviving screen ('laptop:') remains present in $conf_file
  if ! grep -qE "(^|[[:space:]])(laptop|laptop-thinkpad):" "$conf_file"; then
    echo "  [FAIL] $desc: Surviving screen 'laptop:' missing from Deskflow config: $conf_file" >&2
    exit 1
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (Deskflow server configuration free of '$forbidden_node' & '$forbidden_host', surviving screen 'laptop:' verified)"
}

# -------------------------------------------------------------
# Phase 0: Syntax and PSL Integrity Audits
# -------------------------------------------------------------
echo ""
echo "=== [Phase 0] Bash Syntax Verification & PSL Integrity Audit ==="
assert_cmd_succeeds "Syntax check core/modules/node.sh" bash -n "$KNOT_ROOT/core/modules/node.sh"
assert_cmd_succeeds "Syntax check bin/knot" bash -n "$KNOT_ROOT/bin/knot"

# PSL Rule 1 Audit on core/modules/node.sh
test_total=$((test_total + 1))
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:|subprocess\.DEVNULL)'
matches=""
if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$KNOT_ROOT/core/modules/node.sh" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
  matches=""
fi
if [ -n "$matches" ]; then
  echo "  [FAIL] Forbidden error-swallowing pattern detected in core/modules/node.sh:" >&2
  echo "$matches" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] PSL Rule 1 Zero Error Swallowing verified in core/modules/node.sh"

# -------------------------------------------------------------
# Phase 1: Test Environment Sandbox & Mocks Setup
# -------------------------------------------------------------
echo ""
echo "=== [Phase 1] Initializing Isolated Test Sandbox & Mocks ==="
TMP_DIR="$(mktemp -d)"
export TMP_DIR
_cleanup() {
  rm -rf "$TMP_DIR"
}
trap _cleanup EXIT

export HOME="$TMP_DIR/home"
export KNOT_RUNTIME_DIR="$TMP_DIR/run"
MOCK_BIN="$TMP_DIR/mock_bin"
LOG_DIR="$TMP_DIR/logs"
SWARM_DIR="$HOME/.config/knot/swarms/testswarm"
NODES_DIR="$SWARM_DIR/nodes"

mkdir -p "$MOCK_BIN" "$LOG_DIR" "$NODES_DIR" \
         "$HOME/.local/state/knot" "$HOME/.config/knot" \
         "$HOME/.ssh" "$HOME/.config/Deskflow" "$HOME/.config/kdeconnect" \
         "$KNOT_RUNTIME_DIR"

export PATH="$MOCK_BIN:$PATH"
unset KNOT_NODE_ID KNOT_ACTIVE_SWARM KNOT_HUB_URL KNOT_RUN_ID KNOT_COUNCIL_RUN_ID WAYLAND_DISPLAY

# 1. Mock ssh binary
cat << 'MOCK_SSH_EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "$*" >> "$LOG_DIR/ssh.log"

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

if [ -z "$cmd" ] || [ "$cmd" = "true" ] || [ "$cmd" = "echo ok" ] || [ "$cmd" = "echo ping" ]; then
  echo "ok"
  exit 0
fi

if [[ "$cmd" =~ unpair ]]; then
  echo "remote-unpair $target" >> "$LOG_DIR/remote_actions.log"
  exit 0
fi

if [[ "$cmd" =~ systemctl ]]; then
  echo "remote-systemctl $target" >> "$LOG_DIR/remote_actions.log"
  exit 0
fi

if [[ "$cmd" =~ rm\ -rf ]]; then
  echo "remote-prune $target" >> "$LOG_DIR/remote_actions.log"
  exit 0
fi

exit 0
MOCK_SSH_EOF
chmod +x "$MOCK_BIN/ssh"

# 2. Mock qdbus6 binary
cat << 'MOCK_QDBUS_EOF' > "$MOCK_BIN/qdbus6"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "qdbus6 $*" >> "$LOG_DIR/qdbus.log"

# Query devices list
if [ "$1" = "org.kde.kdeconnect" ] && [ "$2" = "/modules/kdeconnect" ]; then
  if [ "${3:-}" = "org.kde.kdeconnect.daemon.devices" ] || [ -z "${3:-}" ]; then
    echo "kde-device-steamdeck"
    echo "kde-device-rogally"
    echo "kde-device-laptop"
    exit 0
  fi
  if [ "${3:-}" = "org.kde.kdeconnect.daemon.forceOnNetworkChange" ]; then
    exit 0
  fi
fi

# Device-specific calls
if [ "$1" = "org.kde.kdeconnect" ] && [[ "$2" =~ ^/modules/kdeconnect/devices/([^/]+)$ ]]; then
  dev="${BASH_REMATCH[1]}"
  method="${3:-}"
  if [ "$method" = "org.kde.kdeconnect.device.name" ]; then
    case "$dev" in
      kde-device-steamdeck) echo "steamdeck-jupiter" ;;
      kde-device-rogally) echo "rog-ally-handheld" ;;
      kde-device-laptop) echo "laptop" ;;
      *) echo "$dev" ;;
    esac
    exit 0
  fi
  if [ "$method" = "org.kde.kdeconnect.device.isPaired" ]; then
    echo "true"
    exit 0
  fi
  if [ "$method" = "org.kde.kdeconnect.device.unpair" ]; then
    echo "$dev" >> "$LOG_DIR/kdeconnect_unpaired.log"
    exit 0
  fi
fi

exit 0
MOCK_QDBUS_EOF
chmod +x "$MOCK_BIN/qdbus6"
ln -sf "$MOCK_BIN/qdbus6" "$MOCK_BIN/qdbus"

# 3. Mock kdeconnect-cli binary
cat << 'MOCK_KCLI_EOF' > "$MOCK_BIN/kdeconnect-cli"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "kdeconnect-cli $*" >> "$LOG_DIR/kdeconnect_cli.log"

if [ "${1:-}" = "--my-id" ]; then
  echo "local-mock-anchor-id"
  exit 0
fi

dev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --unpair)
      if [ -n "${2:-}" ] && [[ ! "$2" =~ ^- ]]; then
        dev="$2"
        shift 2
      else
        shift
      fi
      ;;
    -d)
      dev="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -n "$dev" ]; then
  echo "$dev" >> "$LOG_DIR/kdeconnect_unpaired.log"
fi

exit 0
MOCK_KCLI_EOF
chmod +x "$MOCK_BIN/kdeconnect-cli"

# 4. Mock systemctl binary
cat << 'MOCK_SYS_EOF' > "$MOCK_BIN/systemctl"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "systemctl $*" >> "$LOG_DIR/systemctl.log"
exit 0
MOCK_SYS_EOF
chmod +x "$MOCK_BIN/systemctl"

# 5. Mock sudo binary
cat << 'MOCK_SUDO_EOF' > "$MOCK_BIN/sudo"
#!/usr/bin/env bash
set -euo pipefail
exit 1
MOCK_SUDO_EOF
chmod +x "$MOCK_BIN/sudo"

# -------------------------------------------------------------
# Test Fixture Files Initialization
# -------------------------------------------------------------
cat << 'SWARM_EOF' > "$SWARM_DIR/swarm.conf"
SWARM_ID="testswarm"
SWARM_NAME="Test Swarm"
ANCHOR_ID="desktop"
ANCHOR_HOST="desktop-anchor"
HUB_PORT=4242
SWARM_EOF
cp "$SWARM_DIR/swarm.conf" "$HOME/.config/knot/swarms/testswarm.conf"

echo "testswarm" > "$HOME/.local/state/knot/active_swarm"
echo "testswarm" > "$HOME/.config/knot/active_swarm"
echo "desktop" > "$HOME/.config/knot/node_id"

# Seed KDE Connect configuration fixture
cat << 'KDE_EOF' > "$HOME/.config/kdeconnect/config"
[General]
customDevices=192.168.1.10,192.168.1.20,192.168.1.30
KDE_EOF

# 4 Node Manifests
cat << 'NODE_EOF' > "$NODES_DIR/desktop.json"
{
  "id": "desktop",
  "hostname": "desktop-anchor",
  "role": "anchor",
  "port": 22,
  "user": "anchoruser",
  "ip_hint": "192.168.1.10",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_DESKTOP_KEY desktop@mesh",
  "display": { "resolution": "2560x1440" }
}
NODE_EOF

cat << 'NODE_EOF' > "$NODES_DIR/laptop.json"
{
  "id": "laptop",
  "hostname": "laptop",
  "role": "strand",
  "port": 22,
  "user": "laptopuser",
  "ip_hint": "192.168.1.11",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_LAPTOP_KEY laptop@mesh",
  "display": { "resolution": "1920x1080" }
}
NODE_EOF

cat << 'NODE_EOF' > "$NODES_DIR/steamdeck.json"
{
  "id": "steamdeck",
  "hostname": "steamdeck-jupiter",
  "role": "strand",
  "port": 22,
  "user": "deck",
  "ip_hint": "192.168.1.20",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_STEAMDECK_KEY deck@steamdeck",
  "display": { "resolution": "1280x800" }
}
NODE_EOF

cat << 'NODE_EOF' > "$NODES_DIR/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "rog-ally-handheld",
  "role": "strand",
  "port": 22,
  "user": "ally",
  "ip_hint": "192.168.1.30",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_ROGALLY_KEY ally@rogally",
  "display": { "resolution": "1920x1080" }
}
NODE_EOF

# Sample Declarative Topology with Sliced Fractional Spans
TOPO_FILE="$SWARM_DIR/topology.json"
cat << 'TOPO_EOF' > "$TOPO_FILE"
{
  "anchor": "desktop",
  "screens": ["desktop", "laptop", "steamdeck", "rog-ally"],
  "layout": {
    "desktop": {
      "left": {
        "node": "laptop",
        "span": [0, 100],
        "target_span": [0, 100]
      },
      "right": [
        {
          "node": "steamdeck",
          "span": [0, 50],
          "target_span": [0, 100]
        },
        {
          "node": "rog-ally",
          "span": [50, 100],
          "target_span": [0, 100]
        }
      ]
    },
    "laptop": {
      "right": {
        "node": "desktop",
        "span": [0, 100],
        "target_span": [0, 100]
      }
    },
    "steamdeck": {
      "left": {
        "node": "desktop",
        "span": [0, 100],
        "target_span": [0, 50]
      }
    },
    "rog-ally": {
      "left": {
        "node": "desktop",
        "span": [0, 100],
        "target_span": [50, 100]
      }
    }
  },
  "links": [
    {"from": "desktop", "to": "steamdeck"},
    {"from": "desktop", "to": "laptop"}
  ],
  "locked": false
}
TOPO_EOF

# Compile Baseline Subsystem State
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/ssh.sh"
source "$KNOT_ROOT/core/modules/deskflow.sh"
source "$KNOT_ROOT/core/modules/node.sh"

ssh_sync_authorized_keys
ssh_sync_client_config
deskflow_compile_server_config "unlocked"

# Verify Baseline Setup Contains All 4 Nodes
assert_file_exists "$NODES_DIR/desktop.json" "Baseline desktop manifest"
assert_file_exists "$NODES_DIR/laptop.json" "Baseline laptop manifest"
assert_file_exists "$NODES_DIR/steamdeck.json" "Baseline steamdeck manifest"
assert_file_exists "$NODES_DIR/rog-ally.json" "Baseline rog-ally manifest"
assert_file_exists "$HOME/.ssh/authorized_keys" "Baseline authorized_keys"
assert_file_exists "$HOME/.ssh/config" "Baseline ssh config"
assert_file_exists "$HOME/.config/Deskflow/deskflow-server.conf" "Baseline deskflow conf"
assert_file_exists "$HOME/.config/kdeconnect/config" "Baseline kdeconnect config"

echo "  -> Baseline environment configured successfully."

# -------------------------------------------------------------
# Test 1: CLI Help Flag Normalization & Option Dispatch
# -------------------------------------------------------------
echo ""
echo "=== [Test 1] CLI Help Flag Normalization & Option Dispatch ==="
assert_cmd_succeeds "knot node -h returns exit 0" "$KNOT_BIN" node -h
assert_cmd_succeeds "knot node --help returns exit 0" "$KNOT_BIN" node --help
assert_cmd_succeeds "knot node remove -h returns exit 0" "$KNOT_BIN" node remove -h
assert_cmd_succeeds "knot node remove --help returns exit 0" "$KNOT_BIN" node remove --help
assert_cmd_succeeds "knot offboard -h returns exit 0" "$KNOT_BIN" offboard -h
assert_cmd_succeeds "knot offboard --help returns exit 0" "$KNOT_BIN" offboard --help

assert_cmd_fails_with_code 1 "Unknown node subcommand" \
  "knot node unknown_cmd fails with exit 1" "$KNOT_BIN" node unknown_cmd

assert_cmd_fails_with_code 1 "Usage:" \
  "knot node remove with missing argument fails with exit 1" "$KNOT_BIN" node remove

assert_cmd_fails_with_code 1 "Usage:" \
  "knot offboard with missing argument fails with exit 1" "$KNOT_BIN" offboard

# -------------------------------------------------------------
# Test 2: Active Anchor Removal Protection & Invariant Preservation
# -------------------------------------------------------------
echo ""
echo "=== [Test 2] Active Anchor Removal Protection ==="
ANCHOR_ERR_MSG="Cannot remove active Anchor node 'desktop'"

assert_cmd_fails_with_code 1 "$ANCHOR_ERR_MSG" \
  "knot node remove desktop is rejected with exit 1" "$KNOT_BIN" node remove desktop

assert_cmd_fails_with_code 1 "$ANCHOR_ERR_MSG" \
  "knot offboard desktop alias is rejected with exit 1" "$KNOT_BIN" offboard desktop

# Assert Zero State Mutation After Attempted Anchor Removal
assert_file_exists "$NODES_DIR/desktop.json" "Anchor manifest preserved"
assert_file_exists "$NODES_DIR/laptop.json" "Strand laptop manifest preserved"
assert_file_exists "$NODES_DIR/steamdeck.json" "Strand steamdeck manifest preserved"
assert_file_exists "$NODES_DIR/rog-ally.json" "Strand rog-ally manifest preserved"
assert_topology_state "$TOPO_FILE" "desktop,laptop,steamdeck,rog-ally" "none" "Topology unmutated after anchor rejection"

if [ -f "$LOG_DIR/kdeconnect_unpaired.log" ]; then
  if grep -q "desktop" "$LOG_DIR/kdeconnect_unpaired.log"; then
    echo "  [FAIL] Unpair must not be called when anchor removal is rejected" >&2
    exit 1
  fi
fi
echo "  [PASS] Zero state mutation on rejected Anchor decommissioning"

# -------------------------------------------------------------
# Test 3: Non-Existent Node Removal Rejection
# -------------------------------------------------------------
echo ""
echo "=== [Test 3] Non-Existent Node Removal Rejection ==="
assert_cmd_fails_with_code 1 "not found in active swarm" \
  "knot node remove phantom-node is rejected with exit 1" "$KNOT_BIN" node remove phantom-node
assert_cmd_fails_with_code 1 "Invalid node identifier" \
  "knot node remove with path traversal is rejected with exit 1" "$KNOT_BIN" node remove ../phantom-node

# Assert Zero State Mutation
assert_file_exists "$NODES_DIR/steamdeck.json" "Steamdeck manifest untouched"
assert_topology_state "$TOPO_FILE" "desktop,laptop,steamdeck,rog-ally" "none" "Topology unmutated after missing node rejection"

# -------------------------------------------------------------
# Test 4: Successful Strand Removal (knot node remove steamdeck)
# -------------------------------------------------------------
echo ""
echo "=== [Test 4] Successful Strand Removal (knot node remove steamdeck) ==="
# Setup a sample muted state file to verify cleanup
touch "$HOME/.local/state/knot/vmon_muted_deskflow_steamdeck"

assert_cmd_succeeds "knot node remove steamdeck executes cleanly" \
  "$KNOT_BIN" node remove steamdeck

# 1. Assert Manifest Deleted
assert_file_not_exists "$NODES_DIR/steamdeck.json" "steamdeck manifest purged"
assert_file_exists "$NODES_DIR/desktop.json" "desktop manifest remains intact"
assert_file_exists "$NODES_DIR/laptop.json" "laptop manifest remains intact"
assert_file_exists "$NODES_DIR/rog-ally.json" "rog-ally manifest remains intact"

# 2. Assert Topology Pruned (screens, outgoing layout, incoming directional edges)
assert_topology_state "$TOPO_FILE" "desktop,laptop,rog-ally" "steamdeck" \
  "Topology screens and directional edges purged of steamdeck"

# Verify sliced span preservation for remaining sibling (rog-ally) in desktop.right
test_total=$((test_total + 1))
python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
right = topo.get("layout", {}).get("desktop", {}).get("right", [])
specs = right if isinstance(right, list) else [right]
ally_found = False
for s in specs:
    tgt = s.get("node") if isinstance(s, dict) else s
    if tgt == "rog-ally":
        ally_found = True
        span = s.get("span")
        if span != [50, 100]:
            sys.stderr.write(f"Span coordinates corrupted for rog-ally: {span}\n")
            sys.exit(1)
if not ally_found:
    sys.stderr.write("rog-ally was unexpectedly dropped from desktop right layout\n")
    sys.exit(1)
sys.exit(0)
PYEOF
test_passed=$((test_passed + 1))
echo "  [PASS] Fractional span coordinates [50, 100] preserved for sibling 'rog-ally'"

# 2b. Assert links in topology.json purged steamdeck while preserving desktop -> laptop
test_total=$((test_total + 1))
python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
links = topo.get("links", [])
deck_link = [l for l in links if l.get("from") == "steamdeck" or l.get("to") == "steamdeck"]
laptop_link = [l for l in links if l.get("from") == "desktop" and l.get("to") == "laptop"]

if deck_link:
    sys.stderr.write(f"steamdeck link was not purged from links: {deck_link}\n")
    sys.exit(1)
if not laptop_link:
    sys.stderr.write(f"Surviving link desktop -> laptop was unexpectedly purged: {links}\n")
    sys.exit(1)
sys.exit(0)
PYEOF
test_passed=$((test_passed + 1))
echo "  [PASS] Surviving link {'from': 'desktop', 'to': 'laptop'} preserved in links, steamdeck purged"

# 3. Assert SSH authorized_keys and config regenerated without steamdeck
assert_ssh_clean "steamdeck" "AAAAC3NzaC1lZDI1NTE5AAAAI_STEAMDECK_KEY" \
  "SSH authorized_keys and config regenerated without steamdeck"

# 4. Assert Deskflow configuration recompiled without steamdeck
assert_deskflow_clean "steamdeck" "steamdeck-jupiter" \
  "Deskflow server configuration recompiled without steamdeck"

# 5. Assert KDE Connect unpair called
test_total=$((test_total + 1))
if [ ! -f "$LOG_DIR/kdeconnect_unpaired.log" ] || ! grep -qE "(kde-device-steamdeck|steamdeck)" "$LOG_DIR/kdeconnect_unpaired.log"; then
  echo "  [FAIL] KDE Connect unpair was not called for steamdeck" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] KDE Connect unpair called for steamdeck"

# 5b. Assert KDE Connect customDevices pruned steamdeck IP (192.168.1.20)
test_total=$((test_total + 1))
kde_cfg="$HOME/.config/kdeconnect/config"
if [ ! -f "$kde_cfg" ]; then
  echo "  [FAIL] KDE Connect config file does not exist: $kde_cfg" >&2
  exit 1
fi
if ! grep -qF "customDevices=192.168.1.10,192.168.1.30" "$kde_cfg"; then
  echo "  [FAIL] KDE Connect customDevices was not correctly pruned. Expected 'customDevices=192.168.1.10,192.168.1.30':" >&2
  cat "$kde_cfg" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] KDE Connect customDevices pruned steamdeck IP (customDevices=192.168.1.10,192.168.1.30)"

# 6. Assert Muted marker file cleaned
assert_file_not_exists "$HOME/.local/state/knot/vmon_muted_deskflow_steamdeck" \
  "Deskflow muted marker file cleaned"

# 7. Assert Zero Ghost Status
test_total=$((test_total + 1))
status_out="$("$KNOT_BIN" status 2>&1)"
if echo "$status_out" | grep -q "steamdeck"; then
  echo "  [FAIL] Ghost status entry for steamdeck found in 'knot status':" >&2
  echo "$status_out" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] knot status shows zero ghost or offline entries for decommissioned steamdeck"

# -------------------------------------------------------------
# Test 5: Offboard CLI Alias Parity (knot offboard rog-ally)
# -------------------------------------------------------------
echo ""
echo "=== [Test 5] Offboard CLI Alias Parity (knot offboard rog-ally) ==="
assert_cmd_succeeds "knot offboard rog-ally executes cleanly" \
  "$KNOT_BIN" offboard rog-ally

# 1. Assert Manifest Deleted
assert_file_not_exists "$NODES_DIR/rog-ally.json" "rog-ally manifest purged"
assert_file_exists "$NODES_DIR/desktop.json" "desktop manifest remains intact"
assert_file_exists "$NODES_DIR/laptop.json" "laptop manifest remains intact"

# 2. Assert Topology Pruned (screens = [desktop, laptop])
assert_topology_state "$TOPO_FILE" "desktop,laptop" "rog-ally" \
  "Topology screens and directional edges purged of rog-ally"

# Assert desktop.right is completely pruned now that all right targets are gone
test_total=$((test_total + 1))
python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
desktop_layout = topo.get("layout", {}).get("desktop", {})
if "right" in desktop_layout and desktop_layout["right"]:
    sys.stderr.write(f"Empty direction 'right' was not pruned from desktop layout: {desktop_layout['right']}\n")
    sys.exit(1)
if "left" not in desktop_layout:
    sys.stderr.write("Valid direction 'left' pointing to laptop was erroneously dropped\n")
    sys.exit(1)
sys.exit(0)
PYEOF
test_passed=$((test_passed + 1))
echo "  [PASS] Empty direction 'right' pruned from desktop layout while 'left' -> laptop preserved"

# 3. Assert SSH authorized_keys and config regenerated without rog-ally
assert_ssh_clean "rog-ally" "AAAAC3NzaC1lZDI1NTE5AAAAI_ROGALLY_KEY" \
  "SSH authorized_keys and config regenerated without rog-ally"

# 4. Assert Deskflow configuration recompiled without rog-ally
assert_deskflow_clean "rog-ally" "rog-ally-handheld" \
  "Deskflow server configuration recompiled without rog-ally"

# 5. Assert KDE Connect unpair called for rog-ally
test_total=$((test_total + 1))
if [ ! -f "$LOG_DIR/kdeconnect_unpaired.log" ] || ! grep -qE "(kde-device-rogally|rog-ally)" "$LOG_DIR/kdeconnect_unpaired.log"; then
  echo "  [FAIL] KDE Connect unpair was not called for rog-ally" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] KDE Connect unpair called for rog-ally via offboard alias"

# -------------------------------------------------------------
# Test 6: Remote Strand Purge Flag (--purge-remote)
# -------------------------------------------------------------
echo ""
echo "=== [Test 6] Remote Strand Purge Flag (--purge-remote) ==="
# Setup a mock strand for remote testing
cat << 'NODE_EOF' > "$NODES_DIR/remote-node.json"
{
  "id": "remote-node",
  "hostname": "remote-node-host",
  "role": "strand",
  "port": 22,
  "user": "remoteuser",
  "ip_hint": "192.168.1.99",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_REMOTE_KEY remote@mesh"
}
NODE_EOF

python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
topo["screens"].append("remote-node")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(topo, f, indent=2)
PYEOF

# 6a. Reachable Remote Node
assert_cmd_succeeds "knot node remove remote-node --purge-remote executes cleanly" \
  "$KNOT_BIN" node remove remote-node --purge-remote

test_total=$((test_total + 1))
if [ ! -f "$LOG_DIR/remote_actions.log" ] || ! grep -q "remote-systemctl remote-node" "$LOG_DIR/remote_actions.log"; then
  echo "  [FAIL] Remote service teardown was not triggered for remote-node" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] Remote service teardown and prune verified over SSH"

# 6b. Unreachable Remote Node (Graceful Degrade)
cat << 'NODE_EOF' > "$NODES_DIR/offline-node.json"
{
  "id": "offline-node",
  "hostname": "offline-node-host",
  "role": "strand",
  "port": 22,
  "user": "offlineuser",
  "ip_hint": "192.168.1.98",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_OFFLINE_KEY offline@mesh"
}
NODE_EOF

python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
topo["screens"].append("offline-node")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(topo, f, indent=2)
PYEOF

export MOCK_SSH_FAIL=1
assert_cmd_succeeds "knot node remove offline-node --purge-remote warns but succeeds when SSH fails" \
  "$KNOT_BIN" node remove offline-node --purge-remote
export MOCK_SSH_FAIL=0

assert_file_not_exists "$NODES_DIR/offline-node.json" "offline-node manifest pruned despite SSH failure"
echo "  [PASS] Graceful fallback on unreachable remote node confirmed"

# -------------------------------------------------------------
# Test 7: Compact / Multi-Field JSON Manifest Resilience & Node Listing
# -------------------------------------------------------------
echo ""
echo "=== [Test 7] Compact JSON Manifest Resilience & Node Listing ==="
# Write single-line compact JSON with fields in non-standard order
echo '{"version": 1, "id": "compact-node", "hostname": "compact-host", "role": "strand", "port": 2222, "user": "compactuser", "ip_hint": "192.168.1.99"}' > "$NODES_DIR/compact-node.json"

list_out="$("$KNOT_BIN" node list 2>&1)"
test_total=$((test_total + 1))
if echo "$list_out" | grep -qE "compact-node[[:space:]]+strand[[:space:]]+compact-host"; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] knot node list extracts fields accurately from compact JSON manifest"
else
  echo "  [FAIL] knot node list failed to parse compact JSON manifest: $list_out" >&2
  exit 1
fi

python3 - << 'PYEOF' "$TOPO_FILE"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    topo = json.load(f)
topo["screens"].append("compact-node")
with open(sys.argv[1], "w", encoding="utf-8") as f:
    json.dump(topo, f, indent=2)
PYEOF

assert_cmd_succeeds "knot node remove compact-node --purge-remote handles compact manifest cleanly" \
  "$KNOT_BIN" node remove compact-node --purge-remote

assert_file_not_exists "$NODES_DIR/compact-node.json" "compact-node manifest pruned"

# -------------------------------------------------------------
# Summary & Test Verification
# -------------------------------------------------------------
echo ""
echo "================================================================================"
echo "✔ Node Offboarding Test Suite Passed: $test_passed / $test_total checks passed."
echo "================================================================================"
exit 0
