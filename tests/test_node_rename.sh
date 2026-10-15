#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Automated Verification Suite for Issue #82
# Atomic Identity Migration: Knot Node Rename
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing, Rule 2: No Test Homework)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
KNOT_BIN="$KNOT_ROOT/bin/knot"

echo "================================================================================"
echo ">>> Knot Mesh: Running Issue #82 Node Rename Verification Suite"
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

assert_manifest_state() {
  local manifest_file="$1"
  local expected_id="$2"
  local expected_host="$3"
  local desc="$4"

  test_total=$((test_total + 1))
  python3 - << 'PYEOF_INNER' "$manifest_file" "$expected_id" "$expected_host" "$desc"
import json, sys
m_file, exp_id, exp_host, desc = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

try:
    with open(m_file, "r", encoding="utf-8") as f:
        data = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write(f"  [FAIL] {desc}: Failed reading manifest {m_file}: {e}\n")
    sys.exit(1)

if data.get("id") != exp_id:
    sys.stderr.write(f"  [FAIL] {desc}: Expected id '{exp_id}', got '{data.get('id')}'\n")
    sys.exit(1)

if exp_host and data.get("hostname") != exp_host:
    sys.stderr.write(f"  [FAIL] {desc}: Expected hostname '{exp_host}', got '{data.get('hostname')}'\n")
    sys.exit(1)

sys.exit(0)
PYEOF_INNER
  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (manifest id='$expected_id', hostname='$expected_host')"
}

assert_topology_state() {
  local topo_file="$1"
  local expected_screens_csv="$2"
  local expected_anchor="$3"
  local old_id="$4"
  local new_id="$5"
  local desc="$6"

  test_total=$((test_total + 1))
  python3 - << 'PYEOF_INNER' "$topo_file" "$expected_screens_csv" "$expected_anchor" "$old_id" "$new_id" "$desc"
import json, sys
topo_file = sys.argv[1]
expected_screens = [s.strip() for s in sys.argv[2].split(",") if s.strip()]
expected_anchor = sys.argv[3]
old_id = sys.argv[4]
new_id = sys.argv[5]
desc = sys.argv[6]

try:
    with open(topo_file, "r", encoding="utf-8") as f:
        topo = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write(f"  [FAIL] {desc}: Failed reading topology {topo_file}: {e}\n")
    sys.exit(1)

# Check anchor
if expected_anchor and topo.get("anchor") != expected_anchor:
    sys.stderr.write(f"  [FAIL] {desc}: Anchor mismatch. Expected '{expected_anchor}', got '{topo.get('anchor')}'\n")
    sys.exit(1)

# Check screens
screens = topo.get("screens", [])
if screens != expected_screens:
    sys.stderr.write(f"  [FAIL] {desc}: Screens mismatch. Expected {expected_screens}, got {screens}\n")
    sys.exit(1)

if old_id in screens:
    sys.stderr.write(f"  [FAIL] {desc}: Old id '{old_id}' still present in screens: {screens}\n")
    sys.exit(1)

# Check layout keys
layout = topo.get("layout", {})
if old_id in layout:
    sys.stderr.write(f"  [FAIL] {desc}: Old id '{old_id}' still present as top-level layout key\n")
    sys.exit(1)

# Check directional edge targets across all nodes
for src, dirs in layout.items():
    if not isinstance(dirs, dict):
        continue
    for d, spec in dirs.items():
        specs = spec if isinstance(spec, list) else [spec]
        for s in specs:
            tgt = s.get("node") if isinstance(s, dict) else s
            if tgt == old_id:
                sys.stderr.write(f"  [FAIL] {desc}: Old id '{old_id}' referenced in edge {src}.{d} -> {tgt}\n")
                sys.exit(1)

# Check links list
for link in topo.get("links", []):
    if link.get("from") == old_id or link.get("to") == old_id or link.get("src") == old_id or link.get("dst") == old_id:
        sys.stderr.write(f"  [FAIL] {desc}: Old id '{old_id}' referenced in links: {link}\n")
        sys.exit(1)

# Verify fractional span preservation for desktop.right target pointing to new_id
if "desktop" in layout and "right" in layout["desktop"]:
    desktop_right = layout["desktop"]["right"]
    if isinstance(desktop_right, list):
        target_entry = next((item for item in desktop_right if isinstance(item, dict) and item.get("node") == new_id), None)
        if target_entry:
            if target_entry.get("span") != [0, 50] or target_entry.get("target_span") != [0, 100]:
                sys.stderr.write(f"  [FAIL] {desc}: Fractional span corrupted for {new_id}: {target_entry}\n")
                sys.exit(1)

sys.exit(0)
PYEOF_INNER
  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (screens=[$expected_screens_csv], anchor='$expected_anchor', '$old_id' migrated to '$new_id' with spans intact)"
}

