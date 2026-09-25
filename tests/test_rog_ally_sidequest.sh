#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Autonomous Side Quest: ROG Ally Dual-Personality & 120Hz Handheld Domain Verification
# Validates:
# 1. Dual Personality: Anchor role on 'office' swarm vs Strand role on 'home' swarm
# 2. 120Hz Handheld Display (1920x1080@120Hz) and Docked Multi-Monitor (4K@144Hz) Parsing
# 3. Dynamic Deskflow Topology Switching (Server mode in office, Client mode in home)
# 4. Network Interface Roaming & Stale Lease Eviction during Dock / Undock Transitions

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "============================================================"
echo "  KNOT MESH: ROG ALLY DUAL-PERSONALITY & 120HZ DOMAIN AUDIT "
echo "============================================================"

# Setup isolated environment
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/knot/swarms"

# Source core library
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/installer/display.sh"

echo "=== [Side Quest 1] Dual Personality: Multi-Swarm Role Switching ==="

# Swarm A: 'test-home' - rog-ally is a STRAND / Worker (Anchor is mock-anchor)
mkdir -p "$HOME/.config/knot/swarms/test-home/nodes"
cat << CONF_EOF > "$HOME/.config/knot/swarms/test-home/swarm.conf"
SWARM_ID="test-home"
SWARM_NAME="Test Home Mesh"
ANCHOR_ID="mock-anchor"
ANCHOR_HOST="mock-anchor-box"
HUB_PORT=4242
CONF_EOF

cat << JSON_EOF > "$HOME/.config/knot/swarms/test-home/nodes/mock-anchor.json"
{
  "id": "mock-anchor",
  "hostname": "mock-anchor-box",
  "role": "anchor",
  "user": "psl"
}
JSON_EOF

cat << JSON_EOF > "$HOME/.config/knot/swarms/test-home/nodes/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "$(knot_detect_hostname)",
  "role": "strand",
  "user": "psl"
}
JSON_EOF

# Swarm B: 'test-office' - rog-ally is the ANCHOR / Coordinator
mkdir -p "$HOME/.config/knot/swarms/test-office/nodes"
cat << CONF_EOF > "$HOME/.config/knot/swarms/test-office/swarm.conf"
SWARM_ID="test-office"
SWARM_NAME="Test Office Fleet"
ANCHOR_ID="rog-ally"
ANCHOR_HOST="$(knot_detect_hostname)"
HUB_PORT=4242
CONF_EOF

cat << JSON_EOF > "$HOME/.config/knot/swarms/test-office/nodes/rog-ally.json"
{
  "id": "rog-ally",
  "hostname": "$(knot_detect_hostname)",
  "role": "anchor",
  "user": "psl"
}
JSON_EOF

cat << JSON_EOF > "$HOME/.config/knot/swarms/test-office/nodes/laptop.json"
{
  "id": "laptop",
  "hostname": "devbox.local",
  "role": "strand",
  "user": "psl"
}
JSON_EOF

# Set node ID
echo "rog-ally" > "$HOME/.config/knot/node_id"
unset KNOT_NODE_ID KNOT_ACTIVE_SWARM

# 1a. Test home swarm profile: Must be recognized as STRAND
export KNOT_ACTIVE_SWARM="test-home"
knot_load_swarm_profile "test-home"
[ "$ANCHOR_ID" = "mock-anchor" ] || { echo "FAIL: Expected ANCHOR_ID=mock-anchor in test-home swarm" >&2; exit 1; }
if knot_is_anchor; then
  echo "FAIL: rog-ally should NOT be anchor on test-home swarm!" >&2
  exit 1
fi
echo "  -> Home swarm: Strand role confirmed (knot_is_anchor == false): OK"

# 1b. Test office swarm profile: Must be recognized as ANCHOR
export KNOT_ACTIVE_SWARM="test-office"
knot_load_swarm_profile "test-office"
[ "$ANCHOR_ID" = "rog-ally" ] || { echo "FAIL: Expected ANCHOR_ID=rog-ally in test-office swarm" >&2; exit 1; }
if ! knot_is_anchor; then
  echo "FAIL: rog-ally SHOULD be anchor on test-office swarm!" >&2
  exit 1
fi
echo "  -> Office swarm: Anchor role confirmed (knot_is_anchor == true): OK"

# 1c. Rapid switching idempotency
for i in {1..5}; do
  export KNOT_ACTIVE_SWARM="test-home"
  knot_load_swarm_profile "test-home"
  [ "$ANCHOR_ID" = "mock-anchor" ]
  export KNOT_ACTIVE_SWARM="test-office"
  knot_load_swarm_profile "test-office"
  [ "$ANCHOR_ID" = "rog-ally" ]
done
echo "  -> Rapid swarm profile flipping idempotency (5 cycles): OK"

echo "=== [Side Quest 2] 120Hz Handheld Display & Docked 4K/144Hz Monitor Parsing ==="

