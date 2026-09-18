#!/usr/bin/env bash
set -euo pipefail

# Knot Ephemeral Auto-Login & Display Manager Orchestration Module
# Removes first login friction on Strands when Anchor is online & unlocked.

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/autounlock.sh"

autologin_is_anchor() {
  local my_host
  my_host="$(knot_detect_hostname)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    local SWARM_ID="" ANCHOR_ID="" ANCHOR_HOST=""
    if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
      # shellcheck disable=SC1090
      source "/etc/knot/swarms.d/${active_swarm}.conf"
      if [ "$my_host" = "${ANCHOR_HOST:-}" ] || [ "$my_host" = "${ANCHOR_ID:-}" ]; then
        return 0
      fi
    fi
  fi

  if [ -f "$KNOT_ROOT/registry/nodes/desktop.json" ]; then
    local h
    h="$(awk -F'"' '/"hostname":/ {print $4}' "$KNOT_ROOT/registry/nodes/desktop.json")"
    if [ -n "$h" ] && [ "$my_host" = "$h" ]; then
      return 0
    fi
  fi
  return 1
}

autologin_detect_user() {
  local u
  u="$(knot_detect_user)"
  if [ "$u" != "root" ]; then
    echo "$u"
    return 0
  fi

  # In root context: inspect registry node for local hostname
  local my_host
  my_host="$(hostname)"
  for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
    [ -e "$manifest" ] || continue
    local host
    host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
    if [ "$host" = "$my_host" ]; then
      local reg_user
      reg_user="$(awk -F'"' '/"user":/ {print $4}' "$manifest")"
      if [ -n "$reg_user" ]; then
        echo "$reg_user"
        return 0
      fi
    fi
  done

  # Fallback to first non-system user with home directory
  local candidate
  candidate="$(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd | head -n1)"
  if [ -n "$candidate" ]; then
    echo "$candidate"
    return 0
  fi

  echo "root"
}

autologin_ensure_dm() {
  knot_log_info "Verifying display manager on $(hostname)..."

  # 1. Install plasma-login-manager if missing
  if ! pacman -Q plasma-login-manager >/dev/null 2>&1; then
    knot_log_info "Installing plasma-login-manager via pacman..."
    if ! sudo pacman -S --needed --noconfirm plasma-login-manager; then
      knot_log_err "Failed to install plasma-login-manager"
      return 1
    fi
    knot_log_ok "plasma-login-manager installed successfully."
  fi

  # 2. Check if SDDM is enabled
  local sddm_enabled=0
  if systemctl is-enabled sddm.service >/dev/null 2>&1; then
    sddm_enabled=1
  fi

  # 3. Disable SDDM and switch to plasmalogin if needed
  if [ $sddm_enabled -eq 1 ]; then
    knot_log_info "Migrating display manager from SDDM to plasma-login-manager..."
    sudo systemctl disable sddm.service
    sudo systemctl enable plasmalogin.service
    knot_log_ok "Display manager migrated to plasmalogin.service (effective on next start)."
  elif ! systemctl is-enabled plasmalogin.service >/dev/null 2>&1; then
    knot_log_info "Enabling plasmalogin.service as display-manager.service..."
    sudo systemctl enable plasmalogin.service
    knot_log_ok "plasmalogin.service enabled."
  else
    knot_log_ok "plasma-login-manager is already enabled and active."
  fi

  return 0
}

autologin_anchor_status() {
  local anchor_host="desktop"
  local target_user
  target_user="$(autologin_detect_user)"

  # Run SSH as non-root user to utilize user's SSH key
  local out=""
  local ssh_cmd=()
  if [ "$(whoami)" = "root" ] && [ "$target_user" != "root" ]; then
    ssh_cmd=(sudo -u "$target_user" ssh -o BatchMode=yes -o ConnectTimeout=2 "$anchor_host" "knot screen status-raw")
  else
    ssh_cmd=(ssh -o BatchMode=yes -o ConnectTimeout=2 "$anchor_host" "knot screen status-raw")
  fi

  if ! out="$("${ssh_cmd[@]}")"; then
    echo "OFFLINE"
    return 2
  fi

  if [ -z "$out" ]; then
    echo "OFFLINE"
    return 2
  fi

  local line
  line="$(echo "$out" | grep '|' | tail -n1)"
  if [ -z "$line" ]; then
    echo "OFFLINE"
    return 2
  fi

  local u sid seat stype locked
  IFS='|' read -r u sid seat stype locked <<< "$line"

  if [ "$locked" = "no" ]; then
    echo "UNLOCKED"
    return 0
  elif [ "$locked" = "yes" ]; then
    echo "LOCKED"
    return 1
  else
    echo "OFFLINE"
    return 2
  fi
}

