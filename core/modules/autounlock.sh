#!/usr/bin/env bash
set -euo pipefail

# Knot Screen State & Authoritative KVM Auto-Unlock Module

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

autounlock_configure() {
  local home
  home="$(knot_detect_user_home)"
  local my_host
  my_host="$(knot_detect_hostname)"

  # 1. Ensure ~/.local/bin/knot-autounlock points to bin/knot-autounlock
  local bin_src="$KNOT_ROOT/bin/knot-autounlock"
  local user_bin="$home/.local/bin"
  mkdir -p "$user_bin"
  ln -sf "$bin_src" "$user_bin/knot-autounlock"
  if command -v sudo >/dev/null && sudo -n true 2>&1; then
    local ln_err=""
    if ! ln_err="$(sudo ln -sf "$bin_src" "/usr/local/bin/knot-autounlock" 2>&1)"; then
      knot_log_warn "Notice: Failed to symlink knot-autounlock to /usr/local/bin: $ln_err"
    fi
  fi

  # 2. Deploy systemd user service
  local systemd_dir="$home/.config/systemd/user"
  mkdir -p "$systemd_dir"

  knot_log_info "Deploying Knot KVM Auto-Unlock service on $my_host..."
  cat << SERVICE_EOF > "$systemd_dir/knot-autounlock.service"
[Unit]
Description=Knot KVM Authoritative Auto-Unlock Daemon
PartOf=graphical-session.target
After=graphical-session.target knot-deskflow.service
Requisite=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/knot-autounlock
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
SERVICE_EOF

  systemctl --user daemon-reload
  systemctl --user enable knot-autounlock.service
  systemctl --user restart knot-autounlock.service
  knot_log_ok "Knot auto-unlock service deployed and active on $my_host."
}

screen_get_local_session() {
  local target_user="${1:-}"
  if [ -z "$target_user" ]; then
    target_user="$(knot_detect_user)"
  fi
  if [ "$target_user" = "root" ]; then
    if command -v autologin_detect_user >/dev/null; then
      target_user="$(autologin_detect_user)"
    fi
  fi

  local sess=""

  if command -v loginctl >/dev/null; then
    if loginctl list-users --no-legend | grep -q "[[:space:]]${target_user}$"; then
      sess="$(loginctl show-user "$target_user" -p Display --value)"
      if [ -n "$sess" ]; then
        echo "$sess"
        return 0
      fi
    fi

    # Fallback to scanning seat0 sessions for this user
    local sid uid suser seat rest
    while read -r sid uid suser seat rest; do
      if [[ "$seat" =~ ^seat ]]; then
        if [ "$suser" = "$target_user" ] || [ "$target_user" = "root" ]; then
          local stype
          stype="$(loginctl show-session "$sid" -p Type --value)"
          if [ "$stype" = "wayland" ] || [ "$stype" = "x11" ]; then
            echo "$sid"
            return 0
          fi
        fi
      fi
    done < <(loginctl list-sessions --no-legend)
  fi

  echo ""
}

screen_unlock_local() {
  local user
  user="$(knot_detect_user)"
  local sess
  sess="$(screen_get_local_session)"

  if [ -z "$sess" ]; then
    # If no graphical session on a Strand, attempt Anchor-gated autologin
    if [ -f "$KNOT_ROOT/core/modules/autologin.sh" ]; then
      source "$KNOT_ROOT/core/modules/autologin.sh"
      if ! autologin_is_anchor; then
        knot_log_info "No active graphical session on Strand. Attempting ephemeral first login..."
        autologin_execute_local
        return $?
      fi
    fi
    knot_log_err "No active graphical session found for user '$user'"
    return 1
  fi

  local locked
  locked="$(loginctl show-session "$sess" -p LockedHint --value)"
  if [ "$locked" = "yes" ]; then
    if loginctl unlock-session "$sess"; then
      knot_log_ok "Unlocked session $sess for user $user"
    else
      knot_log_err "Failed to unlock session $sess"
      return 1
    fi
  else
    knot_log_info "Session $sess is already unlocked"
  fi

  # Simulate activity to wake monitor / reset idle timer
  if command -v qdbus6 >/dev/null; then
    local qd_err="" qd_rc=0
    qd_err="$(qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity 2>&1)" || qd_rc=$?
    if [ $qd_rc -ne 0 ]; then
      knot_log_warn "Notice: SimulateUserActivity exited with code $qd_rc: $qd_err"
    fi
  elif command -v qdbus >/dev/null; then
    local qd_err="" qd_rc=0
    qd_err="$(qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity 2>&1)" || qd_rc=$?
    if [ $qd_rc -ne 0 ]; then
      knot_log_warn "Notice: SimulateUserActivity exited with code $qd_rc: $qd_err"
    fi
  fi
}

screen_lock_local() {
  local user
  user="$(knot_detect_user)"
  local sess
  sess="$(screen_get_local_session)"

  if [ -z "$sess" ]; then
    knot_log_err "No active graphical session found for user '$user'"
    return 1
  fi

  if loginctl lock-session "$sess"; then
    knot_log_ok "Locked session $sess for user $user"
  else
    knot_log_err "Failed to lock session $sess"
    return 1
  fi
}

