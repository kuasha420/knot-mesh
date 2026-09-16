#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Mesh Automated Migration Engine (ISSUE-14)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
MIGRATE_SCRIPT="$KNOT_ROOT/core/installer/migrate.sh"

echo "=== [Test 1] Syntax & Zero Error Swallowing Verification ==="
bash -n "$MIGRATE_SCRIPT"
echo "  -> migrate.sh syntax: OK"

if grep -n "2>/dev/null\||| true\||| :" "$MIGRATE_SCRIPT"; then
  echo "Error: Detected forbidden error swallowing in migrate.sh!" >&2
  exit 1
fi
echo "  -> Zero error swallowing: OK"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export KNOT_TEST_MODE=1

LEGACY_DIR="$TMP_DIR/legacy_knot"
mkdir -p "$LEGACY_DIR/registry/nodes"

# Setup synthetic legacy manifests
cat << 'DESKTOP_EOF' > "$LEGACY_DIR/registry/nodes/desktop.json"
{
  "id": "desktop",
  "hostname": "test-desktop",
  "user": "anchor-user",
  "port": 42069,
  "subnet": "192.168.10.0/24",
  "gateway_mac": "aa:bb:cc:dd:ee:ff",
  "interfaces": {
    "eth0": {
      "type": "ethernet",
      "mac": "11:22:33:44:55:66"
    }
  }
}
DESKTOP_EOF

cat << 'LAPTOP_EOF' > "$LEGACY_DIR/registry/nodes/laptop.json"
{
  "id": "laptop",
  "hostname": "test-laptop",
  "user": "strand-user",
  "port": 22,
  "subnet": "192.168.10.0/24",
  "gateway_mac": "aa:bb:cc:dd:ee:ff",
  "interfaces": {
    "wlan0": {
      "type": "wifi",
      "mac": "77:88:99:aa:bb:cc"
    }
  }
}
LAPTOP_EOF

cat << 'TOPO_EOF' > "$LEGACY_DIR/registry/topology.json"
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

echo "=== [Test 2] Role Detection Unit Test ==="
source "$MIGRATE_SCRIPT"

# Mock hostname to match laptop
knot_detect_hostname() { echo "test-laptop"; }
ROLE_INFO="$(migrate_detect_role "$LEGACY_DIR")"
read -r DET_ID DET_ROLE DET_ANCHOR <<< "$ROLE_INFO"

if [ "$DET_ID" != "laptop" ] || [ "$DET_ROLE" != "strand" ] || [ "$DET_ANCHOR" != "desktop" ]; then
  echo "Error: Failed strand detection, got: $ROLE_INFO" >&2
  exit 1
fi
echo "  -> Strand role auto-detection: OK"

# Mock hostname to match desktop
knot_detect_hostname() { echo "test-desktop"; }
ROLE_INFO_ANCHOR="$(migrate_detect_role "$LEGACY_DIR")"
read -r DET_ID2 DET_ROLE2 DET_ANCHOR2 <<< "$ROLE_INFO_ANCHOR"

if [ "$DET_ID2" != "desktop" ] || [ "$DET_ROLE2" != "anchor" ] || [ "$DET_ANCHOR2" != "desktop" ]; then
  echo "Error: Failed anchor detection, got: $ROLE_INFO_ANCHOR" >&2
  exit 1
fi
echo "  -> Anchor role auto-detection: OK"

echo "=== [Test 3] Dry-Run Simulation ==="
export HOME="$TMP_DIR/home"
mkdir -p "$HOME"

DRY_RUN_OUT="$("$MIGRATE_SCRIPT" --legacy-dir "$LEGACY_DIR" --swarm-id "home-test" --dry-run)"
echo "$DRY_RUN_OUT" | grep -q "DRY-RUN SIMULATION"
echo "$DRY_RUN_OUT" | grep -q "Would write profile to"

# Verify that dry-run did NOT write files
if [ -d "$HOME/.config/knot/swarms/home-test" ]; then
  echo "Error: dry-run created files on disk!" >&2
  exit 1
fi
echo "  -> Dry-run execution without disk side-effects: OK"

echo "=== [Test 4] Live Migration Execution ==="
# Stub service calls to prevent systemd calls in test environment
deskflow_compile_server_config() { return 0; }
sudo() { "$@"; }

LIVE_OUT="$("$MIGRATE_SCRIPT" --legacy-dir "$LEGACY_DIR" --swarm-id "home-test")"
echo "$LIVE_OUT" | grep -q "MIGRATION COMPLETED SUCCESSFULLY"

MIGRATED_SWARM_DIR="$HOME/.config/knot/swarms/home-test"
if [ ! -f "$MIGRATED_SWARM_DIR/swarm.conf" ]; then
  echo "Error: Migrated swarm.conf missing!" >&2
  exit 1
fi

grep -q 'SWARM_ID="home-test"' "$MIGRATED_SWARM_DIR/swarm.conf"
grep -q 'ANCHOR_ID="desktop"' "$MIGRATED_SWARM_DIR/swarm.conf"
grep -q 'ANCHOR_HOST="test-desktop"' "$MIGRATED_SWARM_DIR/swarm.conf"

if [ ! -f "$MIGRATED_SWARM_DIR/topology.json" ]; then
  echo "Error: Migrated topology.json missing!" >&2
  exit 1
fi

if [ ! -f "$MIGRATED_SWARM_DIR/nodes/laptop.json" ] || [ ! -f "$MIGRATED_SWARM_DIR/nodes/desktop.json" ]; then
  echo "Error: Migrated node manifests missing!" >&2
  exit 1
fi

ACTIVE_STATE="$HOME/.local/state/knot/active_swarm"
if [ ! -f "$ACTIVE_STATE" ] || [ "$(cat "$ACTIVE_STATE")" != "home-test" ]; then
  echo "Error: Active swarm not updated to home-test!" >&2
  exit 1
fi
echo "  -> Live migration synthesized profile, topology, and active state: OK"

echo "=== [Test 5] Integration via knot-installer CLI ==="
"$KNOT_ROOT/bin/knot-installer" migrate --legacy-dir "$LEGACY_DIR" --swarm-id "cli-test" --dry-run | grep -q "DRY-RUN SIMULATION COMPLETE"
echo "  -> knot-installer migrate invocation: OK"

echo "=== [✓] ALL MIGRATION ENGINE TESTS PASSED! ==="