autologin_execute_local() {
  # Recursion circuit-breaker
  if [ "${_KNOT_AUTOLOGIN_RUNNING:-0}" -eq 1 ]; then
    return 0
  fi
  export _KNOT_AUTOLOGIN_RUNNING=1

  local my_host
  my_host="$(knot_detect_hostname)"

  if autologin_is_anchor; then
    knot_log_warn "Current node ($my_host) is the Anchor desktop host; auto-login orchestration applies to Strands."
    return 0
  fi

  # 1. Verify Active Swarm Network Fence
  local active_swarm=""
  if [ "${_KNOT_GUARD_RUNNING:-0}" -eq 0 ] && [ -x /usr/local/bin/knot-guard ]; then
    # Verify knot-guard actually supports --check-active to prevent recursion with legacy guard scripts
    if grep -q "check-active" /usr/local/bin/knot-guard 2>/dev/null; then
      local probed=""
      if probed="$(/usr/local/bin/knot-guard --check-active 2>/dev/null)"; then
        if [ -n "$probed" ] && [ "$probed" != "none" ]; then
          active_swarm="$probed"
        fi
      fi
    fi
  fi
  if [ -z "$active_swarm" ]; then
    active_swarm="$(knot_get_active_swarm)"
  fi

  if [ -z "$active_swarm" ] || [ "$active_swarm" = "none" ]; then
    knot_log_warn "Refusing auto-login: Outside any verified swarm hardware network fence."
    return 1
  fi

  # 2. Check Anchor Status of Active Swarm
  local anchor_state
  anchor_state="$(autologin_anchor_status)"
  if [ "$anchor_state" != "UNLOCKED" ]; then
    knot_log_warn "Refusing auto-login: Active swarm [$active_swarm] Anchor is not unlocked (state: $anchor_state)."
    return 1
  fi

  # 3. Detect user and check existing graphical session
  local user
  user="$(autologin_detect_user)"

  local sess
  sess="$(screen_get_local_session "$user")"
  if [ -n "$sess" ]; then
    local locked
    locked="$(loginctl show-session "$sess" -p LockedHint --value)"
    if [ "$locked" = "yes" ]; then
      knot_log_info "Session $sess is currently locked. Unlocking display session..."
      screen_unlock_local
      return 0
    else
      knot_log_ok "Session $sess is already active and unlocked. No login required."
      return 0
    fi
  fi

  # 4. Ephemeral Autologin Execution via plasmalogin
  knot_log_info "Anchor is UP and UNLOCKED. Performing ephemeral first login for user '$user' on $my_host..."

  local conf_file="/etc/plasmalogin.conf"
  local had_existing=0
  local backup_content=""
  if [ -r "$conf_file" ]; then
    had_existing=1
    backup_content="$(< "$conf_file")"
  fi

  cleanup_autologin() {
    if [ "${had_existing:-0}" -eq 1 ]; then
      echo "${backup_content:-}" | sudo tee "$conf_file" >/dev/null
    else
      sudo rm -f "$conf_file"
    fi
  }
  trap cleanup_autologin EXIT INT TERM

  # Write ephemeral autologin configuration
  cat << CONF_EOF | sudo tee "$conf_file" >/dev/null
[Autologin]
User=$user
Session=plasma
CONF_EOF

  # Clear any rate-limit burst before restarting
  sudo systemctl reset-failed display-manager.service plasmalogin.service

  # Trigger display manager restart
  knot_log_info "Restarting display-manager.service for ephemeral session handoff..."
  sudo systemctl restart display-manager.service

  # Await active session on seat0 (up to 15s)
  local elapsed=0
  local new_sess=""
  while [ $elapsed -lt 30 ]; do
    sleep 0.5
    elapsed=$((elapsed + 1))
    new_sess="$(screen_get_local_session "$user")"
    if [ -n "$new_sess" ]; then
      local stype
      stype="$(loginctl show-session "$new_sess" -p Type --value)"
      if [ "$stype" = "wayland" ] || [ "$stype" = "x11" ]; then
        break
      fi
    fi
  done

  # Always purge ephemeral configuration immediately
  cleanup_autologin
  trap - EXIT INT TERM

  if [ -z "$new_sess" ]; then
    knot_log_err "Timed out waiting for graphical session for user '$user' on $my_host."
    return 1
  fi

  knot_log_ok "First login complete! Active session $new_sess ($stype) established for '$user' on $my_host."
  return 0
}

