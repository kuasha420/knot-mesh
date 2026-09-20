#!/usr/bin/env bash
set -euo pipefail

# Knot Graceful Mesh Shutdown & Reboot Module
# Coordinates graceful service drains and OS shutdown across mesh nodes from any node.

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

shutdown_parse_delay() {
  local val="${1:-now}"
  if [ "$val" = "now" ] || [ "$val" = "0" ] || [ "$val" = "0s" ] || [ "$val" = "0m" ]; then
    echo "now"
    return 0
  fi

  # Handle minute suffix: e.g. 5m
  if [[ "$val" =~ ^([0-9]+)m$ ]]; then
    local m="${BASH_REMATCH[1]}"
    if [ "$m" -eq 0 ]; then
      echo "now"
    else
      echo "+$m"
    fi
    return 0
  fi

  # Handle second suffix: e.g. 120s -> convert to minutes (rounded up)
  if [[ "$val" =~ ^([0-9]+)s$ ]]; then
    local s="${BASH_REMATCH[1]}"
    if [ "$s" -eq 0 ]; then
      echo "now"
    else
      local m=$(( (s + 59) / 60 ))
      echo "+$m"
    fi
    return 0
  fi

  # Pure integer: treat as minutes
  if [[ "$val" =~ ^[0-9]+$ ]]; then
    if [ "$val" -eq 0 ]; then
      echo "now"
    else
      echo "+$val"
    fi
    return 0
  fi

  # Already formatted like +5
  if [[ "$val" =~ ^\+[0-9]+$ ]]; then
    echo "$val"
    return 0
  fi

  echo "now"
}

shutdown_stop_local_services() {
  knot_log_info "Gracefully stopping local Knot services on $(knot_detect_hostname)..."

  # 1. Stop Knot Worker Agent
  if systemctl --user is-active knot-agent.service >/dev/null 2>&1; then
    knot_log_info "Stopping knot-agent.service (releasing active tasks)..."
    systemctl --user stop knot-agent.service 2>/dev/null || true
  fi

  # 2. Stop Deskflow KVM if running
  if systemctl --user is-active --quiet knot-deskflow.service; then
    systemctl --user stop knot-deskflow.service || knot_log_warn "Failed to stop knot-deskflow.service"
  fi

  # 3. If this host is Anchor, gracefully stop Hub and persistence databases
  local my_host
  my_host="$(knot_detect_hostname)"
  local anchor_host=""
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    local SWARM_ID="" ANCHOR_ID="" ANCHOR_HOST=""
    if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
      # shellcheck disable=SC1090
      source "/etc/knot/swarms.d/${active_swarm}.conf"
      anchor_host="${ANCHOR_HOST:-$ANCHOR_ID}"
    fi
  fi
  if [ -z "$anchor_host" ]; then
    local a_manifest=""
    if a_manifest="$(knot_get_manifest_path "desktop" 2>/dev/null)"; then
      local h
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$a_manifest")"
      if [ -n "$h" ]; then anchor_host="$h"; fi
    fi
  fi

  if [ -n "$anchor_host" ] && [ "$my_host" = "$anchor_host" ]; then
    if systemctl --user is-active --quiet knot-hub.service; then
      knot_log_info "Stopping knot-hub.service..."
      systemctl --user stop knot-hub.service || knot_log_warn "Failed to stop knot-hub.service"
    fi
  fi

  sync
  knot_log_ok "Local Knot services gracefully stopped and filesystem synced."
}

shutdown_resume_local_services() {
  knot_log_info "Resuming local Knot services on $(knot_detect_hostname)..."
  local my_host
  my_host="$(knot_detect_hostname)"
  local anchor_host=""
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    local SWARM_ID="" ANCHOR_ID="" ANCHOR_HOST=""
    if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
      # shellcheck disable=SC1090
      source "/etc/knot/swarms.d/${active_swarm}.conf"
      anchor_host="${ANCHOR_HOST:-$ANCHOR_ID}"
    fi
  fi
  if [ -z "$anchor_host" ]; then
    local a_manifest=""
    if a_manifest="$(knot_get_manifest_path "desktop" 2>/dev/null)"; then
      local h
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$a_manifest")"
      if [ -n "$h" ]; then anchor_host="$h"; fi
    fi
  fi

  if [ -n "$anchor_host" ] && [ "$my_host" = "$anchor_host" ]; then
    systemctl --user start knot-hub.service 2>/dev/null || true
  fi
  systemctl --user start knot-agent.service 2>/dev/null || true
  systemctl --user start knot-deskflow.service 2>/dev/null || true
  knot_log_ok "Local Knot services active."
}

shutdown_exec_local() {
  local action="${1:-poweroff}"
  local delay_arg="${2:-now}"
  local wall_msg="${3:-Shutdown scheduled via Knot Swarm}"

  local time_spec
  time_spec="$(shutdown_parse_delay "$delay_arg")"

  if [ "$action" = "cancel" ]; then
    sudo shutdown -c 2>/dev/null || true
    shutdown_resume_local_services
    knot_log_ok "Shutdown/reboot cancelled on $(knot_detect_hostname)."
    return 0
  fi

  if [ "$action" = "show" ] || [ "$action" = "status" ]; then
    local my_host show_out
    my_host="$(knot_detect_hostname)"
    show_out="$(shutdown --show 2>&1)" || true
    echo "[$my_host] $show_out"
    return 0
  fi

  if [ "$time_spec" = "now" ]; then
    shutdown_stop_local_services
    if [ "$action" = "reboot" ]; then
      knot_log_warn "Executing immediate reboot on $(knot_detect_hostname)..."
      sudo systemctl reboot
    else
      knot_log_warn "Executing immediate poweroff on $(knot_detect_hostname)..."
      sudo systemctl poweroff
    fi
  else
    local opt="-h"
    if [ "$action" = "reboot" ]; then opt="-r"; fi
    knot_log_info "Scheduling $action on $(knot_detect_hostname) with delay $time_spec..."
    sudo shutdown "$opt" "$time_spec" "$wall_msg"
    knot_log_ok "Scheduled: $action on $(knot_detect_hostname) at $time_spec."
  fi
}

