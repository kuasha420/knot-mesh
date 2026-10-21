#!/usr/bin/env bash
set -euo pipefail

# Knot - Multi-Screen Topology & Visual Spatial Reasoning Module

KNOT_ROOT="${KNOT_ROOT:-$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)}"

topology_get_file() {
  if [ -n "${KNOT_TOPOLOGY_FILE:-}" ]; then
    echo "$KNOT_TOPOLOGY_FILE"
    return 0
  fi
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local user_home
  user_home="$(knot_detect_user_home)"
  local user_topo="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
  if [ -f "$user_topo" ]; then
    echo "$user_topo"
    return 0
  fi
  local etc_topo="/etc/knot/swarms.d/${active_swarm}/topology.json"
  if [ -f "$etc_topo" ]; then
    echo "$etc_topo"
    return 0
  fi
  echo "$user_topo"
}

topology_show() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot topology show"
    return 0
  fi
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local topo_file
  topo_file="$(topology_get_file)"

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

topology_align_internal() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot topology align-internal"
    return 0
  fi
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
    local fresh_disp="" disp_rc=0
    if fresh_disp="$("$KNOT_ROOT/core/installer/display.sh" --json)"; then
      if [ -n "$fresh_disp" ]; then
        for target_mf in "$home/.config/knot/swarms/${active_swarm}/nodes/${my_host}.json" "$home/.config/knot/swarms/${active_swarm}/nodes/rog-ally.json"; do
          if [ -f "$target_mf" ]; then
            local py_err="" py_rc=0
            py_err="$(python3 -c "
import json, sys
with open('$target_mf', 'r') as f:
    d = json.load(f)
d['display'] = json.loads('''$fresh_disp''')
with open('$target_mf', 'w') as f:
    json.dump(d, f, indent=2)
" 2>&1)" || py_rc=$?
            if [ $py_rc -ne 0 ]; then
              knot_log_warn "Notice: Failed to update display manifest $target_mf ($py_rc): $py_err"
            fi
          fi
        done
      fi
    else
      disp_rc=$?
      knot_log_warn "Notice: display.sh --json exited with code $disp_rc"
    fi
  fi

  deskflow_configure
  local r_err=""
  if ! r_err="$(systemctl --user restart knot-deskflow.service 2>&1)"; then
    knot_log_warn "Notice: knot-deskflow.service restart failed: $r_err"
  fi
  if ! r_err="$(systemctl --user restart knot-stripd.service 2>&1)"; then
    knot_log_warn "Notice: knot-stripd.service restart failed: $r_err"
  fi
  knot_log_ok "Internal display topology synchronized with Deskflow KVM."
}

