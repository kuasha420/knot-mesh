#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Display Cockpit Launcher & Headless Fleet Screen Capture Module
# Authoritative implementation for Issues #71 and #66

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/hub.sh"

display_launch_app() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot display launch <target_node> <preset|command> [--dry-run] [args...]"
    echo ""
    echo "Presets:"
    echo "  board        Launch live Swarm Council DB message board (compact)"
    echo "  quota        Launch live model quotas visualizer (compact)"
    echo "  confluence   Launch multi-agent interactive spatial confluence grid"
    return 0
  fi

  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: knot display launch <target_node> <preset|command> [--dry-run] [args...]"
    return 1
  fi
  shift

  local preset_or_cmd="${1:-}"
  if [ -z "$preset_or_cmd" ]; then
    knot_log_err "Missing preset or command for display launch"
    return 1
  fi
  shift

  local dry_run=0
  local extra_args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run)
        dry_run=1
        shift
        ;;
      *)
        extra_args+=("$1")
        shift
        ;;
    esac
  done

  # Resolve preset
  local launch_cmd=""
  case "$preset_or_cmd" in
    board)
      launch_cmd="knot council board --compact"
      ;;
    quota)
      launch_cmd="knot quota live --compact"
      ;;
    confluence)
      launch_cmd="knot council start --interactive --tiling grid"
      ;;
    *)
      launch_cmd="$preset_or_cmd"
      ;;
  esac

  if [ ${#extra_args[@]} -gt 0 ]; then
    launch_cmd="$launch_cmd ${extra_args[*]}"
  fi

  # Resolve central Knot Hub URL for injection across remote strands
  local resolved_hub_url=""
  if [ -n "${KNOT_HUB_URL:-}" ]; then
    resolved_hub_url="$KNOT_HUB_URL"
  else
    resolved_hub_url="$(hub_resolve_url)"
  fi

  local full_cmd="export KNOT_HUB_URL='$resolved_hub_url'; $launch_cmd"

  if [ "$dry_run" -eq 1 ]; then
    echo "$full_cmd"
    return 0
  fi

  local my_node my_host is_local=0
  my_node="$(knot_detect_node_id)"
  my_host="$(knot_detect_hostname)"
  if [ "$target" = "$my_node" ] || [ "$target" = "$my_host" ] || [ "$target" = "local" ] || [ "$target" = "localhost" ]; then
    is_local=1
  fi

  if [ "$is_local" -eq 1 ]; then
    knot_log_info "Launching local display cockpit with KNOT_HUB_URL=$resolved_hub_url..."
    bash -lc "$full_cmd"
  else
    knot_log_info "Launching remote display cockpit on '$target' with KNOT_HUB_URL=$resolved_hub_url..."
    "$KNOT_ROOT/bin/knot" exec "$target" "$full_cmd"
  fi
}

display_capture_fleet() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot display capture-fleet [--node <node_id|--all>] [--output-dir <path>] [--format png|base64] [--json]"
    return 0
  fi

  local target_node="--all"
  local output_dir="/tmp/knot_captures"
  local fmt="png"
  local json_flag=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --node)
        target_node="${2:-}"
        shift 2
        ;;
      --output-dir)
        output_dir="${2:-}"
        shift 2
        ;;
      --format)
        fmt="${2:-png}"
        shift 2
        ;;
      --json)
        json_flag=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  mkdir -p "$output_dir"
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  local ts_compact
  ts_compact="$(date -u +"%Y%m%d_%H%M%S")"

  local nodes=()
  local my_node my_host
  my_node="$(knot_detect_node_id)"
  my_host="$(knot_detect_hostname)"

  if [ "$target_node" = "--all" ]; then
    local nodes_dir=""
    if nodes_dir="$(knot_get_nodes_dir 2>&1)"; then
      for mf in "$nodes_dir/"*.json; do
        [ -e "$mf" ] || continue
        local nid
        nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
        if [ -n "$nid" ]; then
          nodes+=("$nid")
        fi
      done
    fi
    if [ ${#nodes[@]} -eq 0 ]; then
      nodes+=("$my_node")
    fi
  else
    nodes+=("$target_node")
  fi

  local captures=()

  for node in "${nodes[@]}"; do
    local is_local=0
    if [ "$node" = "$my_node" ] || [ "$node" = "$my_host" ] || [ "$node" = "local" ] || [ "$node" = "localhost" ]; then
      is_local=1
    fi

    local out_path="$output_dir/${node}_${ts_compact}.png"
    local cap_status="ok"
    local cap_disp="wayland-0"
    local cap_err=""
    local width=1920
    local height=1080

    if [ "$is_local" -eq 1 ]; then
      local uid
      uid="$(id -u)"
      export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
      if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        cap_disp="$WAYLAND_DISPLAY"
      elif [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; then
        cap_disp="wayland-0"
      fi

      if [ -z "${DISPLAY:-}" ] && [ -e "/tmp/.X11-unix/X0" ]; then
        export DISPLAY=":0"
      fi

      local cap_ok=0
      if command -v spectacle >/dev/null; then
        local spec_out=""
        if spec_out="$(WAYLAND_DISPLAY="$cap_disp" spectacle -b -n -o "$out_path" 2>&1)" && [ -f "$out_path" ] && [ -s "$out_path" ]; then
          cap_ok=1
        fi
      fi

      if [ "$cap_ok" -eq 0 ] && command -v grim >/dev/null; then
        local grim_out=""
        if grim_out="$(WAYLAND_DISPLAY="$cap_disp" grim "$out_path" 2>&1)" && [ -f "$out_path" ] && [ -s "$out_path" ]; then
          cap_ok=1
        fi
      fi

      if [ "$cap_ok" -eq 0 ] && [ -n "${DISPLAY:-}" ]; then
        cap_disp="$DISPLAY"
        if command -v import >/dev/null; then
          local imp_out=""
          if imp_out="$(import -window root "$out_path" 2>&1)" && [ -f "$out_path" ] && [ -s "$out_path" ]; then
            cap_ok=1
          fi
        elif command -v maim >/dev/null; then
          local maim_out=""
          if maim_out="$(maim "$out_path" 2>&1)" && [ -f "$out_path" ] && [ -s "$out_path" ]; then
            cap_ok=1
          fi
        fi
      fi

      if [ "$cap_ok" -eq 1 ]; then
        # Parse PNG dimensions
        local dims=""
        if dims="$(python3 -c '
import sys
try:
    with open(sys.argv[1], "rb") as f:
        h = f.read(24)
        if h.startswith(b"\x89PNG\r\n\x1a\n"):
            w = int.from_bytes(h[16:20], "big")
            hi = int.from_bytes(h[20:24], "big")
            print(f"{w} {hi}")
            sys.exit(0)
except Exception as _err:
    sys.stderr.write(f"Notice: [display] Failed to parse PNG dimensions: {_err}\n")
print("1920 1080")
' "$out_path")"; then
          read -r width height <<< "$dims"
        fi
      else
        cap_status="error"
        cap_err="No active graphical display server or capture tool available locally"
      fi
    else
      # Remote node capture via SSH
      local remote_cap_script='
        uid="$(id -u)"
        export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$uid}"
        disp="${WAYLAND_DISPLAY:-wayland-0}"
        if [ -z "${DISPLAY:-}" ] && [ -e "/tmp/.X11-unix/X0" ]; then
          export DISPLAY=":0"
        fi
        tmp="/tmp/knot_cap_$$.png"
        ok=0
        if command -v spectacle >/dev/null && WAYLAND_DISPLAY="$disp" spectacle -b -n -o "$tmp" 2>&1; then
          [ -s "$tmp" ] && ok=1
        elif command -v grim >/dev/null && WAYLAND_DISPLAY="$disp" grim "$tmp" 2>&1; then
          [ -s "$tmp" ] && ok=1
        elif [ -n "${DISPLAY:-}" ] && command -v maim >/dev/null && maim "$tmp" 2>&1; then
          [ -s "$tmp" ] && ok=1
        elif [ -n "${DISPLAY:-}" ] && command -v import >/dev/null && import -window root "$tmp" 2>&1; then
          [ -s "$tmp" ] && ok=1
        fi
        if [ "$ok" -eq 1 ]; then
          cat "$tmp"
          rm -f "$tmp"
          exit 0
        else
          rm -f "$tmp"
          exit 1
        fi
      '
      local ssh_err_file="$output_dir/.ssh_err_${node}_$$.log"
      if ssh -o BatchMode=yes -o ConnectTimeout=5 "$node" "bash -lc $(printf %q "$remote_cap_script")" > "$out_path" 2> "$ssh_err_file" && [ -s "$out_path" ]; then
        rm -f "$ssh_err_file"
        local dims=""
        if dims="$(python3 -c '
import sys
try:
    with open(sys.argv[1], "rb") as f:
        h = f.read(24)
        if h.startswith(b"\x89PNG\r\n\x1a\n"):
            w = int.from_bytes(h[16:20], "big")
            hi = int.from_bytes(h[20:24], "big")
            print(f"{w} {hi}")
            sys.exit(0)
except Exception as _err:
    sys.stderr.write(f"Notice: [display] Failed to parse remote PNG dimensions: {_err}\n")
print("1920 1080")
' "$out_path")"; then
          read -r width height <<< "$dims"
        fi
      else
        local ssh_err=""
        if [ -f "$ssh_err_file" ]; then
          ssh_err="$(cat "$ssh_err_file")"
          rm -f "$ssh_err_file"
        fi
        rm -f "$out_path"
        cap_status="error"
        cap_err="Remote capture failed on node '\''$node'\'': ${ssh_err:-unreachable or display server inactive}"
      fi
    fi

    # Assemble JSON object for this capture
    local b64_str=""
    if [ "$fmt" = "base64" ] && [ "$cap_status" = "ok" ] && [ -f "$out_path" ]; then
      if ! b64_str="$(base64 -w 0 "$out_path" 2>&1)"; then
        b64_str=""
      fi
    fi

    local entry=""
    if [ "$cap_status" = "ok" ]; then
      if [ "$fmt" = "base64" ]; then
        entry=$(python3 -c '
import sys, json
print(json.dumps({
    "node": sys.argv[1],
    "display": sys.argv[2],
    "status": "ok",
    "path": sys.argv[3],
    "width": int(sys.argv[4]),
    "height": int(sys.argv[5]),
    "base64": sys.argv[6]
}))' "$node" "$cap_disp" "$out_path" "$width" "$height" "$b64_str")
      else
        entry=$(python3 -c '
import sys, json
print(json.dumps({
    "node": sys.argv[1],
    "display": sys.argv[2],
    "status": "ok",
    "path": sys.argv[3],
    "width": int(sys.argv[4]),
    "height": int(sys.argv[5])
}))' "$node" "$cap_disp" "$out_path" "$width" "$height")
      fi
    else
      entry=$(python3 -c '
import sys, json
print(json.dumps({
    "node": sys.argv[1],
    "display": "none",
    "status": "error",
    "error": sys.argv[2]
}))' "$node" "$cap_err")
    fi
    captures+=("$entry")
  done

  # Assemble fleet-wide JSON
  python3 -c '
import sys, json
ts = sys.argv[1]
raw_caps = sys.argv[2:]
parsed = [json.loads(c) for c in raw_caps if c.strip()]
print(json.dumps({
    "timestamp": ts,
    "captures": parsed
}, indent=2))
' "$timestamp" "${captures[@]}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    launch)
      shift
      display_launch_app "$@"
      ;;
    capture-fleet|capture)
      shift
      display_capture_fleet "$@"
      ;;
    *)
      echo "Usage: display.sh <launch|capture-fleet> [args...]"
      exit 1
      ;;
  esac
fi
