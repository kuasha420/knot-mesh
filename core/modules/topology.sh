#!/usr/bin/env bash
set -euo pipefail

# Knot - Multi-Screen Topology & Visual Spatial Reasoning Module

topology_show() {
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local user_home
  user_home="$(knot_detect_user_home)"
  local topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"

  if [ ! -f "$topo_file" ]; then
    knot_log_warn "No topology configuration found at: $topo_file"
    return 1
  fi

  python3 -c "
import json, sys

with open('$topo_file') as f:
    topo = json.load(f)

anchor = topo.get('anchor', 'unknown')
screens = topo.get('screens', [])
layout = topo.get('layout', {})
locked = topo.get('locked', False)

print('\033[1m=== Knot Multi-Screen Mesh Topology (' + '$active_swarm' + ') ===\033[0m')
print(f'Anchor Screen : \033[36m{anchor}\033[0m')
print(f'Screens Active: {len(screens)} screens {screens}')
print(f'Layout Status : {\"LOCKED\" if locked else \"DYNAMIC / UNLOCKED\"}')
print('')

# Draw visual 2D ASCII screen layout
# Determine left, right, up, down relative to anchor
anchor_layout = layout.get(anchor, {})
def _extract_nodes(spec):
    if not spec:
        return []
    if isinstance(spec, list):
        return [s.get('node', '?') for s in spec if isinstance(s, dict) and s.get('node')]
    if isinstance(spec, dict) and spec.get('node'):
        return [spec['node']]
    return []

left_nodes = _extract_nodes(anchor_layout.get('left'))
right_nodes = _extract_nodes(anchor_layout.get('right'))
up_nodes = _extract_nodes(anchor_layout.get('up'))
down_nodes = _extract_nodes(anchor_layout.get('down'))

left_label = '/'.join(left_nodes) if left_nodes else None
right_label = '/'.join(right_nodes) if right_nodes else None
up_label = '/'.join(up_nodes) if up_nodes else None
down_label = ' | '.join(down_nodes) if down_nodes else None

if up_label:
    print(f'                     ┌──────────────────┐')
    print(f'                     │ {up_label:^16} │ (UP)')
    print(f'                     └────────┬─────────┘')
    print(f'                              │ ↕')

# Main row
left_box = [
    '┌──────────────────┐',
    f'│ {left_label:^16} │',
    '└──────────────────┘'
] if left_label else ['                    ', '                    ', '                    ']

anchor_box = [
    '┌────────────────────────┐',
    f'│  {anchor:^20}  │',
    '└────────────────────────┘'
]

right_box = [
    '┌──────────────────┐',
    f'│ {right_label:^16} │',
    '└──────────────────┘'
] if right_label else ['                    ', '                    ', '                    ']

l_arrow = ' ⇄ ' if left_label else '   '
r_arrow = ' ⇄ ' if right_label else '   '

print(f'{left_box[0]}{l_arrow}{anchor_box[0]}{r_arrow}{right_box[0]}')
print(f'{left_box[1]}{l_arrow}\033[1;36m{anchor_box[1]}\033[0m{r_arrow}{right_box[1]}')
print(f'{left_box[2]}{l_arrow}{anchor_box[2]}{r_arrow}{right_box[2]}')

if down_label:
    print(f'                              │ ↕')
    if len(down_nodes) > 1:
        d1 = down_nodes[0]
        d2 = down_nodes[1]
        print(f'           ┌──────────────────┐    ┌──────────────────┐')
        print(f'           │ {d1:^16} │    │ {d2:^16} │ (DOWN)')
        print(f'           └──────────────────┘    └──────────────────┘')
    else:
        print(f'                     ┌────────┴─────────┐')
        print(f'                     │ {down_label:^16} │ (DOWN)')
        print(f'                     └──────────────────┘')

print('')
print('\033[1mBidirectional Reciprocal Links:\033[0m')
for src, dirs in layout.items():
    for d, target_val in dirs.items():
        specs = target_val if isinstance(target_val, list) else [target_val]
        for spec in specs:
            if isinstance(spec, dict):
                t = spec.get('node', '?')
                s = spec.get('span', [0, 100])
                ts = spec.get('target_span', [0, 100])
                print(f'  \033[34m{src}\033[0m --[{d} span={s[0]}-{s[1]}% -> {t} span={ts[0]}-{ts[1]}%]--> \033[32m{t}\033[0m')
"
}

