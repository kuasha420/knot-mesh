#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Automated Verification for OpenSSH Multiplexing & Parallel Exec (Strand A: #65, #78, #77)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BIN_KNOT="$KNOT_ROOT/bin/knot"
SSH_MODULE="$KNOT_ROOT/core/modules/ssh.sh"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$SSH_MODULE"
bash -n "$BIN_KNOT"
echo "  -> Syntax valid: OK"

echo "=== [Test 2] Zero Error Swallowing Audit (PSL Rule 1) ==="
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
matches=""
if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$SSH_MODULE" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
  matches=""
fi
if [ -n "$matches" ]; then
  echo "Error: Forbidden error swallowing detected in ssh.sh:" >&2
  echo "$matches" >&2
  exit 1
fi
echo "  -> Zero error swallowing in ssh.sh: OK"

echo "=== [Test 3] OpenSSH ControlMaster Client Profile Generation ==="
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export HOME="$TEST_TMP"
mkdir -p "$HOME/.ssh"
mkdir -p "$HOME/.config/knot/swarms/test_swarm/nodes"

# Create synthetic node manifests
cat << 'EOF' > "$HOME/.config/knot/swarms/test_swarm/nodes/desktop.json"
{
  "id": "desktop",
  "hostname": "desktop",
  "user": "psl",
  "port": 22,
  "role": "anchor",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest1 test@desktop"
}
EOF

cat << 'EOF' > "$HOME/.config/knot/swarms/test_swarm/nodes/laptop.json"
{
  "id": "laptop",
  "hostname": "laptop",
  "user": "psl",
  "port": 22,
  "role": "worker",
  "pubkey": "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest2 test@laptop"
}
EOF

cat << 'EOF' > "$HOME/.config/knot/swarms/test_swarm/swarm.conf"
SWARM_ID=test_swarm
ANCHOR_ID=desktop
ANCHOR_HOST=desktop
EOF

echo "test_swarm" > "$HOME/.config/knot/active_swarm"
mkdir -p "$HOME/.local/state/knot"
echo "test_swarm" > "$HOME/.local/state/knot/active_swarm"
export KNOT_ACTIVE_SWARM="test_swarm"

# Run client configuration compilation
bash "$SSH_MODULE" client-config

CONFIG_FILE="$HOME/.ssh/config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Generated ~/.ssh/config not found!" >&2
  exit 1
fi

if ! grep -q "ControlMaster auto" "$CONFIG_FILE"; then
  echo "Error: ControlMaster auto missing from generated ~/.ssh/config!" >&2
  exit 1
fi

if ! grep -q "ControlPath ~/.cache/knot/ssh/cm_%C" "$CONFIG_FILE"; then
  echo "Error: ControlPath missing from generated ~/.ssh/config!" >&2
  exit 1
fi

if ! grep -q "ControlPersist 10m" "$CONFIG_FILE"; then
  echo "Error: ControlPersist 10m missing from generated ~/.ssh/config!" >&2
  exit 1
fi

# Verify socket cache directory permissions (0700)
SOCK_DIR="$HOME/.cache/knot/ssh"
if [ ! -d "$SOCK_DIR" ]; then
  echo "Error: ~/.cache/knot/ssh directory was not created!" >&2
  exit 1
fi

SOCK_PERMS="$(stat -c %a "$SOCK_DIR")"
if [ "$SOCK_PERMS" != "700" ]; then
  echo "Error: ~/.cache/knot/ssh directory permissions are $SOCK_PERMS (expected 700)!" >&2
  exit 1
fi
echo "  -> ControlMaster auto, ControlPath cm_%C, ControlPersist 10m, and 0700 permissions: OK"

echo "=== [Test 4] Socket Status & Stale Pruning Routines ==="
# Test initial socket status
status_out="$(bash "$BIN_KNOT" socket status)"
echo "$status_out" | grep -q "No active OpenSSH ControlMaster multiplexing sockets"

# Create a stale dummy socket
touch "$SOCK_DIR/cm_synthetic_stale_socket"
status_out_after="$(bash "$BIN_KNOT" socket status)"
echo "$status_out_after" | grep -q "cm_synthetic_stale_socket"

