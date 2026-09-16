#!/usr/bin/env bash
set -euo pipefail

# Knot Doctor & Mesh Repair Module
# Diagnostic engine and self-healing automation for network, KVM, portals, and screen state

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"
if [ -f "$KNOT_ROOT/core/modules/antigravity.sh" ]; then
  source "$KNOT_ROOT/core/modules/antigravity.sh"
fi

# Format helpers
doc_ok()   { echo -e "  ${C_GREEN}[✓] PASS${C_RESET} $*"; }
doc_warn() { echo -e "  ${C_YELLOW}[!] WARN${C_RESET} $*"; }
doc_fail() { echo -e "  ${C_RED}[✗] FAIL${C_RESET} $*"; }
doc_info() { echo -e "  ${C_CYAN}[i] INFO${C_RESET} $*"; }

# ------------------------------------------------------------------------------
# Diagnostic Check: Local Node
# ------------------------------------------------------------------------------
doctor_check_local() {
  local my_host
  my_host="$(knot_detect_hostname)"
  local my_user
  my_user="$(knot_detect_user)"
  local is_anchor=0

  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local anchor_id="desktop"
  local anchor_host="desktop"
  if knot_load_swarm_profile "$active_swarm"; then
    anchor_id="${ANCHOR_ID:-desktop}"
    anchor_host="${ANCHOR_HOST:-desktop}"
  fi

  if [ "$my_host" = "$anchor_host" ] || [ "$my_host" = "$anchor_id" ]; then
    is_anchor=1
  else
    local nodes_dir
    if nodes_dir="$(knot_get_nodes_dir)"; then
      if [ -r "$nodes_dir/${anchor_id}.json" ]; then
        local m_host
        m_host="$(awk -F'"' '/"hostname":/ {print $4}' "$nodes_dir/${anchor_id}.json")"
        if [ "$m_host" = "$my_host" ] || grep -q "\"$my_host\"" "$nodes_dir/${anchor_id}.json"; then
          is_anchor=1
        fi
      fi
    fi
  fi

  echo -e "\n${C_BOLD}=== Diagnostics for Node: $my_host ($([ $is_anchor -eq 1 ] && echo "Anchor/Server" || echo "Strand/Client")) ===${C_RESET}"

  local failures=0
  local warnings=0

  # 1. Wayland & Display Environment
  echo -e "\n${C_BOLD}[Display & Compositor]${C_RESET}"
  local wayland_disp="${WAYLAND_DISPLAY:-}"
  local xdg_desktop="${XDG_CURRENT_DESKTOP:-}"

  # If running in non-graphical ssh, inspect user systemd environment
  if [ -z "$wayland_disp" ] && command -v systemctl >/dev/null; then
    local env_out=""
    if env_out="$(systemctl --user show-environment 2>&1)"; then
      wayland_disp="$(echo "$env_out" | awk -F= '/^WAYLAND_DISPLAY=/ {print $2}')"
      if [ -z "$xdg_desktop" ]; then
        xdg_desktop="$(echo "$env_out" | awk -F= '/^XDG_CURRENT_DESKTOP=/ {print $2}')"
      fi
    fi
  fi

  if [ -n "$wayland_disp" ]; then
    doc_ok "Wayland display socket detected: $wayland_disp"
  else
    doc_warn "WAYLAND_DISPLAY not set in user environment"
    warnings=$((warnings + 1))
  fi

  if [ -n "$xdg_desktop" ]; then
    doc_ok "Desktop environment detected: $xdg_desktop"
  else
    doc_warn "XDG_CURRENT_DESKTOP not set in user environment"
    warnings=$((warnings + 1))
  fi

  # 2. XDG Desktop Portals & RemoteDesktop Interface
  echo -e "\n${C_BOLD}[Desktop Portals & EI Integration]${C_RESET}"
  local portal_active=0
  if systemctl --user is-active --quiet xdg-desktop-portal.service 2>/dev/null; then
    doc_ok "xdg-desktop-portal.service is active"
    portal_active=1
  else
    doc_fail "xdg-desktop-portal.service is not active"
    failures=$((failures + 1))
  fi

  local kde_portal_installed=0
  if command -v pacman >/dev/null; then
    if pacman -Qs xdg-desktop-portal-kde >/dev/null 2>&1; then
      kde_portal_installed=1
    fi
  elif dpkg -l xdg-desktop-portal-kde >/dev/null 2>&1; then
    kde_portal_installed=1
  elif [ -f /usr/lib/xdg-desktop-portal-kde ] || [ -f /usr/libexec/xdg-desktop-portal-kde ]; then
    kde_portal_installed=1
  fi

  if [ $kde_portal_installed -eq 1 ]; then
    if systemctl --user is-active --quiet plasma-xdg-desktop-portal-kde.service 2>/dev/null; then
      doc_ok "plasma-xdg-desktop-portal-kde.service is active"
    else
      doc_fail "plasma-xdg-desktop-portal-kde.service is INACTIVE (KVM client will fail without RemoteDesktop interface)"
      failures=$((failures + 1))
    fi

    local wants_link="$HOME/.config/systemd/user/graphical-session.target.wants/plasma-xdg-desktop-portal-kde.service"
    if [ -L "$wants_link" ]; then
      doc_ok "plasma-xdg-desktop-portal-kde is linked to graphical-session.target"
    else
      doc_warn "plasma-xdg-desktop-portal-kde is NOT linked in graphical-session.target.wants/ (may not start on boot)"
      warnings=$((warnings + 1))
    fi
  fi

  # Test D-Bus interface availability
  if command -v gdbus >/dev/null; then
    if gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q 'interface org.freedesktop.portal.RemoteDesktop'; then
      doc_ok "D-Bus portal exports 'org.freedesktop.portal.RemoteDesktop'"
    else
      doc_fail "D-Bus portal DOES NOT export 'org.freedesktop.portal.RemoteDesktop' (Deskflow cannot inject input!)"
      failures=$((failures + 1))
    fi

    if gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q 'interface org.freedesktop.portal.InputCapture'; then
      doc_ok "D-Bus portal exports 'org.freedesktop.portal.InputCapture'"
    else
      if [ $is_anchor -eq 1 ]; then
        doc_warn "D-Bus portal does not export 'org.freedesktop.portal.InputCapture' (Anchor uses persistence shim fallback)"
        warnings=$((warnings + 1))
      fi
    fi
  fi

  # Flatpak permissions
  if command -v flatpak >/dev/null; then
    if flatpak permissions 2>/dev/null | grep -qE "kde-authorized[[:space:]]+remote-desktop"; then
      doc_ok "Flatpak kde-authorized remote-desktop permission is granted"
    else
      doc_warn "Flatpak kde-authorized remote-desktop permission not set"
      warnings=$((warnings + 1))
    fi
  fi

  # 3. KVM (Deskflow) Service & Socket State
  echo -e "\n${C_BOLD}[Deskflow KVM Service & Sockets]${C_RESET}"
  local deskflow_state="unknown" deskflow_sub="unknown" deskflow_restarts="0"
  local show_out=""
  if show_out="$(systemctl --user show knot-deskflow 2>&1)"; then
    deskflow_state="$(echo "$show_out" | awk -F= '/^ActiveState=/ {print $2}')"
    deskflow_sub="$(echo "$show_out" | awk -F= '/^SubState=/ {print $2}')"
    deskflow_restarts="$(echo "$show_out" | awk -F= '/^NRestarts=/ {print $2}')"
  fi

  if [ "$deskflow_state" = "active" ] && [ "$deskflow_sub" = "running" ]; then
    doc_ok "knot-deskflow.service is running ($deskflow_sub)"
  elif [ "$deskflow_sub" = "auto-restart" ]; then
    doc_fail "knot-deskflow.service is in CRASH LOOP (restarts: $deskflow_restarts, state: $deskflow_sub)"
    failures=$((failures + 1))
  else
    doc_fail "knot-deskflow.service is not healthy: state=$deskflow_state, sub=$deskflow_sub (restarts: $deskflow_restarts)"
    failures=$((failures + 1))
  fi

  if [ $is_anchor -eq 1 ]; then
    # Anchor: check if listening on 24800 and list established clients
    local ss_tl_out=""
    if ss_tl_out="$(ss -H -tl sport = :24800 2>&1)" && echo "$ss_tl_out" | grep -q 24800; then
      doc_ok "Deskflow server is listening on TCP port 24800"
    else
      doc_fail "Deskflow server is NOT listening on port 24800"
      failures=$((failures + 1))
    fi

    local connected_clients=""
    local ss_tn_out=""
    if ss_tn_out="$(ss -H -tn state established sport = :24800 2>&1)"; then
      connected_clients="$(echo "$ss_tn_out" | awk '{print $4}' | cut -d: -f1)"
    fi
    local client_count=0
    if [ -n "$connected_clients" ]; then
      client_count="$(echo "$connected_clients" | grep -v '^$' | wc -l)"
    fi
    doc_ok "Active connected KVM strands: $client_count"
    for ip in $connected_clients; do
      [ -n "$ip" ] && doc_info "  -> Established connection with client at $ip"
    done
  else
    # Strand: check if connected to anchor:24800
    local conn_out=""
    if ! conn_out="$(ss -H -tn state established dport = :24800 2>&1)"; then
      conn_out=""
    fi
    if [ -n "$conn_out" ]; then
      local server_ip
      server_ip="$(echo "$conn_out" | awk '{print $4}' | head -n1)"
      doc_ok "Established KVM connection to server at $server_ip"
    else
      doc_fail "NO established KVM connection to server on port 24800 (disconnected from KVM mesh)"
      failures=$((failures + 1))
    fi
  fi

  # 4. Deskflow TLS & Fingerprint Trust
  echo -e "\n${C_BOLD}[TLS Certificates & Security]${C_RESET}"
  local tls_dir="$HOME/.config/Deskflow/tls"
  if [ -f "$tls_dir/deskflow.pem" ]; then
    doc_ok "TLS certificate present: $tls_dir/deskflow.pem"
    local fp
    fp="$(openssl x509 -in "$tls_dir/deskflow.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]' || true)"
    if [ -n "$fp" ]; then
      if [ -f "$tls_dir/trusted-servers" ] && grep -q "$fp" "$tls_dir/trusted-servers"; then
        doc_ok "Server certificate fingerprint recognized in trusted-servers"
      else
        doc_warn "Certificate fingerprint not found in trusted-servers"
        warnings=$((warnings + 1))
      fi
    fi
  else
    doc_fail "Missing Deskflow TLS certificate at $tls_dir/deskflow.pem"
    failures=$((failures + 1))
  fi

  # 5. Auto-Unlock & Screen Session
  echo -e "\n${C_BOLD}[Auto-Unlock & Screen Session]${C_RESET}"
  if systemctl is-enabled plasmalogin.service >/dev/null 2>&1; then
    doc_ok "Display manager standardized on plasma-login-manager (plasmalogin.service)"
  elif systemctl is-enabled sddm.service >/dev/null 2>&1; then
    doc_warn "Display manager is SDDM; run 'knot repair' to migrate to plasma-login-manager"
    warnings=$((warnings + 1))
  fi

  if systemctl --user is-active --quiet knot-autounlock.service 2>/dev/null; then
    doc_ok "knot-autounlock.service is active"
  else
    doc_warn "knot-autounlock.service is not active"
    warnings=$((warnings + 1))
  fi

  source "$KNOT_ROOT/core/modules/autounlock.sh"
  source "$KNOT_ROOT/core/modules/autologin.sh"
  local raw_session
  raw_session="$(screen_status_raw)"
  if [ "$raw_session" = "NO_SESSION" ]; then
    doc_warn "No active loginctl seat session detected for user $my_user (node at login screen)"
    warnings=$((warnings + 1))
    if ! autologin_is_anchor; then
      local a_state
      a_state="$(autologin_anchor_status)"
      if [ "$a_state" = "UNLOCKED" ]; then
        knot_log_info "  -> Anchor is UP and UNLOCKED; strand is eligible for automatic first login."
      fi
    fi
  else
    local u sid seat stype locked
    IFS='|' read -r u sid seat stype locked <<< "$raw_session"
    doc_ok "Active session $sid ($stype on $seat, locked=$locked)"
  fi

  source "$KNOT_ROOT/core/modules/deskflow.sh"
  local lock_state
  lock_state="$(deskflow_get_lock)"
  if [ "$lock_state" = "locked" ]; then
    doc_warn "KVM Cursor Lock: LOCKED (host cursor confined to desktop screen)"
    warnings=$((warnings + 1))
  else
    doc_ok "KVM Cursor Lock: UNLOCKED (multi-screen crossover active)"
  fi

  # 6. KDE Connect & Mesh Clipboard Sharing
  echo -e "\n${C_BOLD}[KDE Connect & Mesh Clipboard Sync]${C_RESET}"
  local qdbus_cmd=""
  if command -v qdbus6 >/dev/null; then
    qdbus_cmd="qdbus6"
  elif command -v qdbus >/dev/null; then
    qdbus_cmd="qdbus"
  fi

  if ! command -v kdeconnect-cli >/dev/null; then
    doc_fail "kdeconnect-cli is not installed on this host"
    failures=$((failures + 1))
  else
    doc_ok "kdeconnect-cli is installed"
  fi

  if pgrep -u "$my_user" -x kdeconnectd >/dev/null; then
    doc_ok "kdeconnectd daemon is active for user $my_user"
  else
    doc_fail "kdeconnectd daemon is NOT running for user $my_user"
    failures=$((failures + 1))
  fi

  if [ -n "$qdbus_cmd" ]; then
    local paired_devs_out
    if paired_devs_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>&1)"; then
      local paired_list=()
      while IFS= read -r dev; do
        [ -n "$dev" ] && paired_list+=("$dev")
      done <<< "$paired_devs_out"

      if [ "${#paired_list[@]}" -eq 0 ]; then
        doc_warn "No paired KDE Connect devices detected on $my_host"
        warnings=$((warnings + 1))
      else
        doc_ok "Detected ${#paired_list[@]} paired KDE Connect device(s)"
        for dev in "${paired_list[@]}"; do
          local dev_name="$dev"
          local name_out
          if name_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
            if [ -n "$name_out" ]; then dev_name="$name_out"; fi
          fi

          local is_reach="false"
          local reach_out
          if reach_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isReachable 2>&1)"; then
            is_reach="$reach_out"
          fi

          local is_clip="false"
          local clip_out
          if clip_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPluginEnabled kdeconnect_clipboard 2>&1)"; then
            is_clip="$clip_out"
          fi

          if [ "$is_clip" = "true" ]; then
            doc_ok "Device '$dev_name' ($dev): clipboard sharing is ENABLED (reachable: $is_reach)"
          else
            doc_fail "Device '$dev_name' ($dev): clipboard sharing is DISABLED (run 'knot repair' or 'knot kdeconnect sync' to fix)"
            failures=$((failures + 1))
          fi
        done
      fi
    else
      doc_warn "Failed to query KDE Connect devices via DBus: $paired_devs_out"
      warnings=$((warnings + 1))
    fi
  else
    doc_warn "Neither qdbus6 nor qdbus installed; skipping KDE Connect plugin checks"
    warnings=$((warnings + 1))
  fi
  # 7. Antigravity Swarm Node Health
  echo -e "\n${C_BOLD}[Antigravity Swarm Node Health]${C_RESET}"
  if command -v antigravity_detect_cli >/dev/null 2>&1 && antigravity_detect_cli; then
    local agy_ver
    agy_ver="$(antigravity_get_version)"
    doc_ok "Antigravity CLI installed: version $agy_ver"

    local agy_test_out="" agy_rc=0
    agy_test_out="$(antigravity_exec_node "local" "ping" 2>&1)" || agy_rc=$?
    if [ $agy_rc -eq 0 ] && echo "$agy_test_out" | grep -q '"status":[[:space:]]*"SUCCESS"'; then
      local dur tok
      dur="$(echo "$agy_test_out" | grep -o '"duration_seconds":[0-9.]*' | cut -d: -f2 | awk '{printf "%.2fs", $1}')"
      tok="$(echo "$agy_test_out" | grep -o '"total_tokens":[0-9]*' | cut -d: -f2)"
      doc_ok "Antigravity Swarm Agent: AUTHENTICATED & OPERATIONAL (${dur:-ok}, ${tok:-?} tokens)"
    else
      doc_fail "Antigravity Swarm Agent: NOT AUTHENTICATED (run 'knot swarm test local' or 'agy' to log in)"
      failures=$((failures + 1))
    fi
  else
    doc_warn "Antigravity CLI (agy) is NOT installed on this node"
    warnings=$((warnings + 1))
  fi

  return $failures
}