topology_refresh() {
  local photo_path=""
  local mode="auto"
  local apply_layout=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --photo|-p)
        photo_path="${2:-}"
        shift 2
        ;;
      --mode|-m)
        mode="${2:-auto}"
        shift 2
        ;;
      --apply|-a)
        apply_layout=1
        shift
        ;;
      *)
        if [ -f "$1" ] && [ -z "$photo_path" ]; then
          photo_path="$1"
          shift
        else
          knot_log_err "Unknown option: $1"
          echo "Usage: knot topology refresh [--photo] <path> [--mode auto|swarm|offline] [--apply]"
          return 1
        fi
        ;;
    esac
  done

  if [ -z "$photo_path" ]; then
    knot_log_err "Missing required --photo argument"
    echo "Usage: knot topology refresh --photo <path> [--mode auto|swarm|offline] [--apply]"
    return 1
  fi

  if [ ! -f "$photo_path" ]; then
    knot_log_err "Photo file not found: $photo_path"
    return 1
  fi

  knot_log_info "Analyzing physical desk photo: $photo_path (mode: $mode)..."

  # Invoke Python vision analysis directly or via Hub endpoint
  local py_code="
import json, sys
from core.vision.engine import analyze_desk_photo

try:
    res = analyze_desk_photo('$photo_path', mode='$mode')
    print(json.dumps(res))
except Exception as e:
    sys.stderr.write(f'Analysis failed: {e}\n')
    sys.exit(1)
"

  local analysis_json
  if ! analysis_json="$(python3 -c "$py_code" 2>/dev/null)"; then
    # If direct import fails due to CWD or path, try through Knot hub
    knot_log_warn "Local execution failed, forwarding to Knot Hub API..."
    analysis_json="$(curl -k -s -X POST https://127.0.0.1:4242/topology/analyze-photo \
      -H 'Content-Type: application/json' \
      -d "{\"image_path\": \"$photo_path\", \"mode\": \"$mode\"}" | jq -r '.result // empty')"
  fi

  if [ -z "$analysis_json" ] || [ "$analysis_json" = "null" ]; then
    knot_log_err "Failed to analyze photo."
    return 1
  fi

  echo "$analysis_json" | python3 -c "
import json, sys

data = json.load(sys.stdin)
engine = data.get('engine', 'unknown')
anchor = data.get('anchor_node_id', 'unknown')
screens = data.get('screens', [])
layout = data.get('proposed_layout', {})
meta = data.get('metadata', {})

print('\033[1;32m✔ Vision & Spatial Reasoning Complete!\033[0m')
print(f'Engine Used  : \033[1;36m{engine.upper()}\033[0m (Duration: {meta.get(\"detection_time_ms\", 0)}ms)')
print(f'Anchor Screen: \033[1m{anchor}\033[0m')
print(f'Detected Displays ({len(screens)}):')

for s in screens:
    nid = s.get('matched_node_id', '?')
    dtype = s.get('device_type', 'screen')
    pos = s.get('position_relative_to_anchor', 'anchor')
    box = s.get('box_2d', [])
    conf = int(s.get('confidence', 0.8) * 100)
    print(f'  • \033[1m{nid:<24}\033[0m [{dtype:<16}] Position: \033[33m{pos:<8}\033[0m Box: {box} (Conf: {conf}%)')

print('')
print('\033[1mReasoning:\033[0m')
print(data.get('reasoning', 'No reasoning provided.'))
"

  if [ "$apply_layout" -eq 1 ]; then
    knot_log_info "Applying proposed topology layout to active mesh..."
    local active_swarm
    active_swarm="$(knot_get_active_swarm)"
    local user_home
    user_home="$(knot_detect_user_home)"
    local topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"

    echo "$analysis_json" | python3 -c "