assert_ssh_clean() {
  local conf_file="$HOME/.ssh/config"
  local old_id="$1"
  local new_id="$2"
  local desc="$3"

  test_total=$((test_total + 1))
  if [ ! -f "$conf_file" ]; then
    echo "  [FAIL] $desc: Expected SSH config file does not exist: $conf_file" >&2
    exit 1
  fi

  if grep -qE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?${old_id}([[:space:]]|\.|$)" "$conf_file"; then
    echo "  [FAIL] $desc: Stale Host block for '$old_id' found in $conf_file" >&2
    exit 1
  fi

  if ! grep -qE "^[[:space:]]*Host[[:space:]]+(.*[[:space:]])?${new_id}([[:space:]]|\.|$)" "$conf_file"; then
    echo "  [FAIL] $desc: Expected Host block for '$new_id' missing from $conf_file" >&2
    exit 1
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (SSH config has Host '$new_id' and zero occurrences of '$old_id')"
}

assert_deskflow_clean() {
  local conf_file="$1"
  local old_id="$2"
  local new_host="$3"
  local desc="$4"

  if [ $# -eq 3 ]; then
    conf_file="$HOME/.config/Deskflow/deskflow-server.conf"
    old_id="$1"
    new_host="$2"
    desc="$3"
  fi

  test_total=$((test_total + 1))
  if [ ! -f "$conf_file" ]; then
    echo "  [FAIL] $desc: Expected Deskflow server configuration file does not exist: $conf_file" >&2
    exit 1
  fi

  if grep -qE "(^|[[:space:]])${old_id}:" "$conf_file"; then
    echo "  [FAIL] $desc: Stale Deskflow screen entry for '$old_id' found in $conf_file" >&2
    exit 1
  fi

  if ! grep -qE "(^|[[:space:]])${new_host}:" "$conf_file"; then
    echo "  [FAIL] $desc: Expected Deskflow screen entry for '$new_host' missing from $conf_file" >&2
    exit 1
  fi

  test_passed=$((test_passed + 1))
  echo "  [PASS] $desc (Deskflow server config has '$new_host' and zero occurrences of '$old_id')"
}

# -------------------------------------------------------------
# Phase 0: Bash Syntax Verification & PSL Integrity Audits
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

# Mock ssh binary
cat << 'MOCK_SSH_EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "ssh $*" >> "$LOG_DIR/ssh.log"
exit 0
MOCK_SSH_EOF
chmod +x "$MOCK_BIN/ssh"

# Mock systemctl binary
cat << 'MOCK_SYS_EOF' > "$MOCK_BIN/systemctl"
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="${TMP_DIR:-/tmp}/logs"
echo "systemctl $*" >> "$LOG_DIR/systemctl.log"
exit 0
MOCK_SYS_EOF
chmod +x "$MOCK_BIN/systemctl"

# Mock ping binary
cat << 'MOCK_PING_EOF' > "$MOCK_BIN/ping"
#!/usr/bin/env bash
set -euo pipefail
echo "PING $1 56(84) bytes of data."
echo "64 bytes from $1: icmp_seq=1 ttl=64 time=0.500 ms"
echo "--- $1 ping statistics ---"
echo "1 packets transmitted, 1 received, 0% packet loss, time 0ms"
echo "rtt min/avg/max/mdev = 0.500/0.500/0.500/0.000 ms"
exit 0
MOCK_PING_EOF
chmod +x "$MOCK_BIN/ping"

# Mock nc binary
cat << 'MOCK_NC_EOF' > "$MOCK_BIN/nc"
#!/usr/bin/env bash
set -euo pipefail
exit 0
MOCK_NC_EOF
chmod +x "$MOCK_BIN/nc"

# Mock qdbus6 binary
cat << 'MOCK_QDBUS_EOF' > "$MOCK_BIN/qdbus6"
#!/usr/bin/env bash
set -euo pipefail
exit 0
MOCK_QDBUS_EOF
chmod +x "$MOCK_BIN/qdbus6"

# Mock kdeconnect-cli binary
cat << 'MOCK_KDEC_EOF' > "$MOCK_BIN/kdeconnect-cli"
#!/usr/bin/env bash
set -euo pipefail
exit 0
MOCK_KDEC_EOF
chmod +x "$MOCK_BIN/kdeconnect-cli"

# Mock deskflow-core binary
cat << 'MOCK_DF_EOF' > "$MOCK_BIN/deskflow-core"
#!/usr/bin/env bash
set -euo pipefail
exit 0
MOCK_DF_EOF
chmod +x "$MOCK_BIN/deskflow-core"

# Swarm Profile
cat << 'CONF_EOF' > "$SWARM_DIR/swarm.conf"
SWARM_ID="testswarm"
SWARM_NAME="Test Swarm"
ANCHOR_ID="desktop"
ANCHOR_HOST="desktop.local"
HUB_PORT=4242
CONF_EOF

# Set active swarm, install type, and local node id
echo "testswarm" > "$HOME/.local/state/knot/active_swarm"
echo "prod" > "$HOME/.config/knot/install_type"
echo "desktop" > "$HOME/.config/knot/node_id"

# Node Manifests
cat << 'NODE_EOF' > "$NODES_DIR/desktop.json"
{
  "id": "desktop",
  "hostname": "desktop-anchor",
  "role": "anchor",
  "port": 22,
  "user": "desktopuser",
  "ip_hint": "192.168.1.10",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_DESKTOP_KEY desktop@mesh"
}
NODE_EOF

cat << 'NODE_EOF' > "$NODES_DIR/laptop.json"
{
  "id": "laptop",
  "hostname": "laptop-thinkpad",
  "role": "strand",
  "port": 22,
  "user": "laptopuser",
  "ip_hint": "192.168.1.30",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_LAPTOP_KEY laptop@mesh"
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
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_STEAMDECK_KEY deck@mesh"
}
NODE_EOF

cat << 'NODE_EOF' > "$NODES_DIR/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "rog-ally-handheld",
  "role": "strand",
  "port": 22,
  "user": "allyuser",
  "ip_hint": "192.168.1.40",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI_ROGALLY_KEY ally@mesh"
}
NODE_EOF