# ------------------------------------------------------------------------------
# Diagnostic Check: Mesh Orchestrator
# ------------------------------------------------------------------------------
doctor_diagnose() {
  local target="${1:-all}"
  local repair_requested=0

  if [ "${2:-}" = "--repair" ] || [ "${1:-}" = "--repair" ]; then
    repair_requested=1
    if [ "$target" = "--repair" ]; then target="all"; fi
  fi

  if [ "$target" = "local" ]; then
    doctor_check_local
    return $?
  fi

  echo -e "${C_BOLD}=========================================${C_RESET}"
  echo -e "${C_BOLD}         Knot Mesh Health Doctor         ${C_RESET}"
  echo -e "${C_BOLD}=========================================${C_RESET}"

  local total_issues=0

  if [ "$target" = "all" ] || [ "$target" = "--all" ]; then
    # First check local
    local local_issues=0
    doctor_check_local || local_issues=$?
    total_issues=$((total_issues + local_issues))

    # Then check all remote nodes in registry
    local my_host
    my_host="$(knot_detect_hostname)"
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      local id host
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"

      if [ "$host" = "$my_host" ]; then
        continue
      fi

      echo -e "\n${C_BOLD}>>> Querying node: $id ($host)...${C_RESET}"
      local remote_out="" rc=0
      remote_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$id" "knot doctor local" 2>&1)" || rc=$?
      if [ -n "$remote_out" ]; then
        echo "$remote_out"
      fi
      if [ $rc -ne 0 ]; then
        total_issues=$((total_issues + rc))
      fi
    done
  else
    # Target specific node
    local my_host
    my_host="$(knot_detect_hostname)"
    local target_host=""
    local manifest="$KNOT_ROOT/registry/nodes/${target}.json"
    if [ -f "$manifest" ]; then
      target_host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
    fi

    if [ "$target" = "$my_host" ] || [ "$target_host" = "$my_host" ]; then
      local local_issues=0
      doctor_check_local || local_issues=$?
      total_issues=$((total_issues + local_issues))
    else
      echo -e "\n${C_BOLD}>>> Querying node: $target...${C_RESET}"
      local remote_out="" rc=0
      remote_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target" "knot doctor local" 2>&1)" || rc=$?
      if [ -n "$remote_out" ]; then
        echo "$remote_out"
      fi
      if [ $rc -ne 0 ]; then
        total_issues=$((total_issues + rc))
      fi
    fi
  fi

  echo -e "\n${C_BOLD}=========================================${C_RESET}"
  if [ $total_issues -eq 0 ]; then
    echo -e "${C_GREEN}${C_BOLD}[✓] Knot Mesh is healthy! All checks passed.${C_RESET}"
  else
    echo -e "${C_RED}${C_BOLD}[✗] Doctor detected $total_issues issue(s) across the mesh.${C_RESET}"
    if [ $repair_requested -eq 1 ]; then
      echo -e "${C_CYAN}Auto-repair flag set. Initiating automated repair...${C_RESET}\n"
      doctor_repair "$target"
    else
      echo -e "Run ${C_BOLD}knot doctor --repair${C_RESET} or ${C_BOLD}knot repair${C_RESET} to automatically resolve detected issues."
    fi
  fi
  echo -e "${C_BOLD}=========================================${C_RESET}"
  return $total_issues
}