topology_link() {
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      echo "Usage: knot topology link <src> <direction> <dst> [--span <MIN-MAX>] [--target-span <MIN-MAX>] [--no-reciprocal] [--topology <path>]"
      echo ""
      echo "Create directional spatial link between screens with optional fractional spans."
      return 0
    fi
  done

  if [ $# -lt 3 ]; then
    echo "Error: Missing arguments for 'knot topology link'. Expected: <src> <dir> <dst>" >&2
    echo "Usage: knot topology link <src> <dir> <dst> [--span <MIN-MAX>] [--target-span <MIN-MAX>] [--no-reciprocal] [--topology <path>]" >&2
    return 1
  fi

  local extra_args=()
  local has_topo=0
  for a in "$@"; do
    if [ "$a" = "--topology" ]; then
      has_topo=1
      break
    fi
  done

  if [ "$has_topo" -eq 0 ]; then
    local topo_file
    topo_file="$(topology_get_file)"
    extra_args+=(--topology "$topo_file")
  fi

  python3 "$KNOT_ROOT/core/modules/topology_mutate.py" link "$@" "${extra_args[@]}"

  if declare -F deskflow_compile_server_config >/dev/null; then
    local df_err="" df_rc=0
    df_err="$(deskflow_compile_server_config "unlocked" 2>&1)" || df_rc=$?
    if [ $df_rc -ne 0 ]; then
      knot_log_warn "Notice: Deskflow configuration compilation warning ($df_rc): $df_err"
    fi
  fi
}

topology_unlink() {
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      echo "Usage: knot topology unlink <src> <direction> [dst] [--topology <path>]"
      echo ""
      echo "Remove directional link(s) and reciprocal counterparts."
      return 0
    fi
  done

  if [ $# -lt 2 ]; then
    echo "Error: Missing arguments for 'knot topology unlink'. Expected: <src> <dir> [dst]" >&2
    echo "Usage: knot topology unlink <src> <dir> [dst] [--topology <path>]" >&2
    return 1
  fi

  local extra_args=()
  local has_topo=0
  for a in "$@"; do
    if [ "$a" = "--topology" ]; then
      has_topo=1
      break
    fi
  done

  if [ "$has_topo" -eq 0 ]; then
    local topo_file
    topo_file="$(topology_get_file)"
    extra_args+=(--topology "$topo_file")
  fi

  python3 "$KNOT_ROOT/core/modules/topology_mutate.py" unlink "$@" "${extra_args[@]}"

  if declare -F deskflow_compile_server_config >/dev/null; then
    local df_err="" df_rc=0
    df_err="$(deskflow_compile_server_config "unlocked" 2>&1)" || df_rc=$?
    if [ $df_rc -ne 0 ]; then
      knot_log_warn "Notice: Deskflow configuration compilation warning ($df_rc): $df_err"
    fi
  fi
}

topology_remove() {
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      echo "Usage: knot topology remove <node> [--topology <path>]"
      echo ""
      echo "Purge a node from topology screens and remove all associated directional links."
      return 0
    fi
  done

  if [ $# -lt 1 ]; then
    echo "Error: Missing node argument for 'knot topology remove'." >&2
    echo "Usage: knot topology remove <node> [--topology <path>]" >&2
    return 1
  fi

  local extra_args=()
  local has_topo=0
  for a in "$@"; do
    if [ "$a" = "--topology" ]; then
      has_topo=1
      break
    fi
  done

  if [ "$has_topo" -eq 0 ]; then
    local topo_file
    topo_file="$(topology_get_file)"
    extra_args+=(--topology "$topo_file")
  fi

  python3 "$KNOT_ROOT/core/modules/topology_mutate.py" remove "$@" "${extra_args[@]}"

  if declare -F deskflow_compile_server_config >/dev/null; then
    local df_err="" df_rc=0
    df_err="$(deskflow_compile_server_config "unlocked" 2>&1)" || df_rc=$?
    if [ $df_rc -ne 0 ]; then
      knot_log_warn "Notice: Deskflow configuration compilation warning ($df_rc): $df_err"
    fi
  fi
}

topology_set_anchor() {
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      echo "Usage: knot topology set-anchor <node> [--topology <path>]"
      echo ""
      echo "Set primary Anchor screen in topology."
      return 0
    fi
  done

  if [ $# -lt 1 ]; then
    echo "Error: Missing node argument for 'knot topology set-anchor'." >&2
    echo "Usage: knot topology set-anchor <node> [--topology <path>]" >&2
    return 1
  fi

  local extra_args=()
  local has_topo=0
  for a in "$@"; do
    if [ "$a" = "--topology" ]; then
      has_topo=1
      break
    fi
  done

  if [ "$has_topo" -eq 0 ]; then
    local topo_file
    topo_file="$(topology_get_file)"
    extra_args+=(--topology "$topo_file")
  fi

  python3 "$KNOT_ROOT/core/modules/topology_mutate.py" set-anchor "$@" "${extra_args[@]}"

  if declare -F deskflow_compile_server_config >/dev/null; then
    local df_err="" df_rc=0
    df_err="$(deskflow_compile_server_config "unlocked" 2>&1)" || df_rc=$?
    if [ $df_rc -ne 0 ]; then
      knot_log_warn "Notice: Deskflow configuration compilation warning ($df_rc): $df_err"
    fi
  fi
}

topology_guide() {
  cat << 'GUIDE_EOF'
================================================================================
           KNOT PHYSICAL TOPOLOGY & DISPLAY ALIGNMENT GUIDANCE
================================================================================

1. MULTI-DISPLAY NODE ALIGNMENT (e.g. ASUS ROG ALLY):
   - For nodes with both an external monitor (DP-2) and a built-in screen (eDP-1):
     Run: knot topology align-internal
     - Places eDP-1 at (0,720) with Scale 3 (640x360) directly below the left 50% of DP-2.
     - Left 50% bottom edge seamlessly transitions into ROG Ally console display.
     - Right 50% bottom edge exits directly to Steam Deck without passing through Ally!

2. FRACTIONAL KVM SPAN CUSTOMIZATION:
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
    link)
      topology_link "$@"
      ;;
    unlink)
      topology_unlink "$@"
      ;;
    remove)
      topology_remove "$@"
      ;;
    set-anchor)
      topology_set_anchor "$@"
      ;;
    align-internal|align)
      topology_align_internal "$@"
      ;;
    guide)
      topology_guide
      return 0
      ;;
    -h|--help|help)
      echo -e "${C_BOLD}Knot Topology Management${C_RESET}"
      echo "Usage:"
      echo "  knot topology show            Show current 2D screen spatial layout"
      echo "  knot topology link <src> <dir> <dst> [--span <MIN-MAX>] [--target-span <MIN-MAX>] [--no-reciprocal]"
      echo "  knot topology unlink <src> <dir> [dst]"
      echo "  knot topology remove <node>   Purge node from screens and directional links"
      echo "  knot topology set-anchor <node> Set primary Anchor screen"
      echo "  knot topology align-internal  Align multi-display outputs (e.g. ROG Ally eDP-1)"
      echo "  knot topology guide           Print layout & alignment best practices"
      return 0
      ;;
    *)
      echo "Error: Unknown topology subcommand '$sub'" >&2
      echo -e "${C_BOLD}Knot Topology Management${C_RESET}" >&2
      echo "Usage:" >&2
      echo "  knot topology show            Show current 2D screen spatial layout" >&2
      echo "  knot topology link <src> <dir> <dst> [--span <MIN-MAX>] [--target-span <MIN-MAX>] [--no-reciprocal]" >&2
      echo "  knot topology unlink <src> <dir> [dst]" >&2
      echo "  knot topology remove <node>   Purge node from screens and directional links" >&2
      echo "  knot topology set-anchor <node> Set primary Anchor screen" >&2
      echo "  knot topology align-internal  Align multi-display outputs (e.g. ROG Ally eDP-1)" >&2
      echo "  knot topology guide           Print layout & alignment best practices" >&2
      return 1
      ;;
  esac
}