# Declarative Topology with Sliced Fractional Spans
TOPO_FILE="$SWARM_DIR/topology.json"
cat << 'TOPO_EOF' > "$TOPO_FILE"
{
  "anchor": "desktop",
  "screens": [
    "desktop",
    "laptop",
    "steamdeck",
    "rog-ally"
  ],
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
    {
      "from": "desktop",
      "to": "steamdeck",
      "direction": "right",
      "span": [0, 50],
      "target_span": [0, 100]
    },
    {
      "from": "desktop",
      "to": "laptop",
      "direction": "left",
      "span": [0, 100],
      "target_span": [0, 100]
    }
  ],
  "nodes": {
    "desktop": { "screens": ["desktop"] },
    "steamdeck": { "screens": ["steamdeck"] }
  }
}
TOPO_EOF

# Mute marker file for steamdeck
touch "$HOME/.local/state/knot/vmon_muted_deskflow_steamdeck"

# Pre-compile SSH and Deskflow configs
assert_cmd_succeeds "Initial SSH client config compile" \
  bash -c "source '$KNOT_ROOT/core/lib.sh' && source '$KNOT_ROOT/core/modules/ssh.sh' && ssh_sync_client_config"

assert_cmd_succeeds "Initial Deskflow server config compile" \
  bash -c "source '$KNOT_ROOT/core/lib.sh' && source '$KNOT_ROOT/core/modules/deskflow.sh' && deskflow_compile_server_config unlocked"

# -------------------------------------------------------------
# Phase 2: CLI Help Flag Verification (Exit Code 0)
# -------------------------------------------------------------
echo ""
echo "=== [Phase 2] CLI Help Invocations (Exit 0) ==="
assert_cmd_succeeds "knot node rename -h" "$KNOT_BIN" node rename -h
assert_cmd_succeeds "knot node rename --help" "$KNOT_BIN" node rename --help
assert_cmd_succeeds "knot node -h" "$KNOT_BIN" node -h
assert_cmd_succeeds "knot node --help" "$KNOT_BIN" node --help

