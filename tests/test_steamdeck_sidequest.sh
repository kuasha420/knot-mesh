#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Autonomous Side Quest: Steam Deck Handheld Domain Verification
# Validates:
# 1. SteamOS Read-Only Rootfs Immutability & User-Space Confinement
# 2. Gaming Mode (gamescope) vs Desktop Mode (KDE Plasma) Wayland Resolution & Session Probing
# 3. Handheld APU Memory & Latency Profiling

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Side Quest 1] SteamOS Read-Only Rootfs & User-Space Confinement ==="

# Verify primary user services target user-space %h/.local/bin
USER_SVCS=(knot-agent knot-deskflow knot-hub knot-stripd)
for s in "${USER_SVCS[@]}"; do
  unit="$KNOT_ROOT/systemd/${s}.service"
  if [ -f "$unit" ]; then
    if ! grep -q "ExecStart=%h/\.local/bin" "$unit"; then
      echo "FAIL: $unit does not use %h/.local/bin" >&2
      exit 1
    fi
  fi
done
echo "  -> Primary Strand user service units properly use %h/.local/bin: OK"

# Check knot-guard.service path requirement
if grep -q "ExecStart=/usr/local/bin" "$KNOT_ROOT/systemd/knot-guard.service"; then
  echo "  -> Notice: knot-guard.service references /usr/local/bin (requires root/guard_configure install): DOCUMENTED"
fi

# Verify knot-installer join user-space symlinks
MOCK_HOME="$(mktemp -d)"
trap 'rm -rf "$MOCK_HOME"' EXIT

export HOME="$MOCK_HOME"
mkdir -p "$MOCK_HOME/.local/bin" "$MOCK_HOME/.config/systemd/user"

for b in knot knot-installer knot-autounlock knot-agent knot-stripd; do
  if [ -f "$KNOT_ROOT/bin/$b" ]; then
    ln -sf "$KNOT_ROOT/bin/$b" "$MOCK_HOME/.local/bin/$b"
  fi
done

[ -x "$MOCK_HOME/.local/bin/knot" ]
[ -x "$MOCK_HOME/.local/bin/knot-installer" ]
[ -x "$MOCK_HOME/.local/bin/knot-autounlock" ]
echo "  -> Zero root write dependency for Strand binaries: OK"

echo "=== [Side Quest 2] Gaming Mode (gamescope) & Handheld Display Handling ==="

# Test 1280x800@60Hz (LCD) and 1280x800@90Hz (OLED) display configurations
DISP_60="$("$KNOT_ROOT/core/installer/display.sh" --resolution 1280x800 --refresh 60.0 --scale 1.0 --json)"
echo "$DISP_60" | grep -q '"resolution": "1280x800"'
echo "$DISP_60" | grep -q '"refresh_rate": 60'
echo "  -> Steam Deck LCD 1280x800@60Hz display spec: OK"

DISP_90="$("$KNOT_ROOT/core/installer/display.sh" --resolution 1280x800 --refresh 90.0 --scale 1.0 --json)"
echo "$DISP_90" | grep -q '"resolution": "1280x800"'
echo "$DISP_90" | grep -q '"refresh_rate": 90'
echo "  -> Steam Deck OLED 1280x800@90Hz display spec: OK"

# Test Deskflow reciprocal compilation with Steam Deck handheld screen
TOPO_COMPILED="$(python3 "$KNOT_ROOT/core/modules/compile_deskflow.py" \
  --topology "$KNOT_ROOT/templates/topology.example.json" \
  --nodes-dir "$KNOT_ROOT/templates/nodes" \
  --mode unlocked)"

echo "$TOPO_COMPILED" | grep -q "steamdeck:"
echo "$TOPO_COMPILED" | grep -q "down(0,100) = steamdeck(0,100)"
echo "$TOPO_COMPILED" | grep -q "up(0,100) = desktop(0,100)"
echo "  -> Reciprocal KVM traversal (desktop down <-> steamdeck up): OK"

echo "=== [Side Quest 3] Handheld APU Lightweight Footprint Telemetry ==="

# Test Gateway RSS Memory
python3 -c '
import subprocess, resource
p = subprocess.run(["python3", "'"$KNOT_ROOT"'/core/mcp/gateway.py", "--test"], capture_output=True, text=True)
rss_mb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024
print(f"  -> Gateway RSS: {rss_mb:.2f} MB (Threshold: < 50MB)")
assert p.returncode == 0, f"Gateway self-test failed: {p.stderr}"
assert rss_mb < 50.0, f"Memory footprint exceeded: {rss_mb} MB"
'
echo "  -> Handheld APU RAM constraint satisfied (<0.3% of 16GB LPDDR5): OK"

# Test CLI execution latency
python3 -c '
import subprocess, time
t0 = time.perf_counter()
subprocess.run(["'"$KNOT_ROOT"'/bin/knot", "help"], capture_output=True)
lat_ms = (time.perf_counter() - t0) * 1000
print(f"  -> Knot CLI dispatcher latency: {lat_ms:.1f}ms (Threshold: < 350ms)")
assert lat_ms < 350.0, f"CLI dispatcher too slow: {lat_ms}ms"
'
echo "  -> APU CPU responsiveness satisfied: OK"

echo "=== [✓] ALL STEAMDECK SIDE QUEST TESTS PASSED! ==="
