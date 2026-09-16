#!/usr/bin/env bash
set -euo pipefail

# Knot Wayland Display Auto-Discovery Module
# Extracts active display resolution, refresh rate, and scale factor.

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
if [ -f "$KNOT_ROOT/core/lib.sh" ]; then
  # shellcheck source=../../core/lib.sh
  source "$KNOT_ROOT/core/lib.sh"
fi

display_parse_kscreen_doctor() {
  local input
  input="$(echo "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')"
  local in_output=0
  local is_enabled=0
  local is_connected=0
  local priority=999
  local best_priority=999
  local active_res=""
  local active_refresh=""
  local active_scale=""

  local cur_res=""
  local cur_refresh=""
  local cur_scale="1.0"

  while IFS= read -r line; do
    local line_clean
    line_clean="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ "$line_clean" =~ ^Output:[[:space:]]*([0-9]+) ]]; then
      if [ "$is_enabled" -eq 1 ] && [ "$is_connected" -eq 1 ] && [ -n "$cur_res" ]; then
        if [ "$priority" -lt "$best_priority" ]; then
          best_priority="$priority"
          active_res="$cur_res"
          active_refresh="$cur_refresh"
          active_scale="$cur_scale"
        fi
      fi
      in_output=1
      is_enabled=0
      is_connected=0
      priority=999
      cur_res=""
      cur_refresh=""
      cur_scale="1.0"
      continue
    fi

    if [ "$in_output" -eq 1 ]; then
      if [ "$line_clean" = "enabled" ]; then
        is_enabled=1
      elif [ "$line_clean" = "connected" ]; then
        is_connected=1
      elif [[ "$line_clean" =~ ^priority[[:space:]]+([0-9]+) ]]; then
        priority="${BASH_REMATCH[1]}"
      elif [[ "$line_clean" =~ ^Scale:[[:space:]]*([0-9.]+) ]]; then
        cur_scale="${BASH_REMATCH[1]}"
      elif [[ "$line_clean" =~ Modes: ]]; then
        if [[ "$line" =~ ([0-9]+)x([0-9]+)@([0-9.]+)\* ]]; then
          cur_res="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
          cur_refresh="${BASH_REMATCH[3]}"
        fi
      fi
    fi
  done <<< "$input"

  if [ "$is_enabled" -eq 1 ] && [ "$is_connected" -eq 1 ] && [ -n "$cur_res" ]; then
    if [ "$priority" -lt "$best_priority" ]; then
      active_res="$cur_res"
      active_refresh="$cur_refresh"
      active_scale="$cur_scale"
    fi
  fi

  if [ -n "$active_res" ]; then
    echo "$active_res $active_refresh $active_scale"
    return 0
  fi
  return 1
}

display_parse_wlr_randr() {
  local input
  input="$(echo "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')"
  local cur_res=""
  local cur_refresh=""
  local cur_scale="1.0"

  while IFS= read -r line; do
    if [[ "$line" =~ Scale:[[:space:]]*([0-9.]+) ]]; then
      cur_scale="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ([0-9]+)x([0-9]+)[[:space:]]*px,[[:space:]]*([0-9.]+)[[:space:]]*Hz[[:space:]]*\(.*current.*\) ]]; then
      cur_res="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
      cur_refresh="${BASH_REMATCH[3]}"
    fi
  done <<< "$input"

  if [ -n "$cur_res" ]; then
    echo "$cur_res $cur_refresh $cur_scale"
    return 0
  fi
  return 1
}

display_parse_xrandr() {
  local input
  input="$(echo "$1" | sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g')"
  local cur_res=""
  local cur_refresh=""
  local cur_scale="1.0"

  while IFS= read -r line; do
    if [[ "$line" =~ connected[[:space:]]+(primary[[:space:]]+)?([0-9]+)x([0-9]+) ]]; then
      cur_res="${BASH_REMATCH[2]}x${BASH_REMATCH[3]}"
    elif [[ "$line" =~ ([0-9.]+)\* ]]; then
      cur_refresh="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "$input"

  if [ -n "$cur_res" ]; then
    echo "$cur_res ${cur_refresh:-60.0} $cur_scale"
    return 0
  fi
  return 1
}

display_detect_specs() {
  local detected=""

  if command -v kscreen-doctor >/dev/null; then
    local kout=""
    if kout="$(kscreen-doctor -o 2>&1)"; then
      if kparsed="$(display_parse_kscreen_doctor "$kout")"; then
        detected="$kparsed"
      fi
    fi
  fi

  if [ -z "$detected" ] && command -v wlr-randr >/dev/null; then
    local wout=""
    if wout="$(wlr-randr 2>&1)"; then
      if wparsed="$(display_parse_wlr_randr "$wout")"; then
        detected="$wparsed"
      fi
    fi
  fi

  if [ -z "$detected" ] && command -v xrandr >/dev/null; then
    local xout=""
    if xout="$(xrandr --current 2>&1)"; then
      if xparsed="$(display_parse_xrandr "$xout")"; then
        detected="$xparsed"
      fi
    fi
  fi

  if [ -n "$detected" ]; then
    echo "$detected"
  else
    echo "1920x1080 60.0 1.0"
  fi
}