screen_status_raw() {
  local user
  user="$(knot_detect_user)"
  local sess
  sess="$(screen_get_local_session)"

  if [ -z "$sess" ]; then
    echo "NO_SESSION"
    return 0
  fi

  local locked
  locked="$(loginctl show-session "$sess" -p LockedHint --value)"
  local seat
  seat="$(loginctl show-session "$sess" -p Seat --value)"
  local type
  type="$(loginctl show-session "$sess" -p Type --value)"

  echo "$user|$sess|${seat:-none}|${type:-unknown}|$locked"
}

screen_status() {
  local target="${1:-local}"

  if [ "$target" = "--all" ]; then
    echo -e "${C_BOLD}--- Knot Screen & Lock Status ---${C_RESET}"
    printf "%-12s %-10s %-8s %-8s %-10s %-12s\n" "NODE" "USER" "SESSION" "SEAT" "TYPE" "LOCK STATE"
    printf "%-12s %-10s %-8s %-8s %-10s %-12s\n" "----" "----" "-------" "----" "----" "----------"

    local my_host
    my_host="$(knot_detect_hostname)"
    local nodes_dirs=()
    local primary_dir=""
    if primary_dir="$(knot_get_nodes_dir)" && [ -d "$primary_dir" ]; then
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
        local id h
        id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        [ -n "$id" ] || continue
        if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
        seen_nodes+=("$id")

        local out=""
        if [ "$id" = "$my_host" ] || [ "$h" = "$my_host" ]; then
          out="$(screen_status_raw)"
        else
          if ! out="$("$KNOT_ROOT/bin/knot" exec "$id" "knot screen status-raw")"; then
            out=""
          fi
        fi

        if [ -z "$out" ]; then
          printf "%-12s %-10s %-8s %-8s %-10s ${C_RED}%-12s${C_RESET}\n" "$id" "-" "-" "-" "-" "UNREACHABLE"
        elif [ "$out" = "NO_SESSION" ]; then
          printf "%-12s %-10s %-8s %-8s %-10s ${C_RED}%-12s${C_RESET}\n" "$id" "-" "-" "-" "-" "NO SESSION"
        else
          local u sid seat stype locked
          IFS='|' read -r u sid seat stype locked <<< "$out"
          if [ "$locked" = "yes" ]; then
            printf "%-12s %-10s %-8s %-8s %-10s ${C_YELLOW}%-12s${C_RESET}\n" "$id" "$u" "$sid" "$seat" "$stype" "LOCKED"
          else
            printf "%-12s %-10s %-8s %-8s %-10s ${C_GREEN}%-12s${C_RESET}\n" "$id" "$u" "$sid" "$seat" "$stype" "UNLOCKED"
          fi
        fi
      done
    done
  elif [ "$target" = "local" ]; then
    local out
    out="$(screen_status_raw)"
    if [ "$out" = "NO_SESSION" ]; then
      knot_log_warn "No active graphical session found."
    else
      local u sid seat stype locked
      IFS='|' read -r u sid seat stype locked <<< "$out"
      if [ "$locked" = "yes" ]; then
        knot_log_warn "Display session $sid ($stype on $seat, user: $u) is LOCKED"
      else
        knot_log_ok "Display session $sid ($stype on $seat, user: $u) is UNLOCKED"
      fi
    fi
  elif [ "$target" = "status-raw" ]; then
    screen_status_raw
  else
    "$KNOT_ROOT/bin/knot" exec "$target" "knot screen status local"
  fi
}

screen_unlock() {
  local target="${1:-local}"
  if [ "$target" = "--all" ]; then
    local my_host
    my_host="$(knot_detect_hostname)"
    local nodes_dirs=()
    local primary_dir=""
    if primary_dir="$(knot_get_nodes_dir)" && [ -d "$primary_dir" ]; then
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
        local id h
        id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        [ -n "$id" ] || continue
        if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
        seen_nodes+=("$id")

        if [ "$id" = "$my_host" ] || [ "$h" = "$my_host" ]; then
          screen_unlock_local
        else
          knot_log_info "Unlocking display on $id..."
          "$KNOT_ROOT/bin/knot" exec "$id" "knot screen unlock local"
        fi
      done
    done
  elif [ "$target" = "local" ]; then
    screen_unlock_local
  else
    "$KNOT_ROOT/bin/knot" exec "$target" "knot screen unlock local"
  fi
}

screen_lock() {
  local target="${1:-local}"
  if [ "$target" = "--all" ]; then
    local my_host
    my_host="$(knot_detect_hostname)"
    local nodes_dirs=()
    local primary_dir=""
    if primary_dir="$(knot_get_nodes_dir)" && [ -d "$primary_dir" ]; then
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
        local id h
        id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        [ -n "$id" ] || continue
        if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
        seen_nodes+=("$id")

        if [ "$id" = "$my_host" ] || [ "$h" = "$my_host" ]; then
          screen_lock_local
        else
          knot_log_info "Locking display on $id..."
          "$KNOT_ROOT/bin/knot" exec "$id" "knot screen lock local"
        fi
      done
    done
  elif [ "$target" = "local" ]; then
    screen_lock_local
  else
    "$KNOT_ROOT/bin/knot" exec "$target" "knot screen lock local"
  fi
}

screen_login() {
  local target="${1:-local}"
  source "$KNOT_ROOT/core/modules/autologin.sh"

  if [ "$target" = "--all" ]; then
    autologin_reconcile_all
  elif [ "$target" = "local" ]; then
    autologin_execute_local
  else
    autologin_trigger_remote "$target"
  fi
}