# -------------------------------------------------------------
# Phase 3: Pre-Flight Validation Failures (Exit 1 & Zero State Mutation)
# -------------------------------------------------------------
echo ""
echo "=== [Phase 3] Pre-Flight Validation Failures (Exit 1 & Zero State Mutation) ==="

# 3a. Missing all arguments
assert_cmd_fails_with_code 1 "requires exactly two arguments" \
  "knot node rename with 0 arguments" \
  "$KNOT_BIN" node rename

# 3b. Missing destination argument
assert_cmd_fails_with_code 1 "requires exactly two arguments" \
  "knot node rename with 1 argument" \
  "$KNOT_BIN" node rename steamdeck

# 3c. Extraneous arguments
assert_cmd_fails_with_code 1 "requires exactly two arguments" \
  "knot node rename with 3 arguments" \
  "$KNOT_BIN" node rename steamdeck deck-prime extra-arg

# 3d. Non-existent source node
assert_cmd_fails_with_code 1 "Source node 'ghost-node' not found" \
  "knot node rename non-existent source" \
  "$KNOT_BIN" node rename ghost-node new-name

# 3e. Destination collision with existing node
assert_cmd_fails_with_code 1 "Target node identifier 'laptop' already exists" \
  "knot node rename destination collision" \
  "$KNOT_BIN" node rename steamdeck laptop

# 3f. Self-rename
assert_cmd_fails_with_code 1 "Cannot rename node 'steamdeck' to itself" \
  "knot node rename self-rename" \
  "$KNOT_BIN" node rename steamdeck steamdeck

# 3g. Invalid identifier syntax
assert_cmd_fails_with_code 1 "Invalid target node identifier" \
  "knot node rename with symbol '@'" \
  "$KNOT_BIN" node rename steamdeck "deck@jupiter"

assert_cmd_fails_with_code 1 "Invalid target node identifier" \
  "knot node rename with leading hyphen" \
  "$KNOT_BIN" node rename steamdeck "-deck"

assert_cmd_fails_with_code 1 "Invalid target node identifier" \
  "knot node rename with trailing hyphen" \
  "$KNOT_BIN" node rename steamdeck "deck-"

assert_cmd_fails_with_code 1 "Invalid target node identifier" \
  "knot node rename with space" \
  "$KNOT_BIN" node rename steamdeck "deck prime"

assert_cmd_fails_with_code 1 "Invalid target node identifier" \
  "knot node rename with slash" \
  "$KNOT_BIN" node rename steamdeck "deck/prime"

# 3h. Assert Zero State Mutation
assert_file_exists "$NODES_DIR/steamdeck.json" "steamdeck.json remains untouched after preflight errors"
assert_file_not_exists "$NODES_DIR/deck-prime.json" "no target manifest created on preflight errors"
assert_file_exists "$HOME/.local/state/knot/vmon_muted_deskflow_steamdeck" "mute file untouched"

# -------------------------------------------------------------
# Phase 4: Successful Strand Node Rename (steamdeck -> deck-prime)
# -------------------------------------------------------------
echo ""
echo "=== [Phase 4] Successful Strand Node Rename (steamdeck -> deck-prime) ==="
assert_cmd_succeeds "knot node rename steamdeck deck-prime executes cleanly" \
  "$KNOT_BIN" node rename steamdeck deck-prime

# 4a. Assert Manifest Migration
assert_file_not_exists "$NODES_DIR/steamdeck.json" "old manifest steamdeck.json purged"
assert_file_exists "$NODES_DIR/deck-prime.json" "new manifest deck-prime.json created"
assert_manifest_state "$NODES_DIR/deck-prime.json" "deck-prime" "steamdeck-jupiter" \
  "deck-prime.json internal id updated and metadata preserved"

# 4b. Assert Topology Migration (screens, layout, directional edges, and fractional spans)
assert_topology_state "$TOPO_FILE" "desktop,laptop,deck-prime,rog-ally" "desktop" \
  "steamdeck" "deck-prime" "Topology migrated cleanly to deck-prime with spans intact"

# 4c. Assert Deskflow Recompilation
assert_deskflow_clean "$HOME/.config/Deskflow/deskflow-server.conf" \
  "steamdeck" "steamdeck-jupiter" \
  "Deskflow server configuration recompiled for deck-prime"

