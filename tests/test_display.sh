#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Display Auto-Discovery (ISSUE-11)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
DISPLAY_SCRIPT="$KNOT_ROOT/core/installer/display.sh"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$DISPLAY_SCRIPT"
echo "  -> display.sh syntax: OK"

echo "=== [Test 2] Zero Error Swallowing Verification ==="
if grep -n "2>/dev/null\||| true\||| :" "$DISPLAY_SCRIPT"; then
  echo "Error: Detected forbidden error swallowing patterns in display.sh!" >&2
  exit 1
fi
echo "  -> Zero error swallowing: OK"

source "$DISPLAY_SCRIPT"

echo "=== [Test 3] Parsing Synthetic kscreen-doctor Outputs ==="
# Synthetic dual-monitor output with ANSI escape sequences
SAMPLE_KSCREEN=$'Output: 1 DP-2 c89b4cd4-9ec1-4fad-90d7-5be4efb912a1\n\tenabled\n\tconnected\n\t\x1b[01;32mpriority 1\x1b[0;0m\n\tDisplayPort\n\t\x1b[01;34mModes: \x1b[0;0m 1:2560x1440@59.95!  2:\x1b[01;32m2560x1440@144.00*\x1b[0;0m  3:1920x1080@60.00\n\t\x1b[01;33mScale: \x1b[0;0m1.5\nOutput: 2 eDP-1 d7785b29-ef03-4c42-97d1-7156b879604a\n\tenabled\n\tconnected\n\t\x1b[01;32mpriority 2\x1b[0;0m\n\tPanel\n\t\x1b[01;34mModes: \x1b[0;0m 106:\x1b[01;32m1920x1080@120.00*!\x1b[0;0m\n\t\x1b[01;33mScale: \x1b[0;0m1.0'

PARSED="$(display_parse_kscreen_doctor "$SAMPLE_KSCREEN")"
read -r P_RES P_REFRESH P_SCALE <<< "$PARSED"

if [ "$P_RES" != "2560x1440" ]; then
  echo "Error: expected 2560x1440, got $P_RES" >&2
  exit 1
fi
if [ "$P_REFRESH" != "144.00" ]; then
  echo "Error: expected 144.00, got $P_REFRESH" >&2
  exit 1
fi
if [ "$P_SCALE" != "1.5" ]; then
  echo "Error: expected 1.5, got $P_SCALE" >&2
  exit 1
fi
echo "  -> Priority 1 display resolution, 144Hz refresh, and 1.5 scale detected: OK"

echo "=== [Test 4] Parsing Synthetic wlr-randr Output ==="
SAMPLE_WLR=$'DP-1 "LG Electronics LG ULTRAGEAR"\n  Physical size: 600x340 mm\n  Enabled: yes\n  Modes:\n    2560x1440 px, 165.000000 Hz (preferred, current)\n    1920x1080 px, 60.000000 Hz\n  Position: 0,0\n  Scale: 1.25'

WLR_PARSED="$(display_parse_wlr_randr "$SAMPLE_WLR")"
read -r W_RES W_REFRESH W_SCALE <<< "$WLR_PARSED"

if [ "$W_RES" != "2560x1440" ] || [ "$W_REFRESH" != "165.000000" ] || [ "$W_SCALE" != "1.25" ]; then
  echo "Error: unexpected wlr-randr parse: $WLR_PARSED" >&2
  exit 1
fi
echo "  -> wlr-randr parser: OK"

echo "=== [Test 5] CLI Overrides & Formatting ==="
# Test --json output with overrides
JSON_OUT="$("$DISPLAY_SCRIPT" --resolution 3840x2160 --refresh 120 --scale 1.75 --json)"

echo "$JSON_OUT" | grep -q '"resolution": "3840x2160"'
echo "$JSON_OUT" | grep -E -q '"refresh_rate": 120(\.0+)?'
echo "$JSON_OUT" | grep -q '"scale": 1.75'
echo "  -> CLI overrides and JSON output format: OK"

# Test --export
EXPORT_OUT="$("$DISPLAY_SCRIPT" --resolution 1920x1080 --refresh 60 --scale 1.0 --export)"
echo "$EXPORT_OUT" | grep -q 'export KNOT_DISPLAY_RES="1920x1080"'
echo "$EXPORT_OUT" | grep -q 'export KNOT_DISPLAY_REFRESH="60"'
echo "$EXPORT_OUT" | grep -q 'export KNOT_DISPLAY_SCALE="1.0"'
echo "  -> CLI export output format: OK"

echo "=== [✓] ALL DISPLAY AUTO-DISCOVERY TESTS PASSED! ==="
