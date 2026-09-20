#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Mesh Unified Installer CLI (ISSUE-12)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
INSTALLER="$KNOT_ROOT/bin/knot-installer"

echo "=== [Test 1] Syntax & Zero Error Swallowing Verification ==="
bash -n "$INSTALLER"
echo "  -> knot-installer syntax: OK"

if grep -n "2>/dev/null\||| true\||| :" "$INSTALLER"; then
  echo "Error: Detected forbidden error swallowing patterns in bin/knot-installer!" >&2
  exit 1
fi
echo "  -> Zero error swallowing: OK"

echo "=== [Test 2] Help and Version Subcommands ==="
"$INSTALLER" --version | grep -q "knot-mesh version 1.0.0-rc5"
"$INSTALLER" --help | grep -q "USAGE:"
"$INSTALLER" init --help | grep -q "Initialize this workstation as an Anchor"
"$INSTALLER" invite --help | grep -q "Generate a secure pairing token"
"$INSTALLER" --help | grep -q "update"
"$INSTALLER" update --help | grep -q "knot update"
echo "  -> Top-level and subcommand help outputs: OK"

echo "=== [Test 3] Subcommand: init (Anchor Swarm Profile Initialization) ==="
TMP_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_TEST_DIR"' EXIT
export KNOT_TEST_MODE=1

export HOME="$TMP_TEST_DIR/home"
export KNOT_RUNTIME_DIR="$TMP_TEST_DIR/run"
mkdir -p "$HOME" "$KNOT_RUNTIME_DIR" "$TMP_TEST_DIR/bin"

# Mock systemctl to protect host services
cat << 'SYS_EOF' > "$TMP_TEST_DIR/bin/systemctl"
#!/usr/bin/env bash
exit 0
SYS_EOF
chmod +x "$TMP_TEST_DIR/bin/systemctl"
export PATH="$TMP_TEST_DIR/bin:$PATH"

# Run knot-installer init in isolated test environment
"$INSTALLER" init --name "Lab Workspace" --id "lab" --anchor-id "lab-anchor" --headless

USER_SWARM_DIR="$HOME/.config/knot/swarms/lab"
if [ ! -f "$USER_SWARM_DIR/swarm.conf" ]; then
  echo "Error: swarm.conf was not created at $USER_SWARM_DIR/swarm.conf" >&2
  exit 1
fi

grep -q 'SWARM_ID="lab"' "$USER_SWARM_DIR/swarm.conf"
grep -q 'SWARM_NAME="Lab Workspace"' "$USER_SWARM_DIR/swarm.conf"
grep -q 'ANCHOR_ID="lab-anchor"' "$USER_SWARM_DIR/swarm.conf"
echo "  -> Swarm profile configuration: OK"

# Check node manifest
MANIFEST="$USER_SWARM_DIR/nodes/lab-anchor.json"
if [ ! -f "$MANIFEST" ]; then
  echo "Error: Anchor node manifest was not created at $MANIFEST" >&2
  exit 1
fi

grep -q '"id": "lab-anchor"' "$MANIFEST"
grep -q '"role": "anchor"' "$MANIFEST"
grep -q '"display": null' "$MANIFEST"
echo "  -> Anchor node manifest: OK"

# Check topology
TOPO="$USER_SWARM_DIR/topology.json"
if [ ! -f "$TOPO" ]; then
  echo "Error: topology.json was not created at $TOPO" >&2
  exit 1
fi

grep -q '"anchor": "lab-anchor"' "$TOPO"
echo "  -> Declarative topology: OK"

# Check active swarm
ACTIVE_SWARM_STATE="$HOME/.local/state/knot/active_swarm"
if [ ! -f "$ACTIVE_SWARM_STATE" ] || [ "$(cat "$ACTIVE_SWARM_STATE")" != "lab" ]; then
  echo "Error: active swarm was not set to 'lab'!" >&2
  exit 1
fi
# Check knot-guard.service deployment
GUARD_SERVICE="$HOME/.config/systemd/user/knot-guard.service"
if [ ! -f "$GUARD_SERVICE" ] && [ ! -L "$GUARD_SERVICE" ]; then
  echo "Error: knot-guard.service was not deployed to $GUARD_SERVICE" >&2
  exit 1
fi
echo "  -> Knot Guard user service deployment: OK"

# Check Antigravity skills deployment
SKILLS_DIR="$HOME/.gemini/antigravity/skills"
if [ ! -d "$SKILLS_DIR/knot-swarm" ] || [ ! -d "$SKILLS_DIR/core-mesh" ]; then
  echo "Error: Antigravity skills were not deployed to $SKILLS_DIR" >&2
  exit 1
fi
echo "  -> Antigravity skills deployment: OK"

# Check Antigravity MCP sync
MCP_CONF="$HOME/.gemini/config/mcp_config.json"
if [ ! -f "$MCP_CONF" ] || ! grep -q '"knot"' "$MCP_CONF"; then
  echo "Error: Knot MCP server configuration was not found in $MCP_CONF" >&2
  exit 1
fi
echo "  -> Antigravity MCP gateway configuration: OK"

echo "=== [Test 4] Subcommand: uninstall (-y) ==="
"$INSTALLER" uninstall -y
echo "  -> Clean uninstall: OK"

echo "=== [✓] ALL KNOT-INSTALLER CLI TESTS PASSED! ==="