shutdown_exec_remote() {
  local target="$1"
  local action="${2:-poweroff}"
  local delay_arg="${3:-now}"
  local wall_msg="${4:-Shutdown scheduled via Knot Swarm}"

  local manifest=""
  manifest="$(knot_get_manifest_path "$target" 2>/dev/null || true)"
  if [ -z "$manifest" ] || [ ! -f "$manifest" ]; then
    knot_log_err "Unknown node '$target'"
    return 1
  fi

  local host user port
  host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
  user="$(awk -F'"' '/"user":/ {print $4}' "$manifest")"
  port="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest")"
  if [ -z "$port" ]; then port="22"; fi

  local my_host
  my_host="$(knot_detect_hostname)"
  if [ "$host" = "$my_host" ]; then
    shutdown_exec_local "$action" "$delay_arg" "$wall_msg"
    return $?
  fi

  if [ "$action" = "show" ] || [ "$action" = "status" ]; then
    local remote_status
    if ! remote_status="$(ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$port" "$target" "shutdown --show 2>&1 || true")"; then
      remote_status="Unreachable"
    fi
    echo "[$target / $host] $remote_status"
    return 0
  fi

  knot_log_info "Dispatching graceful $action to '$target' ($host)..."
  ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$port" "$target" \
    "bash -l -c 'knot shutdown local --action \"$action\" --delay \"$delay_arg\" --msg $(printf '%q' "$wall_msg") --force'"
}

shutdown_exec_all() {
  local action="${1:-poweroff}"
  local delay_arg="${2:-now}"
  local wall_msg="${3:-Shutdown scheduled via Knot Swarm}"

  local my_host
  my_host="$(knot_detect_hostname)"

  local strands=()
  local anchor=""

  local anchor_id="desktop"
  local anchor_host=""
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    local SWARM_ID="" ANCHOR_ID="" ANCHOR_HOST=""
    if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
      # shellcheck disable=SC1090
      source "/etc/knot/swarms.d/${active_swarm}.conf"
      anchor_id="${ANCHOR_ID:-desktop}"
      anchor_host="${ANCHOR_HOST:-$anchor_id}"
    fi
  fi

  local nodes_dirs=()
  local primary_dir=""
  if primary_dir="$(knot_get_nodes_dir 2>/dev/null)" && [ -d "$primary_dir" ]; then
    nodes_dirs+=("$primary_dir")
  fi
  local user_home
  user_home="$(knot_detect_user_home)"
  for d in "$user_home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    if [[ ! " ${nodes_dirs[*]} " =~ " ${d} " ]]; then
      nodes_dirs+=("$d")
    fi
  done

  local seen_nodes=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local id host
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      [ -n "$id" ] || continue
      if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
      seen_nodes+=("$id")

      if [ "$id" = "$anchor_id" ] || [ -n "$anchor_host" ] && [ "$host" = "$anchor_host" ]; then
        anchor="$id"
      else
        strands+=("$id")
      fi
    done
  done

  if [ "$action" = "show" ] || [ "$action" = "status" ]; then
    echo -e "${C_BOLD}--- Knot Swarm Scheduled Shutdown Status ---${C_RESET}"
    for s in "${strands[@]}"; do
      shutdown_exec_remote "$s" "show"
    done
    if [ -n "$anchor" ]; then
      shutdown_exec_remote "$anchor" "show"
    fi
    return 0
  fi

  if [ "$action" = "cancel" ]; then
    knot_log_info "Cancelling scheduled shutdowns across the entire swarm..."
    for s in "${strands[@]}"; do
      shutdown_exec_remote "$s" "cancel" || knot_log_warn "Failed to cancel shutdown on $s"
    done
    if [ -n "$anchor" ]; then
      shutdown_exec_remote "$anchor" "cancel" || knot_log_warn "Failed to cancel shutdown on anchor"
    fi
    knot_log_ok "Swarm cancellation complete."
    return 0
  fi

  knot_log_info "Initiating swarm-wide $action (Strands first, Anchor last)..."

  # 1. Shut down / schedule strands first
  for s in "${strands[@]}"; do
    local s_manifest=""
    s_manifest="$(knot_get_manifest_path "$s" 2>/dev/null || true)"
    local s_host=""
    if [ -n "$s_manifest" ] && [ -f "$s_manifest" ]; then
      s_host="$(awk -F'"' '/"hostname":/ {print $4}' "$s_manifest")"
    fi
    if [ "$s_host" != "$my_host" ]; then
      shutdown_exec_remote "$s" "$action" "$delay_arg" "$wall_msg" || knot_log_warn "Failed to dispatch to $s"
    fi
  done

  # 2. If current node is a strand, shut down anchor, then local
  if [ -n "$anchor_host" ] && [ "$my_host" != "$anchor_host" ] && [ -n "$anchor" ]; then
    shutdown_exec_remote "$anchor" "$action" "$delay_arg" "$wall_msg" || knot_log_warn "Failed to dispatch to anchor"
    shutdown_exec_local "$action" "$delay_arg" "$wall_msg"
    return 0
  fi

  # 3. If current node is Anchor, shut down local Anchor last
  if [ -n "$anchor" ]; then
    shutdown_exec_local "$action" "$delay_arg" "$wall_msg"
  fi
}