display_format_json() {
  local res="$1"
  local refresh="$2"
  local scale="$3"
  local raw_kscreen="${4:-}"

  python3 -c '
import sys, json, re

res = sys.argv[1]
try:
    refresh = float(sys.argv[2])
except ValueError:
    refresh = 60.0
try:
    scale = float(sys.argv[3])
except ValueError:
    scale = 1.0

kraw = sys.argv[4] if len(sys.argv) > 4 else ""
outputs = []

if kraw:
    text = re.sub(r"\x1b\[[0-9;]*[a-zA-Z]", "", kraw)
    cur = {}
    for line in text.splitlines():
        line = line.strip()
        m_out = re.match(r"^Output:\s*\d+\s+([^\s]+)", line)
        if m_out:
            if cur and cur.get("enabled") and cur.get("connected") and cur.get("resolution"):
                outputs.append(cur)
            cur = {
                "name": m_out.group(1),
                "enabled": False,
                "connected": False,
                "priority": 999,
                "scale": 1.0,
                "geometry": "",
                "resolution": "",
                "refresh_rate": 60.0
            }
            continue
        if not cur:
            continue
        if line == "enabled":
            cur["enabled"] = True
        elif line == "connected":
            cur["connected"] = True
        elif line.startswith("priority"):
            parts = line.split()
            if len(parts) >= 2 and parts[1].isdigit():
                cur["priority"] = int(parts[1])
        elif line.startswith("Geometry:"):
            cur["geometry"] = line.split(":", 1)[1].strip()
        elif line.startswith("Scale:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    cur["scale"] = float(parts[1])
                except ValueError:
                    pass
        elif "Modes:" in line or ("*" in line and "x" in line and "@" in line):
            m_mode = re.search(r"(\d+)x(\d+)@([0-9.]+)\*", line)
            if m_mode:
                cur["resolution"] = f"{m_mode.group(1)}x{m_mode.group(2)}"
                try:
                    cur["refresh_rate"] = float(m_mode.group(3))
                except ValueError:
                    pass
    if cur and cur.get("enabled") and cur.get("connected") and cur.get("resolution"):
        outputs.append(cur)

    outputs = sorted(outputs, key=lambda o: o["priority"])

formatted_outputs = []
for idx, o in enumerate(outputs):
    formatted_outputs.append({
        "name": o["name"],
        "primary": (idx == 0),
        "priority": o["priority"],
        "resolution": o["resolution"],
        "refresh_rate": round(o["refresh_rate"], 2),
        "scale": round(o["scale"], 2),
        "geometry": o["geometry"]
    })

payload = {
    "resolution": res,
    "refresh_rate": round(refresh, 2),
    "scale": round(scale, 2)
}
if formatted_outputs:
    payload["outputs"] = formatted_outputs

print(json.dumps(payload, indent=2))
' "$res" "$refresh" "$scale" "$raw_kscreen"
}

main() {
  local override_res=""
  local override_refresh=""
  local override_scale=""
  local output_format="text"

  while [ $# -gt 0 ]; do
    case "$1" in
      --resolution)
        override_res="$2"
        shift 2
        ;;
      --refresh)
        override_refresh="$2"
        shift 2
        ;;
      --scale)
        override_scale="$2"
        shift 2
        ;;
      --json)
        output_format="json"
        shift
        ;;
      --export)
        output_format="export"
        shift
        ;;
      -h|--help)
        echo "Usage: display.sh [--resolution <WxH>] [--refresh <Hz>] [--scale <float>] [--json] [--export]"
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  local raw_detected
  local raw_kscreen=""
  if command -v kscreen-doctor >/dev/null; then
    if ! raw_kscreen="$(kscreen-doctor -o 2>&1)"; then
      raw_kscreen=""
    fi
  fi

  raw_detected="$(display_detect_specs)"
  read -r det_res det_refresh det_scale <<< "$raw_detected"

  local final_res="${override_res:-$det_res}"
  local final_refresh="${override_refresh:-$det_refresh}"
  local final_scale="${override_scale:-$det_scale}"

  if [ "$output_format" = "json" ]; then
    display_format_json "$final_res" "$final_refresh" "$final_scale" "$raw_kscreen"
  elif [ "$output_format" = "export" ]; then
    echo "export KNOT_DISPLAY_RES=\"$final_res\""
    echo "export KNOT_DISPLAY_REFRESH=\"$final_refresh\""
    echo "export KNOT_DISPLAY_SCALE=\"$final_scale\""
  else
    echo "Resolution:   $final_res"
    echo "Refresh Rate: ${final_refresh} Hz"
    echo "Scale Factor: $final_scale"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
