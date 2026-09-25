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

  if command -v knot_get_manifest_path >/dev/null; then
    local a_manifest=""
    if a_manifest="$(knot_get_manifest_path "desktop")" && [ -f "$a_manifest" ]; then
      local h
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$a_manifest")"
      if [ -n "$h" ] && [ "$my_host" = "$h" ]; then
        return 0
      fi
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

  # In root context: inspect swarm node manifests for local hostname
  local my_host
  my_host="$(knot_detect_hostname)"
  local nodes_dirs=()
  for d in /home/*/.config/knot/swarms/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    nodes_dirs+=("$d")
  done
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
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

autologin_detect_dm() {
  local dm_name="unknown"
  if [ -L /etc/systemd/system/display-manager.service ]; then
    dm_name="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
  elif command -v systemctl >/dev/null && systemctl is-enabled plasmalogin.service >/dev/null; then
    dm_name="plasmalogin"
  elif command -v systemctl >/dev/null && systemctl is-enabled sddm.service >/dev/null; then
    dm_name="sddm"
  fi
  echo "$dm_name"
}

autologin_ensure_dm() {
  if ! command -v systemctl >/dev/null; then
    knot_log_info "systemctl not available; skipping display manager configuration."
    return 0
  fi

  local current_dm
  current_dm="$(autologin_detect_dm)"
  if [ "$current_dm" = "plasmalogin" ]; then
    knot_log_ok "Display manager is already plasmalogin.service (enabled)."
    return 0
  fi

  # Check if plasmalogin unit file exists
  local pl_avail=0
  local unit_list=""
  if unit_list="$(systemctl list-unit-files plasmalogin.service 2>&1)"; then
    if echo "$unit_list" | grep -q "plasmalogin.service"; then
      pl_avail=1
    fi
  fi

  if [ $pl_avail -eq 1 ]; then
    local has_root=0
    if [ "$(id -u)" -eq 0 ]; then
      has_root=1
    elif command -v sudo >/dev/null && sudo -n true 2>&1; then
      has_root=1
    fi

    if [ $has_root -eq 1 ]; then
      knot_log_info "Migrating display manager to plasmalogin.service..."
      local sudo_cmd=()
      if [ "$(id -u)" -ne 0 ]; then
        sudo_cmd=(sudo -n)
      fi

      if [ "$current_dm" != "unknown" ]; then
        knot_log_info "Disabling current display manager: ${current_dm}.service"
        local dis_err=""
        if ! dis_err="$("${sudo_cmd[@]}" systemctl disable "${current_dm}.service" 2>&1)"; then
          knot_log_warn "Notice: Could not disable ${current_dm}.service: $dis_err"
        fi
      fi
      knot_log_info "Enabling plasmalogin.service..."
      local en_err=""
      if ! en_err="$("${sudo_cmd[@]}" systemctl enable plasmalogin.service 2>&1)"; then
        knot_log_err "Failed to enable plasmalogin.service: $en_err"
        return 1
      fi
      knot_log_ok "plasmalogin.service successfully enabled."
      return 0
    else
      knot_log_warn "Display manager is '$current_dm'. plasmalogin.service is available but root privileges are not non-interactively available."
      knot_log_info "Run 'knot autologin migrate-dm' with sudo privileges to switch display manager."
      return 0
    fi
  else
    knot_log_info "Display manager is '$current_dm' (plasmalogin.service not present on system)."
    return 0
  fi
}

autologin_status() {
  local my_host
  my_host="$(knot_detect_hostname)"
  echo -e "\033[1;36m=== Knot Auto-Login Status on $my_host ===\033[0m"

  local dm_name="unknown"
  if [ -L /etc/systemd/system/display-manager.service ]; then
    dm_name="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
  fi
  echo "  Display Manager: $dm_name"

  local user
  user="$(autologin_detect_user)"
  local sess=""
  sess="$(screen_get_local_session "$user")"
  if [ -n "$sess" ]; then
    local locked
    locked="$(loginctl show-session "$sess" -p LockedHint --value)"
    local stype
    stype="$(loginctl show-session "$sess" -p Type --value)"
    echo "  Session on seat0: Session $sess (user: $user, type: $stype, locked: $locked)"
  else
    echo "  Session on seat0: None (awaiting login for user: $user)"
  fi

  local a_state
  a_state="$(autologin_anchor_status)"
  echo "  Anchor Lock State: $a_state"
}

autologin_check() {
  local my_host
  my_host="$(knot_detect_hostname)"

  if autologin_is_anchor; then
    echo "IS_ANCHOR"
    return 0
  fi

  local user
  user="$(autologin_detect_user)"
  local sess=""
  sess="$(screen_get_local_session "$user")"
  if [ -n "$sess" ]; then
    local locked
    locked="$(loginctl show-session "$sess" -p LockedHint --value)"
    if [ "$locked" = "yes" ]; then
      echo "SESSION_LOCKED"
      return 0
    else
      echo "ALREADY_LOGGED_IN"
      return 0
    fi
  fi

  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -z "$active_swarm" ] || [ "$active_swarm" = "none" ]; then
    echo "OUTSIDE_FENCE"
    return 1
  fi

  local a_state
  a_state="$(autologin_anchor_status)"
  if [ "$a_state" = "LOCKED" ]; then
    echo "ANCHOR_LOCKED"
    return 1
  elif [ "$a_state" != "UNLOCKED" ]; then
    echo "ANCHOR_OFFLINE"
    return 2
  fi

  local dm_name="unknown"
  if [ -L /etc/systemd/system/display-manager.service ]; then
    dm_name="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
  fi
  if [ "$dm_name" != "plasmalogin" ]; then
    echo "DM_MIGRATION_RECOMMENDED"
    return 0
  fi

  echo "READY_FOR_AUTOLOGIN"
  return 0
}

autologin_doctor() {
  local my_host
  my_host="$(knot_detect_hostname)"
  echo -e "\033[1;36m=== Knot Ephemeral Auto-Login Diagnostics ($my_host) ===\033[0m"

  # 1. Host Role Check
  if autologin_is_anchor; then
    echo -e "  [i] Host Role: \033[36mAnchor Desktop\033[0m (Ephemeral Strand autologin applies to Strand nodes)"
  else
    echo -e "  [✓] Host Role: \033[32mStrand Node\033[0m"
  fi

  # 2. Display Manager Inspection
  local dm_name="unknown"
  if [ -L /etc/systemd/system/display-manager.service ]; then
    dm_name="$(basename "$(readlink -f /etc/systemd/system/display-manager.service)" .service)"
  fi
  echo -e "  [i] Active/Default Display Manager: \033[33m$dm_name\033[0m"

  if [ "$dm_name" = "plasmalogin" ]; then
    echo -e "  [✓] Display Manager Compatibility: \033[32mCompatible (plasma-login-manager active)\033[0m"
  else
    echo -e "  [!] Display Manager Notice: Currently using \033[33m$dm_name\033[0m."
    echo -e "      Knot ephemeral unattended first-login is built for \033[1mplasma-login-manager\033[0m."
    echo -e "      Recommendation: Run '\033[36mknot autologin migrate-dm\033[0m' if you wish to opt into plasma-login-manager."
  fi

  # 3. Active Session Check
  local user
  user="$(autologin_detect_user)"
  echo -e "  [i] Target Login User: \033[36m$user\033[0m"
  local sess=""
  sess="$(screen_get_local_session "$user")"
  if [ -n "$sess" ]; then
    local locked
    locked="$(loginctl show-session "$sess" -p LockedHint --value)"
    echo -e "  [✓] Active Session: \033[32mSession $sess detected (Locked: $locked)\033[0m"
  else
    echo -e "  [i] Active Session: None (at display manager login screen)"
  fi

  # 4. Swarm Network Fence Check
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    echo -e "  [✓] Network Fence: \033[32mActive swarm [$active_swarm] verified\033[0m"
  else
    echo -e "  [!] Network Fence: \033[33mNo active swarm hardware fence detected\033[0m"
  fi

  # 5. Anchor Reachability & Lock Status Check
  local a_state
  a_state="$(autologin_anchor_status)"
  if [ "$a_state" = "UNLOCKED" ]; then
    echo -e "  [✓] Anchor Status: \033[32mUNLOCKED (Strand autologin permitted)\033[0m"
  elif [ "$a_state" = "LOCKED" ]; then
    echo -e "  [!] Anchor Status: \033[33mLOCKED (Strand autologin gated until Anchor unlocks)\033[0m"
  else
    echo -e "  [✗] Anchor Status: \033[31mOFFLINE or Unreachable\033[0m"
  fi
}

autologin_migrate_dm() {
  local force=0
  if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
    force=1
  fi

  knot_log_info "Knot Display Manager Migration to plasma-login-manager"
  echo ""
  echo "This operation will:"
  echo "  1. Verify / install plasma-login-manager via pacman."
  echo "  2. Disable the currently active display manager (e.g. sddm.service)."
  echo "  3. Enable plasmalogin.service as display-manager.service."
  echo ""

  if [ $force -eq 0 ]; then
    read -r -p "Proceed with display manager migration? [y/N] " response
    case "$response" in
      [yY][eE][sS]|[yY]) ;;
      *)
        knot_log_info "Migration cancelled by operator."
        return 0
        ;;
    esac
  fi

  # 1. Install plasma-login-manager if missing
  if ! pacman -Q plasma-login-manager >/dev/null; then
    knot_log_info "Installing plasma-login-manager via pacman..."
    if ! sudo pacman -S --needed --noconfirm plasma-login-manager; then
      knot_log_err "Failed to install plasma-login-manager"
      return 1
    fi
    knot_log_ok "plasma-login-manager installed successfully."
  else
    knot_log_ok "plasma-login-manager is already installed."
  fi

  # 2. Check and disable SDDM if enabled
  if systemctl is-enabled sddm.service >/dev/null; then
    knot_log_info "Disabling sddm.service..."
    sudo systemctl disable sddm.service
  fi

  # 3. Enable plasmalogin
  knot_log_info "Enabling plasmalogin.service..."
  sudo systemctl enable plasmalogin.service
  knot_log_ok "Display manager successfully migrated to plasmalogin.service (effective on next start)."
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
    return 0
  fi

  if [ -z "$out" ]; then
    echo "OFFLINE"
    return 0
  fi

  local line
  line="$(echo "$out" | grep '|' | tail -n1)"
  if [ -z "$line" ]; then
    echo "OFFLINE"
    return 0
  fi

  local u sid seat stype locked
  IFS='|' read -r u sid seat stype locked <<< "$line"

  if [ "$locked" = "no" ]; then
    echo "UNLOCKED"
    return 0
  elif [ "$locked" = "yes" ]; then
    echo "LOCKED"
    return 0
  else
    echo "OFFLINE"
    return 0
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

  # Non-destructive check probe
  local probe=""
  if ! probe="$(autologin_check)"; then
    : # Probe returned non-zero, handled below
  fi

  case "$probe" in
    ALREADY_LOGGED_IN)
      knot_log_ok "User session is already active and unlocked on $my_host. No login required."
      return 0
      ;;
    SESSION_LOCKED)
      knot_log_info "Session is currently locked on $my_host. Unlocking display session..."
      screen_unlock_local
      return 0
      ;;
    OUTSIDE_FENCE)
      knot_log_warn "Refusing auto-login: Outside any verified swarm hardware network fence."
      return 1
      ;;
    ANCHOR_LOCKED)
      knot_log_warn "Refusing auto-login: Active swarm Anchor is locked."
      return 1
      ;;
    ANCHOR_OFFLINE)
      knot_log_warn "Refusing auto-login: Active swarm Anchor is offline or unreachable."
      return 1
      ;;
    DM_MIGRATION_RECOMMENDED)
      knot_log_warn "Display manager is not plasma-login-manager. Ephemeral auto-login requires plasmalogin.service."
      knot_log_info "Run 'knot autologin doctor' for diagnostic guidance, or 'knot autologin migrate-dm' to opt in."
      return 1
      ;;
    READY_FOR_AUTOLOGIN)
      ;;
    *)
      knot_log_warn "Auto-login check probe returned: $probe"
      ;;
  esac

  local user
  user="$(autologin_detect_user)"
  knot_log_info "Anchor is UP and UNLOCKED. Performing ephemeral first login for user '$user' on $my_host..."

  local conf_file="/etc/plasmalogin.conf"
  local had_existing=0
  local backup_content=""
  if [ -r "$conf_file" ]; then
    had_existing=1
    backup_content="$(cat "$conf_file")"
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
  local stype=""
  while [ $elapsed -lt 30 ]; do
    sleep 0.5
    elapsed=$((elapsed + 1))
    new_sess="$(screen_get_local_session "$user")"
    if [ -n "$new_sess" ]; then
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
  my_host="$(knot_detect_hostname)"
  local nodes_dirs=()
  local primary_dir=""
  if command -v knot_get_nodes_dir >/dev/null; then
    if primary_dir="$(knot_get_nodes_dir)" && [ -d "$primary_dir" ]; then
      nodes_dirs+=("$primary_dir")
    fi
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

      if [ "$id" = "desktop" ] || [ "$host" = "$my_host" ] || [ "$id" = "$my_host" ]; then
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
  done

  return 0
}

# Configure KWallet to use a blank password for unattended autologin without GUI popups
autologin_fix_kwallet() {
  local target="${1:-local}"
  local my_host
  my_host="$(knot_detect_hostname)"
  if [ "$target" != "local" ] && [ "$target" != "$my_host" ]; then
    knot_log_info "Dispatching KWallet configuration to '$target'..."
    "$KNOT_ROOT/bin/knot" exec "$target" "knot autologin fix-kwallet local"
    return $?
  fi

  knot_log_info "Opening KDE Wallet Password Manager on $my_host..."
  knot_log_info "To eliminate all login prompts under autologin:"
  knot_log_info "  1. In the opened dialog/KWalletManager, select 'Change Password...'"
  knot_log_info "  2. Enter your current password."
  knot_log_info "  3. Leave the New Password and Verify fields BLANK (empty)."
  knot_log_info "  4. Click OK and confirm 'Use empty password'."

  if command -v kwalletmanager5 >/dev/null; then
    systemd-run --user kwalletmanager5
  elif command -v kwalletmanager >/dev/null; then
    systemd-run --user kwalletmanager
  elif command -v qdbus6 >/dev/null; then
    systemd-run --user qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.changePassword kdewallet 0 "Knot"
  elif command -v qdbus >/dev/null; then
    systemd-run --user qdbus org.kde.kwalletd5 /modules/kwalletd5 org.kde.KWallet.changePassword kdewallet 0 "Knot"
  fi

  knot_log_ok "KWallet dialog launched on active desktop display."
}