# 4d. Assert SSH Client Config Regeneration
assert_ssh_clean "steamdeck" "deck-prime" \
  "SSH client config updated with Host deck-prime and purged steamdeck"

# 4e. Assert Mute Marker File Migration
assert_file_not_exists "$HOME/.local/state/knot/vmon_muted_deskflow_steamdeck" \
  "old mute marker for steamdeck removed"
assert_file_exists "$HOME/.local/state/knot/vmon_muted_deskflow_deck-prime" \
  "new mute marker for deck-prime created"

# 4f. Assert Zero Ghost Status
test_total=$((test_total + 1))
status_out="$("$KNOT_BIN" status 2>&1)"
if echo "$status_out" | grep -q "steamdeck"; then
  echo "  [FAIL] Ghost entry for steamdeck found in knot status" >&2
  echo "$status_out" >&2
  exit 1
fi
if ! echo "$status_out" | grep -q "deck-prime"; then
  echo "  [FAIL] Expected entry for deck-prime missing from knot status" >&2
  echo "$status_out" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] knot status shows deck-prime and zero ghost occurrences of steamdeck"

# -------------------------------------------------------------
# Phase 5: Successful Anchor Node Rename (desktop -> desktop-alpha)
# -------------------------------------------------------------
echo ""
echo "=== [Phase 5] Successful Anchor Node Rename (desktop -> desktop-alpha) ==="
assert_cmd_succeeds "knot node rename desktop desktop-alpha executes cleanly" \
  "$KNOT_BIN" node rename desktop desktop-alpha

# 5a. Assert Manifest Migration
assert_file_not_exists "$NODES_DIR/desktop.json" "old anchor manifest desktop.json purged"
assert_file_exists "$NODES_DIR/desktop-alpha.json" "new anchor manifest desktop-alpha.json created"
assert_manifest_state "$NODES_DIR/desktop-alpha.json" "desktop-alpha" "desktop-anchor" \
  "desktop-alpha.json internal id updated and metadata preserved"

# 5b. Assert Topology Migration (anchor key, screens, reverse directional edges)
assert_topology_state "$TOPO_FILE" "desktop-alpha,laptop,deck-prime,rog-ally" "desktop-alpha" \
  "desktop" "desktop-alpha" "Topology anchor and references migrated to desktop-alpha"

# 5c. Assert Swarm Profile Migration (ANCHOR_ID in swarm.conf)
test_total=$((test_total + 1))
if ! grep -qE '^ANCHOR_ID="desktop-alpha"' "$SWARM_DIR/swarm.conf"; then
  echo "  [FAIL] ANCHOR_ID in $SWARM_DIR/swarm.conf was not updated to desktop-alpha:" >&2
  cat "$SWARM_DIR/swarm.conf" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] swarm.conf ANCHOR_ID updated to desktop-alpha"

# 5d. Assert Local Node ID marker updated
test_total=$((test_total + 1))
if [ -f "$HOME/.config/knot/node_id" ] && [ "$(tr -d '[:space:]' < "$HOME/.config/knot/node_id")" = "desktop-alpha" ]; then
  test_passed=$((test_passed + 1))
  echo "  [PASS] local node_id marker updated to desktop-alpha"
else
  echo "  [FAIL] local node_id marker was not updated to desktop-alpha" >&2
  exit 1
fi

# 5e. Assert Zero Ghost Status for Anchor
test_total=$((test_total + 1))
status_out="$("$KNOT_BIN" status 2>&1)"
if echo "$status_out" | grep -qE "(^|[[:space:]])desktop([[:space:]]|$)"; then
  echo "  [FAIL] Ghost entry for old anchor 'desktop' found in knot status" >&2
  echo "$status_out" >&2
  exit 1
fi
if ! echo "$status_out" | grep -q "desktop-alpha"; then
  echo "  [FAIL] Expected entry for desktop-alpha missing from knot status" >&2
  echo "$status_out" >&2
  exit 1
fi
test_passed=$((test_passed + 1))
echo "  [PASS] knot status shows desktop-alpha and zero ghost occurrences of desktop"

# -------------------------------------------------------------
# Summary & Test Verification
# -------------------------------------------------------------
echo ""
echo "================================================================================"
echo "✔ Node Rename Test Suite Passed: $test_passed / $test_total checks passed."
echo "================================================================================"
exit 0