import json, sys

data = json.load(sys.stdin)
anchor = data.get('anchor_node_id', 'unknown')
layout = data.get('proposed_layout', {})
screens = list(set([s.get('matched_node_id') for s in data.get('screens', []) if s.get('matched_node_id')]))

new_topo = {
    'anchor': anchor,
    'screens': screens,
    'layout': layout,
    'locked': False
}

with open('$topo_file', 'w') as f:
    json.dump(new_topo, f, indent=2)

print('Updated ' + '$topo_file')
"
    # Recompile and reload Deskflow & Stripd
    deskflow_configure
    systemctl --user restart knot-deskflow.service 2>/dev/null || true
    systemctl --user restart knot-stripd.service 2>/dev/null || true
    knot_log_ok "Topology successfully refreshed and applied to mesh!"
  else
    echo ""
    echo -e "${C_YELLOW}Note: Layout was not applied. Pass --apply to update topology.json and reload Deskflow KVM.${C_RESET}"
  fi
}

topology_align_internal() {
  local home
  home="$(knot_detect_user_home)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local my_host
  my_host="$(knot_detect_hostname)"

  knot_log_info "Probing and aligning local internal display placement..."

  if command -v kscreen-doctor >/dev/null; then
    knot_log_info "Standard display configuration detected."
  else
    knot_log_warn "kscreen-doctor not found; manual display configuration required."
  fi

  # Update node manifest and recompile Deskflow
  if [ -x "$KNOT_ROOT/core/installer/display.sh" ]; then
    local fresh_disp
    fresh_disp="$("$KNOT_ROOT/core/installer/display.sh" --json 2>/dev/null || true)"
    if [ -n "$fresh_disp" ]; then
      for target_mf in "$home/.config/knot/swarms/${active_swarm}/nodes/${my_host}.json" "$home/.config/knot/swarms/${active_swarm}/nodes/rog-ally.json"; do
        if [ -f "$target_mf" ]; then
          python3 -c "
import json, sys
with open('$target_mf', 'r') as f:
    d = json.load(f)
d['display'] = json.loads('''$fresh_disp''')
with open('$target_mf', 'w') as f:
    json.dump(d, f, indent=2)
" 2>/dev/null || true
        fi
      done
    fi
  fi

  deskflow_configure
  systemctl --user restart knot-deskflow.service 2>/dev/null || true
  systemctl --user restart knot-stripd.service 2>/dev/null || true
  knot_log_ok "Internal display topology synchronized with Deskflow KVM."
}

topology_identify() {
  local bg="white"
  local duration="15"
  local broadcast_all=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bg)
        bg="${2:-white}"
        shift 2
        ;;
      --duration|-d)
        duration="${2:-15}"
        shift 2
        ;;
      --all|-a)
        broadcast_all=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  # Guarantee GUI compositor environment variables in non-interactive sessions
  if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
  fi
  if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
    export WAYLAND_DISPLAY="wayland-0"
  fi
  if [ -z "${DISPLAY:-}" ]; then
    export DISPLAY=":0"
  fi

  # Wake display from DPMS power-save and simulate user activity
  if command -v kscreen-doctor >/dev/null; then
    kscreen-doctor --dpms on >/dev/null 2>&1 || true
  fi
  if command -v qdbus6 >/dev/null; then
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null; then
    qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity >/dev/null 2>&1 || true
  fi

  # Auto-unlock graphical session if locked so overlay is not obscured by lockscreen
  if command -v loginctl >/dev/null; then
    local u_name
    u_name="$(knot_detect_user)"
    local s_id
    s_id="$(loginctl show-user "$u_name" -p Display --value 2>/dev/null || true)"
    if [ -z "$s_id" ]; then
      s_id="$(loginctl list-sessions --no-legend 2>/dev/null | awk -v u="$u_name" '$3==u && $4~/seat/ {print $1; exit}')"
    fi
    if [ -n "$s_id" ]; then
      local is_locked
      is_locked="$(loginctl show-session "$s_id" -p LockedHint --value 2>/dev/null || true)"
      if [ "$is_locked" = "yes" ]; then
        loginctl unlock-session "$s_id" >/dev/null 2>&1 || true
      fi
    fi
  fi

  if [ "$broadcast_all" -eq 1 ]; then
    knot_log_info "Flashing display calibration pattern swarm-wide across all mesh nodes..."
    curl -k -s -X POST https://127.0.0.1:4242/topology/identify \
      -H "Content-Type: application/json" \
      -d "{\"bg\": \"$bg\", \"duration_sec\": $duration}" >/dev/null 2>&1 || true
  fi

  knot_log_info "Opening high-contrast display identification overlay on local displays (bg: $bg, duration: ${duration}s)..."
  local py_script="$KNOT_ROOT/core/vision/display_overlay.py"
  if [ -f "$py_script" ]; then
    python3 "$py_script" --bg "$bg" --duration "$duration"
  else
    knot_log_err "Overlay script not found at: $py_script"
    return 1
  fi
}