autologin_trigger_remote() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: autologin_trigger_remote <strand-id>"
    return 1
  fi

  knot_log_info "Triggering auto-login on Strand '$target'..."
  if ! "$KNOT_ROOT/bin/knot" exec "$target" "sudo knot autologin local"; then
    knot_log_warn "Failed to execute auto-login on $target"
    return 1
  fi
  return 0
}

autologin_reconcile_all() {
  if ! autologin_is_anchor; then
    knot_log_warn "Mesh auto-login reconciliation must be coordinated from the Anchor desktop."
    return 1
  fi

  # Check Anchor's own lock state
  local anchor_out
  anchor_out="$(screen_status_raw)"
  if [ -z "$anchor_out" ] || [ "$anchor_out" = "NO_SESSION" ]; then
    knot_log_warn "Anchor desktop has no active graphical session; cannot reconcile strands."
    return 1
  fi

  local u sid seat stype locked
  IFS='|' read -r u sid seat stype locked <<< "$anchor_out"
  if [ "$locked" = "yes" ]; then
    knot_log_info "Anchor desktop is locked; strands will remain at login screen."
    return 0
  fi

  knot_log_info "Anchor is UNLOCKED. Scanning strands for pending first logins..."
  local my_host
  my_host="$(hostname)"

  for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
    [ -e "$manifest" ] || continue
    local id host
    id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
    host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"

    if [ "$id" = "desktop" ] || [ "$host" = "$my_host" ]; then
      continue
    fi

    local strand_status=""
    if strand_status="$("$KNOT_ROOT/bin/knot" exec "$id" "knot screen status-raw")"; then
      local strand_line
      strand_line="$(echo "$strand_status" | grep -E 'NO_SESSION|\|' | tail -n1)"
      if [ "$strand_line" = "NO_SESSION" ]; then
        knot_log_info "Strand '$id' ($host) is waiting at login screen. Initiating auto-login..."
        autologin_trigger_remote "$id"
      else
        knot_log_info "Strand '$id' ($host) already has an active session ($strand_line)."
      fi
    else
      knot_log_warn "Strand '$id' ($host) is unreachable."
    fi
  done

  return 0
}

# Configure KWallet to use a blank password for unattended autologin without GUI popups
autologin_fix_kwallet() {
  local target="${1:-local}"
  if [ "$target" != "local" ] && [ "$target" != "$(hostname)" ]; then
    knot_log_info "Dispatching KWallet configuration to '$target'..."
    "$KNOT_ROOT/bin/knot" exec "$target" "knot autologin fix-kwallet local"
    return $?
  fi

  knot_log_info "Opening KDE Wallet Password Manager on $(hostname)..."
  knot_log_info "To eliminate all login prompts under autologin:"
  knot_log_info "  1. In the opened dialog/KWalletManager, select 'Change Password...'"
  knot_log_info "  2. Enter your current password."
  knot_log_info "  3. Leave the New Password and Verify fields BLANK (empty)."
  knot_log_info "  4. Click OK and confirm 'Use empty password'."

  if command -v kwalletmanager5 >/dev/null 2>&1; then
    systemd-run --user kwalletmanager5 >/dev/null 2>&1 || kwalletmanager5 &
  elif command -v kwalletmanager >/dev/null 2>&1; then
    systemd-run --user kwalletmanager >/dev/null 2>&1 || kwalletmanager &
  elif command -v qdbus6 >/dev/null 2>&1; then
    systemd-run --user qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.changePassword kdewallet 0 "Knot" >/dev/null 2>&1 || true
  elif command -v qdbus >/dev/null 2>&1; then
    systemd-run --user qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.changePassword kdewallet 0 "Knot" >/dev/null 2>&1 || true
  fi

  knot_log_ok "KWallet dialog launched on active desktop display."
}