# ------------------------------------------------------------------------------
# Auto-Repair Engine: Local Node
# ------------------------------------------------------------------------------
doctor_repair_local() {
  local my_host
  my_host="$(knot_detect_hostname)"
  local my_user
  my_user="$(knot_detect_user)"
  local is_anchor=0

  if [ -f "$KNOT_ROOT/registry/nodes/desktop.json" ] && grep -q "$my_host" "$KNOT_ROOT/registry/nodes/desktop.json"; then
    is_anchor=1
  fi

  knot_log_info "Repairing Knot components locally on $my_host..."

  # 0. Ensure display manager is migrated to plasma-login-manager
  source "$KNOT_ROOT/core/modules/autologin.sh"
  autologin_ensure_dm

  # 0b. If Strand has no graphical session and Anchor is unlocked, log in first
  if [ $is_anchor -eq 0 ]; then
    local current_sess
    current_sess="$(screen_get_local_session)"
    if [ -z "$current_sess" ]; then
      local a_state
      a_state="$(autologin_anchor_status)"
      if [ "$a_state" = "UNLOCKED" ]; then
        knot_log_info "Strand is at login screen; performing ephemeral first login..."
        autologin_execute_local
      fi
    fi
  fi

  # 1. Ensure KDE Portal backend is enabled
  local kde_portal_service="/usr/lib/systemd/user/plasma-xdg-desktop-portal-kde.service"
  if [ -f "$kde_portal_service" ]; then
    local wants_dir="$HOME/.config/systemd/user/graphical-session.target.wants"
    if [ ! -L "$wants_dir/plasma-xdg-desktop-portal-kde.service" ]; then
      knot_log_info "Configuring persistent KDE portal startup in graphical-session..."
      mkdir -p "$wants_dir"
      ln -sf "$kde_portal_service" "$wants_dir/plasma-xdg-desktop-portal-kde.service"
      systemctl --user daemon-reload
    fi
    if ! systemctl --user is-active --quiet plasma-xdg-desktop-portal-kde.service 2>/dev/null; then
      knot_log_info "Starting plasma-xdg-desktop-portal-kde.service..."
      systemctl --user start plasma-xdg-desktop-portal-kde.service 2>/dev/null || true
    fi
  fi

  # 2. Check if portal D-Bus interface is missing
  local portal_broken=0
  if command -v gdbus >/dev/null; then
    if [ $is_anchor -eq 0 ]; then
      if ! gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q 'interface org.freedesktop.portal.RemoteDesktop'; then
        portal_broken=1
      fi
    else
      if ! gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q 'interface org.freedesktop.portal.InputCapture'; then
        portal_broken=1
      fi
    fi
  fi

  # CRITICAL SAFETY: NEVER restart xdg-desktop-portal while Deskflow is running on Anchor!
  # If portal is broken, stop knot-deskflow FIRST so KWin does not trap pointer/keyboard in an orphaned session.
  if [ $portal_broken -eq 1 ]; then
    knot_log_warn "Portal interface missing. Safely stopping deskflow before reloading xdg-desktop-portal..."
    systemctl --user stop knot-deskflow.service 2>/dev/null || true
    sleep 0.5
    systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
    sleep 1
  fi

  # 3. Flatpak Remote Desktop Permissions
  if command -v flatpak >/dev/null; then
    flatpak permission-set kde-authorized remote-desktop "" yes 2>/dev/null || true
    flatpak permission-set kde-authorized remote-desktop org.deskflow.deskflow yes 2>/dev/null || true
    flatpak permission-set kde-authorized remote-desktop deskflow yes 2>/dev/null || true
    flatpak permission-set kde-authorized remote-desktop deskflow-core yes 2>/dev/null || true
  fi

  # 4. Deskflow TLS sync
  local cfg_dir="$HOME/.config/Deskflow"
  local tls_dir="$cfg_dir/tls"
  mkdir -p "$tls_dir"
  chmod 700 "$tls_dir"

  if [ $is_anchor -eq 1 ]; then
    if [ ! -f "$tls_dir/deskflow.pem" ]; then
      knot_log_info "Generating Anchor Deskflow TLS certificate..."
      openssl req -x509 -nodes -days 3650 -subj "/CN=Deskflow" -newkey rsa:2048 \
        -keyout "$tls_dir/deskflow.pem" -out "$tls_dir/deskflow.pem"
      chmod 600 "$tls_dir/deskflow.pem"
    fi
    local fp
    fp="$(openssl x509 -in "$tls_dir/deskflow.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
    echo "v2:sha256:$fp" > "$tls_dir/trusted-servers"
    echo "v2:sha256:$fp" > "$tls_dir/trusted-clients"
    chmod 600 "$tls_dir/trusted-servers" "$tls_dir/trusted-clients"
  else
    if [ ! -f "$tls_dir/deskflow.pem" ]; then
      knot_log_info "Syncing TLS certificate and fingerprints from Anchor desktop..."
      scp -o BatchMode=yes -o ConnectTimeout=4 "desktop:.config/Deskflow/tls/deskflow.pem" "$tls_dir/deskflow.pem" 2>/dev/null || true
    fi
    if [ -f "$tls_dir/deskflow.pem" ]; then
      chmod 600 "$tls_dir/deskflow.pem"
      local fp
      fp="$(openssl x509 -in "$tls_dir/deskflow.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
      echo "v2:sha256:$fp" > "$tls_dir/trusted-servers"
      echo "v2:sha256:$fp" > "$tls_dir/trusted-clients"
      chmod 600 "$tls_dir/trusted-servers" "$tls_dir/trusted-clients"
    fi
  fi

  # 5. Service & Client Runner Reconciliation
  source "$KNOT_ROOT/core/modules/deskflow.sh"
  if [ $is_anchor -eq 0 ]; then
    deskflow_configure
  else
    # On Anchor: only configure/restart if not running or listening
    if ! ss -H -tl sport = :24800 2>/dev/null | grep -q 24800 || ! systemctl --user is-active --quiet knot-deskflow 2>/dev/null; then
      deskflow_configure
    fi
  fi

  # 6. Ensure auto-unlock daemon is running
  source "$KNOT_ROOT/core/modules/autounlock.sh"
  if ! systemctl --user is-active --quiet knot-autounlock 2>/dev/null; then
    autounlock_configure
  fi

  # 7. Ensure KDE Connect mesh sync & clipboard sharing
  source "$KNOT_ROOT/core/modules/kdeconnect.sh"
  kdeconnect_sync_mesh

  knot_log_ok "Local repair operations completed for $my_host."
}