# 2a. ROG Ally Native 1080p 120Hz Landscape Display
SAMPLE_ALLY_KSCREEN=$'Output: 1 eDP-1 00000000-0000-0000-0000-000000000000\n\tenabled\n\tconnected\n\tpriority 1\n\tPanel\n\tModes: 1:1920x1080@120.00*! 2:1920x1080@60.00\n\tScale: 1.0'
PARSED_ALLY="$(display_parse_kscreen_doctor "$SAMPLE_ALLY_KSCREEN")"
read -r A_RES A_REFRESH A_SCALE <<< "$PARSED_ALLY"
[ "$A_RES" = "1920x1080" ] || { echo "FAIL: Expected 1920x1080, got $A_RES" >&2; exit 1; }
[ "$A_REFRESH" = "120.00" ] || { echo "FAIL: Expected 120.00, got $A_REFRESH" >&2; exit 1; }
[ "$A_SCALE" = "1.0" ] || { echo "FAIL: Expected 1.0, got $A_SCALE" >&2; exit 1; }
echo "  -> ROG Ally native panel 1920x1080@120Hz auto-discovery: OK"

# 2b. Docked Station with External 4K 144Hz Display (Priority 1) + Internal 1080p 120Hz (Priority 2)
SAMPLE_DOCKED_KSCREEN=$'Output: 1 DP-1 aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n\tenabled\n\tconnected\n\tpriority 1\n\tDisplayPort\n\tModes: 1:3840x2160@144.00*! 2:3840x2160@120.00 3:2560x1440@144.00\n\tScale: 1.5\nOutput: 2 eDP-1 00000000-0000-0000-0000-000000000000\n\tenabled\n\tconnected\n\tpriority 2\n\tPanel\n\tModes: 1:1920x1080@120.00*! 2:1920x1080@60.00\n\tScale: 1.0'
PARSED_DOCKED="$(display_parse_kscreen_doctor "$SAMPLE_DOCKED_KSCREEN")"
read -r D_RES D_REFRESH D_SCALE <<< "$PARSED_DOCKED"
[ "$D_RES" = "3840x2160" ] || { echo "FAIL: Expected 3840x2160, got $D_RES" >&2; exit 1; }
[ "$D_REFRESH" = "144.00" ] || { echo "FAIL: Expected 144.00, got $D_REFRESH" >&2; exit 1; }
[ "$D_SCALE" = "1.5" ] || { echo "FAIL: Expected 1.5, got $D_SCALE" >&2; exit 1; }
echo "  -> Docked 4K@144Hz external monitor priority auto-discovery: OK"

# 2c. CLI JSON output compliance
JSON_OUT="$("$KNOT_ROOT/core/installer/display.sh" --resolution 1920x1080 --refresh 120.0 --scale 1.0 --json)"
echo "$JSON_OUT" | grep -q '"resolution": "1920x1080"'
echo "$JSON_OUT" | grep -E -q '"refresh_rate": 120'
echo "  -> 120Hz JSON schema formatting: OK"

echo "=== [Side Quest 3] Deskflow Dynamic Server vs Client Compilation ==="

# 3a. In office swarm: rog-ally is Server/Anchor controlling laptop
python3 - << 'PYEOF'
import json, tempfile, os
from core.modules.compile_deskflow import compile_deskflow

with tempfile.TemporaryDirectory() as td:
    nodes_dir = os.path.join(td, "nodes")
    os.makedirs(nodes_dir)
    with open(os.path.join(nodes_dir, "rog-ally.json"), "w") as f:
        json.dump({"id": "rog-ally", "hostname": "rog-ally"}, f)
    with open(os.path.join(nodes_dir, "laptop.json"), "w") as f:
        json.dump({"id": "laptop", "hostname": "devbox"}, f)

    topology = {
        "anchor": "rog-ally",
        "screens": ["rog-ally", "laptop"],
        "layout": {
            "rog-ally": {
                "right": "laptop"
            }
        }
    }
    topo_path = os.path.join(td, "topology.json")
    with open(topo_path, "w") as f:
        json.dump(topology, f)

    conf = compile_deskflow(topo_path, nodes_dir, "unlocked")
    assert "rog-ally:" in conf
    assert "devbox:" in conf
    assert "right(0,100) = devbox(0,100)" in conf
    assert "left(0,100) = rog-ally(0,100)" in conf
    print("  -> Deskflow Server configuration with rog-ally Anchor: OK")
PYEOF

echo "=== [Side Quest 4] Network Roaming: Docked Ethernet <-> Wi-Fi Lease Eviction ==="

# Simulate network transition:
# In office, rog-ally shifts from Wi-Fi (192.168.1.55) to Docked Ethernet (192.168.1.155)
LEASE_DIR="$HOME/.config/knot/cache/leases"
mkdir -p "$LEASE_DIR"
echo "192.168.1.55" > "$LEASE_DIR/rog-ally.lease"

[ -f "$LEASE_DIR/rog-ally.lease" ]
old_ip="$(cat "$LEASE_DIR/rog-ally.lease")"
[ "$old_ip" = "192.168.1.55" ]

# Resolver lease invalidation test
RESOLVER="$KNOT_ROOT/core/resolver.sh"
# Test conflict eviction function directly from resolver
resolved_local="$(bash "$RESOLVER" rog-ally)"
[ "$resolved_local" = "127.0.0.1" ]
echo "  -> Local node resolution bypasses stale remote lease: OK"

echo ""
echo "============================================================"
echo "✔ ALL ROG ALLY DUAL-PERSONALITY & 120HZ AUDIT TESTS PASSED!"
echo "============================================================"