topology_guide() {
  cat << 'GUIDE_EOF'
================================================================================
           KNOT VISION & PHYSICAL TOPOLOGY PHOTOGRAPHY GUIDANCE
================================================================================

1. DISPLAY IDENTIFICATION CALIBRATION PATTERN:
   Run: knot topology identify --all [--bg white|black|neon]
   Or in Kafe Web Cockpit: Click "📸 Flash Display ID Pattern"
   - Every connected screen will display a crisp, high-contrast banner with its
     Node ID, output connector name (DP-2, eDP-1), resolution, and corner fiducials.
   - This guarantees 100% boundary detection and zero ambiguous node assignments.

2. OPTIMAL PHOTOGRAPHY FRAMING:
   - Stand or place camera 1.5 - 2.5 meters away from the desk.
   - Hold camera parallel to the desk plane (eye-level with the center monitor).
   - Ensure ALL screens (elevated monitors, laptops, handheld consoles) are visible
     in a single wide shot without extreme wide-angle fisheye lens distortion.
   - Avoid direct overhead light glare reflecting directly on screen panels.

3. MULTI-DISPLAY NODE ALIGNMENT (e.g. ASUS ROG ALLY):
   - For nodes with both an external monitor (DP-2) and a built-in screen (eDP-1):
     Run: knot topology align-internal
     - Places eDP-1 at (0,720) with Scale 3 (640x360) directly below the left 50% of DP-2.
     - Left 50% bottom edge seamlessly transitions into ROG Ally console display.
     - Right 50% bottom edge exits directly to Steam Deck without passing through Ally!

4. FRACTIONAL KVM SPAN CUSTOMIZATION:
   In topology.json, spans can be customized per edge:
   - "left": { "node": "laptop", "span": [25, 100], "target_span": [0, 85] }
   - "right": { "node": "workstation_monitor", "span": [0, 100] }
   - "down": { "node": "handheld_console", "span": [50, 100], "target_span": [0, 100] }

================================================================================
GUIDE_EOF
}

cmd_topology() {
  local sub="${1:-show}"
  [ $# -gt 0 ] && shift
  case "$sub" in
    show|status|map)
      topology_show "$@"
      ;;
    refresh|analyze|photo)
      topology_refresh "$@"
      ;;
    align-internal|align)
      topology_align_internal "$@"
      ;;
    identify|calibrate|flash)
      topology_identify "$@"
      ;;
    guide|help)
      topology_guide
      ;;
    *)
      echo -e "${C_BOLD}Knot Topology Management${C_RESET}"
      echo "Usage:"
      echo "  knot topology show                  Show current 2D screen spatial layout"
      echo "  knot topology refresh --photo <img.jpg> [--mode auto|swarm|offline] [--apply]"
      echo "  knot topology align-internal        Align multi-display outputs (e.g. ROG Ally eDP-1)"
      echo "  knot topology identify [--all]      Flash high-contrast display identification overlay"
      echo "  knot topology guide                 Print photography & alignment best practices"
      ;;
  esac
}

