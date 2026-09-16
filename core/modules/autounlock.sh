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

  # 1. Ensure /usr/local/bin/knot-autounlock points to bin/knot-autounlock
  local bin_src="$KNOT_ROOT/bin/knot-autounlock"
  local bin_dst="/usr/local/bin/knot-autounlock"
  if [ ! -L "$bin_dst" ] || [ "$(readlink -f "$bin_dst")" != "$(readlink -f "$bin_src")" ]; then
    knot_log_info "Installing $bin_dst symlink..."
    sudo ln -sf "$bin_src" "$bin_dst"
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
ExecStart=/usr/local/bin/knot-autounlock
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
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity
  elif command -v qdbus >/dev/null; then
    qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity
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

    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      local id
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      local out=""
      local my_id="desktop"
      if [ -f "$KNOT_ROOT/registry/nodes/desktop.json" ] && grep -q "$(knot_detect_hostname)" "$KNOT_ROOT/registry/nodes/desktop.json"; then
        my_id="desktop"
      fi

      if [ "$id" = "$my_id" ]; then
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
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      local id
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      local my_id="desktop"
      if [ -f "$KNOT_ROOT/registry/nodes/desktop.json" ] && grep -q "$(knot_detect_hostname)" "$KNOT_ROOT/registry/nodes/desktop.json"; then
        my_id="desktop"
      fi

      if [ "$id" = "$my_id" ]; then
        screen_unlock_local
      else
        knot_log_info "Unlocking display on $id..."
        "$KNOT_ROOT/bin/knot" exec "$id" "knot screen unlock local"
      fi
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
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      local id
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      local my_id="desktop"
      if [ -f "$KNOT_ROOT/registry/nodes/desktop.json" ] && grep -q "$(knot_detect_hostname)" "$KNOT_ROOT/registry/nodes/desktop.json"; then
        my_id="desktop"
      fi

      if [ "$id" = "$my_id" ]; then
        screen_lock_local
      else
        knot_log_info "Locking display on $id..."
        "$KNOT_ROOT/bin/knot" exec "$id" "knot screen lock local"
      fi
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