# Run socket cleanup
cleanup_out="$(bash "$BIN_KNOT" socket cleanup)"
echo "$cleanup_out" | grep -q "Pruned 1 OpenSSH ControlMaster socket"

if [ -e "$SOCK_DIR/cm_synthetic_stale_socket" ]; then
  echo "Error: Stale socket was not pruned by socket cleanup!" >&2
  exit 1
fi
echo "  -> Socket status & stale pruning: OK"

echo "=== [Test 5] knot exec -P / --parallel Streaming & Prefix Fan-Out ==="
# Test parallel execution against local node in synthetic environment
# We simulate a 2-node local test by creating a temporary wrapper or running on current node
export KNOT_ROOT
export KNOT_HUB_URL="https://127.0.0.1:4242"
export KNOT_NODE_ID="desktop"

# Test executing with -P locally
exec_out="$(bash "$BIN_KNOT" exec -P desktop "echo 'stream_line_1'; echo 'stream_line_2'")"

if ! echo "$exec_out" | grep -q "\[desktop\] stream_line_1"; then
  echo "Error: Expected '[desktop] stream_line_1' in streaming output, got: $exec_out" >&2
  exit 1
fi

if ! echo "$exec_out" | grep -q "\[desktop\] stream_line_2"; then
  echo "Error: Expected '[desktop] stream_line_2' in streaming output, got: $exec_out" >&2
  exit 1
fi
echo "  -> Line streaming with node prefix [desktop]: OK"

echo "=== [Test 6] Parallel Exit Code Aggregation ==="
# Verify non-zero exit code reporting without early crash
set +e
bash "$BIN_KNOT" exec -P desktop "exit 42" > "$TEST_TMP/fail_out.txt" 2>&1
fail_rc=$?
set -euo pipefail

if [ "$fail_rc" -eq 0 ]; then
  echo "Error: Expected non-zero exit code from failing command under knot exec -P, got 0" >&2
  exit 1
fi
echo "  -> Exit code aggregation (propagated exit code $fail_rc): OK"

echo "=== [Test 7] knot exec -P --all Multi-Node Concurrent Streaming & Exit Aggregation ==="
MOCK_BIN="$TEST_TMP/mock_bin"
mkdir -p "$MOCK_BIN"
cat << 'EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
# Mock SSH for laptop node
node=""
for arg in "$@"; do
  if [ "$arg" = "laptop" ]; then
    node="laptop"
  fi
done

if [ -n "$node" ]; then
  echo "remote_stream_line_1"
  echo "remote_stream_line_2"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/ssh"

all_out="$(PATH="$MOCK_BIN:$PATH" bash "$BIN_KNOT" exec -P --all "echo local_stream_line")"

if ! echo "$all_out" | grep -q "\[desktop\] local_stream_line"; then
  echo "Error: [desktop] prefix missing in parallel --all output: $all_out" >&2
  exit 1
fi

if ! echo "$all_out" | grep -q "\[laptop\] remote_stream_line_1"; then
  echo "Error: [laptop] prefix missing in parallel --all output: $all_out" >&2
  exit 1
fi
echo "  -> Multi-node concurrent streaming fan-out with prefixes [desktop] & [laptop]: OK"

# Verify multi-node exit code aggregation when a remote node fails
cat << 'EOF' > "$MOCK_BIN/ssh"
#!/usr/bin/env bash
echo "remote_failure_diagnostic"
exit 42
EOF
chmod +x "$MOCK_BIN/ssh"

set +e
all_fail_out="$(PATH="$MOCK_BIN:$PATH" bash "$BIN_KNOT" exec -P --all "echo ok" 2>&1)"
all_fail_rc=$?
set -euo pipefail

if [ "$all_fail_rc" -ne 42 ]; then
  echo "Error: Expected aggregated exit code 42 from failed remote node, got $all_fail_rc: $all_fail_out" >&2
  exit 1
fi

if ! echo "$all_fail_out" | grep -q "laptop (exit 42)"; then
  echo "Error: Expected failure summary mentioning laptop (exit 42), got: $all_fail_out" >&2
  exit 1
fi
echo "  -> Multi-node failure exit code 42 aggregation and summary: OK"

echo "=== [✓] ALL OPENSSH MULTIPLEXING & PARALLEL EXEC TESTS PASSED! ==="