# ------------------------------------------------------------------------------
# Auto-Repair Engine: Mesh Orchestrator
# ------------------------------------------------------------------------------
doctor_repair() {
  local target="${1:-all}"
  if [ "$target" = "--repair" ]; then target="all"; fi

  echo -e "${C_BOLD}=========================================${C_RESET}"
  echo -e "${C_BOLD}          Knot Mesh Auto-Repair          ${C_RESET}"
  echo -e "${C_BOLD}=========================================${C_RESET}"

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
  if [ -z "$anchor_host" ] && [ -d "$KNOT_ROOT/registry/nodes" ]; then
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      if grep -q '"id":[[:space:]]*"desktop"' "$manifest"; then
        anchor_host="$(grep -o '"hostname":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"
      fi
    done
  fi

  local my_host
  my_host="$(knot_detect_hostname)"

  if [ "$target" = "local" ]; then
    doctor_repair_local
  elif [ "$target" = "all" ] || [ "$target" = "--all" ]; then
    # Step 1: Check Anchor Health. ONLY repair Anchor if it is NOT healthy!
    local anchor_healthy=1
    if [ "$my_host" = "$anchor_host" ]; then
      if ! ss -H -tl sport = :24800 2>/dev/null | grep -q 24800 || ! systemctl --user is-active --quiet knot-deskflow 2>/dev/null; then
        anchor_healthy=0
        doctor_repair_local
      else
        knot_log_ok "Anchor desktop ($anchor_host) KVM server is healthy and listening."
      fi
    else
      if ! ssh -o BatchMode=yes -o ConnectTimeout=3 "$anchor_id" "ss -H -tl sport = :24800 | grep -q 24800 && systemctl --user is-active --quiet knot-deskflow" 2>/dev/null; then
        anchor_healthy=0
        knot_log_info "Initiating repair on Anchor desktop ($anchor_host)..."
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$anchor_id" "knot repair local 2>/dev/null || ~/Dev/knot/bin/knot repair local" || knot_log_warn "Failed to repair Anchor"
      else
        knot_log_ok "Anchor desktop ($anchor_host) KVM server is healthy and listening."
      fi
    fi

    sleep 0.5

    # Step 2: Repair Strands
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      local id host
      id="$(grep -o '"id":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"
      host="$(grep -o '"hostname":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"

      if [ "$id" = "$anchor_id" ] || [ "$host" = "$anchor_host" ]; then
        continue
      fi

      if [ "$my_host" = "$host" ]; then
        doctor_repair_local
      else
        knot_log_info "Initiating repair on Strand $id ($host)..."
        ssh -o BatchMode=yes -o ConnectTimeout=5 "$id" "knot repair local 2>/dev/null || ~/Dev/knot/bin/knot repair local" || knot_log_warn "Failed to repair $id"
      fi
    done

    # Step 3: Only restart entire mesh if Anchor was repaired
    if [ $anchor_healthy -eq 0 ]; then
      sleep 1
      knot_log_info "Anchor was repaired; synchronizing Deskflow KVM mesh restart..."
      "$KNOT_ROOT/bin/knot" kvm restart
    fi

  else
    # Single target
    if [ "$target" = "$my_host" ]; then
      doctor_repair_local
    else
      knot_log_info "Initiating repair on target $target..."
      ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "knot repair local 2>/dev/null || ~/Dev/knot/bin/knot repair local"
      "$KNOT_ROOT/bin/knot" exec "$target" "systemctl --user restart knot-deskflow.service"
    fi
  fi

  sleep 1.5
  echo -e "\n${C_BOLD}Post-repair verification:${C_RESET}"
  doctor_diagnose "$target"
}
