#!/usr/bin/env bash
set -euo pipefail

# Knot Antigravity Swarm Module
# Core orchestration and health engine for headless agy CLI agents across mesh nodes

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

antigravity_detect_cli() {
  local cli_path=""
  cli_path="$(antigravity_get_cli_path)"
  if [ -n "$cli_path" ] && [ -x "$cli_path" ]; then
    return 0
  fi
  return 1
}

antigravity_get_cli_path() {
  local p=""
  if command -v agy >/dev/null; then
    p="$(command -v agy)"
  elif [ -x "$HOME/.local/bin/agy" ]; then
    p="$HOME/.local/bin/agy"
  elif [ -x "/usr/local/bin/agy" ]; then
    p="/usr/local/bin/agy"
  elif [ -x "/usr/bin/agy" ]; then
    p="/usr/bin/agy"
  fi

  if [ -n "$p" ] && [ -x "$p" ]; then
    echo "$p"
    return 0
  fi

  local fallback_candidates=()
  if command -v antigravity >/dev/null; then
    fallback_candidates+=("$(command -v antigravity)")
  fi
  for cand_path in "$HOME/.local/bin/antigravity" "/usr/local/bin/antigravity" "/usr/bin/antigravity"; do
    if [ -x "$cand_path" ]; then
      fallback_candidates+=("$cand_path")
    fi
  done

  local tested=""
  for cand in "${fallback_candidates[@]}"; do
    [[ " $tested " =~ " $cand " ]] && continue
    tested="$tested $cand"
    local test_out="" rc=0
    if command -v timeout >/dev/null; then
      test_out="$(timeout 3 "$cand" --version 2>&1)" || rc=$?
    else
      test_out="$("$cand" --version 2>&1)" || rc=$?
    fi
    if [ $rc -eq 0 ] && [ -n "$test_out" ]; then
      echo "$cand"
      return 0
    fi
  done

  echo ""
  return 0
}

antigravity_get_version() {
  local agy_path=""
  agy_path="$(antigravity_get_cli_path)"
  if [ -z "$agy_path" ]; then
    echo "not_installed"
    return 1
  fi

  local ver_out="" rc=0
  if command -v timeout >/dev/null; then
    ver_out="$(timeout 3 "$agy_path" --version 2>&1)" || rc=$?
  else
    ver_out="$("$agy_path" --version 2>&1)" || rc=$?
  fi
  if [ $rc -eq 0 ] && [ -n "$ver_out" ]; then
    echo "$ver_out" | head -n1 | awk '{print $NF}'
    return 0
  else
    echo "unknown"
    return 1
  fi
}

antigravity_ensure_shims() {
  local shims_dir="$HOME/.local/share/knot/shims"
  mkdir -p "$shims_dir"
  local binaries=(
    xdg-open kde-open kde-open5 kde-open6
    kioexec kfmclient gio sensible-browser
    x-www-browser chromium google-chrome-stable
    google-chrome brave firefox
  )
  for b in "${binaries[@]}"; do
    local p="$shims_dir/$b"
    if [ ! -x "$p" ]; then
      cat << 'EOF' > "$p"
#!/bin/sh
# Knot Headless Shim: Exit immediately to prevent GUI spawns
exit 0
EOF
      chmod +x "$p"
    fi
  done
  echo "$shims_dir"
}

# Run agy command inside local user systemd slice to ensure DBus & KWallet access
antigravity_run_local_systemd() {
  local agy_path
  agy_path="$(antigravity_get_cli_path)"
  if [ -z "$agy_path" ]; then
    knot_log_err "Antigravity CLI (agy) not found on local system."
    return 1
  fi

  local shims_dir
  shims_dir="$(antigravity_ensure_shims)"

  if command -v systemd-run >/dev/null; then
    systemd-run --user --pipe \
      --setenv="PATH=$shims_dir:/usr/local/bin:/usr/bin:/bin" \
      --setenv=BROWSER=/bin/true \
      --setenv=DE=generic \
      --setenv=XDG_CURRENT_DESKTOP="" \
      --setenv=KDE_FULL_SESSION="" \
      --setenv=KDE_SESSION_VERSION="" \
      "$agy_path" "$@"
  else
    PATH="$shims_dir:$PATH" BROWSER=/bin/true DE=generic XDG_CURRENT_DESKTOP="" "$agy_path" "$@"
  fi
}

# Sync credentials from FreeDesktop Secret Service / KWallet to ~/.gemini/antigravity-cli/antigravity-oauth-token
antigravity_sync_credentials() {
  local token_file="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
  mkdir -p "$(dirname "$token_file")"

  if command -v secret-tool >/dev/null; then
    local secret_json="" st_out="" st_rc=0
    st_out="$(secret-tool search service gemini 2>&1)" || st_rc=$?
    if [ $st_rc -eq 0 ]; then
      secret_json="$(echo "$st_out" | awk -F'secret = ' '/^secret = / {print $2}' | head -n1)"
    else
      knot_log_warn "Notice: secret-tool search failed (exit code $st_rc): $st_out"
    fi
    if [ -n "$secret_json" ] && echo "$secret_json" | jq -e '.token.access_token or .token.refresh_token' >/dev/null; then
      local current_json=""
      if [ -f "$token_file" ]; then
        current_json="$(cat "$token_file")"
      fi
      if [ "$current_json" != "$secret_json" ]; then
        echo "$secret_json" > "$token_file"
        chmod 600 "$token_file"
        knot_log_ok "Synchronized updated Antigravity token from Secret Service to $token_file"
      fi
      return 0
    fi
  fi

  if [ -s "$token_file" ] && jq -e '.token.access_token or .token.refresh_token' "$token_file" >/dev/null; then
    return 0
  fi
  return 1
}

# Check if KWallet or Secret Service is unlocked on local node
antigravity_is_kwallet_unlocked() {
  # 1. Check Secret Service collection Locked property first (modern Plasma 6 / ksecretd / GNOME Keyring)
  local locked="" lock_out="" rc_lock=0
  lock_out="$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>&1)" || rc_lock=$?
  if [ $rc_lock -eq 0 ]; then
    locked="$lock_out"
    if echo "$locked" | grep -q "false"; then
      return 0
    elif echo "$locked" | grep -q "true"; then
      return 1
    fi
  else
    knot_log_warn "Notice: Secret Service collection status check failed (exit code $rc_lock): $lock_out"
  fi

  # 2. Check KDE KWallet DBus interface (Plasma 6 / 5)
  for svc in org.kde.kwalletd6 org.kde.kwalletd5; do
    local mod="${svc##*.}"
    local en_out="" en_rc=0
    en_out="$(busctl --user call "$svc" "/modules/$mod" org.kde.KWallet isEnabled 2>&1)" || en_rc=$?
    if [ $en_rc -eq 0 ]; then
      if echo "$en_out" | grep -q "true"; then
        local wallet="kdewallet" wal_out="" wal_rc=0
        wal_out="$(busctl --user call "$svc" "/modules/$mod" org.kde.KWallet localWallet 2>&1)" || wal_rc=$?
        if [ $wal_rc -eq 0 ]; then
          local parsed_wal
          parsed_wal="$(echo "$wal_out" | awk -F'"' '{print $2}')"
          if [ -n "$parsed_wal" ]; then wallet="$parsed_wal"; fi
        else
          knot_log_warn "Notice: DBus call $svc localWallet failed (exit code $wal_rc): $wal_out"
        fi

        local open_out="" open_rc=0
        open_out="$(busctl --user call "$svc" "/modules/$mod" org.kde.KWallet isOpen s "$wallet" 2>&1)" || open_rc=$?
        if [ $open_rc -eq 0 ]; then
          if echo "$open_out" | grep -q "true"; then
            return 0
          elif echo "$open_out" | grep -q "false"; then
            return 1
          fi
        else
          knot_log_warn "Notice: DBus call $svc isOpen failed (exit code $open_rc): $open_out"
        fi
      fi
    else
      knot_log_warn "Notice: DBus service $svc isEnabled call failed (exit code $en_rc): $en_out"
    fi
  done

  return 0
}

# Check if an OAuth token file exists on disk with a valid token payload
antigravity_has_oauth_token_file() {
  local token_file="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
  local fallback_token="$HOME/.gemini/jetski-standalone-oauth-token"
  local jq_out=""
  if [ -s "$token_file" ]; then
    if jq_out="$(jq -e '.token.access_token or .token.refresh_token' "$token_file" 2>&1)"; then
      return 0
    fi
  fi
  if [ -s "$fallback_token" ]; then
    if jq_out="$(jq -e '.token.access_token or .token.refresh_token' "$fallback_token" 2>&1)"; then
      return 0
    fi
  fi
  return 1
}

# Fast verification of token/auth state on local node
antigravity_check_auth_local() {
  local agy_path
  agy_path="$(antigravity_get_cli_path)"
  if [ -z "$agy_path" ]; then
    return 1
  fi

  # Ensure credentials are sync'd first if unlocked
  if antigravity_is_kwallet_unlocked; then
    if ! antigravity_sync_credentials; then
      knot_log_warn "Notice: local credential synchronization failed or no credentials found"
    fi
  fi

  if antigravity_has_oauth_token_file; then
    return 0
  fi

  # Skip headless probe if KWallet is locked
  if ! antigravity_is_kwallet_unlocked; then
    return 1
  fi

  # Probe with a 1-token prompt to check live backend connectivity
  local probe_out="" rc=0
  probe_out="$(antigravity_run_local_systemd -p "ping" --output-format json 2>&1)" || rc=$?
  if [ $rc -eq 0 ] && echo "$probe_out" | grep -q '"status":[[:space:]]*"SUCCESS"'; then
    return 0
  fi
  return 1
}

# Execute a prompt on any target node (local or remote) and output raw JSON telemetry
antigravity_exec_node() {
  local target="$1"
  local prompt="$2"
  shift 2
  local extra_flags=("$@")

  local my_host
  my_host="$(knot_detect_hostname)"

  local manifest=""
  local target_host="$target"
  if manifest="$(knot_get_manifest_path "$target")"; then
    if [ -f "$manifest" ]; then
      target_host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
    fi
  fi

  # Ensure --dangerously-skip-permissions is set for headless autonomous agent executions
  local has_skip=0
  for f in "${extra_flags[@]}"; do
    if [ "$f" = "--dangerously-skip-permissions" ]; then has_skip=1; break; fi
  done
  if [ $has_skip -eq 0 ]; then
    extra_flags+=("--dangerously-skip-permissions")
  fi

  if [ "$target" = "local" ] || [ "$target" = "$my_host" ] || [ "$target_host" = "$my_host" ]; then
    local agy_path
    agy_path="$(antigravity_get_cli_path)"
    if [ -z "$agy_path" ]; then
      knot_log_err "agy CLI is not installed locally"
      return 1
    fi
    antigravity_run_local_systemd -p "$prompt" --output-format json "${extra_flags[@]}"
  else
    local port="22"
    if [ -f "$manifest" ]; then
      local p
      p="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest")"
      if [ -n "$p" ]; then port="$p"; fi
    fi

    local resolved_ip=""
    if ! resolved_ip="$("$KNOT_ROOT/core/resolver.sh" "$target" "$port")"; then
      knot_log_err "Failed to resolve node '$target'"
      return 1
    fi

    # Dispatch remotely into the target user's graphical session slice
    ssh -o BatchMode=yes -o ConnectTimeout=8 -p "$port" "$target" \
      "systemd-run --user --pipe \
         --setenv=\"PATH=\$HOME/.local/bin:\$HOME/.local/share/knot/shims:/usr/local/bin:/usr/bin:/bin\" \
         --setenv=BROWSER=/bin/true \
         --setenv=DE=generic \
         --setenv=XDG_CURRENT_DESKTOP=\"\" \
         --setenv=KDE_FULL_SESSION=\"\" \
         --setenv=KDE_SESSION_VERSION=\"\" \
         agy -p $(printf '%q' "$prompt") --output-format json ${extra_flags[*]:-}"
  fi
}

# Guided onboarding step for Antigravity on a node
antigravity_onboard() {
  knot_log_info "Verifying Antigravity Swarm CLI (agy) integration..."

  if ! antigravity_detect_cli; then
    knot_log_warn "Antigravity CLI (agy) is not installed on this system."
    knot_log_info "To install: ensure Antigravity IDE is installed from https://antigravity.google or package manager."
    return 0
  fi

  local ver="unknown"
  local v_out=""
  if v_out="$(antigravity_get_version 2>&1)"; then
    ver="$v_out"
  fi
  knot_log_ok "Antigravity CLI detected: version $ver"

  knot_log_info "Checking Antigravity authentication status..."
  if antigravity_check_auth_local; then
    knot_log_ok "Antigravity CLI is authenticated and operational!"
    return 0
  fi

  local agy_bin
  agy_bin="$(antigravity_get_cli_path)"
  knot_log_warn "Antigravity CLI is not yet authenticated on this node."

  if [ -n "${KNOT_TEST_MODE:-}" ] || [ ! -t 0 ]; then
    knot_log_info "Non-interactive session: skipping graphical login prompt. Run 'agy' later to authenticate."
    return 0
  fi

  knot_log_info "Initiating guided authentication terminal on graphical display..."

  if command -v konsole >/dev/null; then
    systemd-run --user konsole -e "$agy_bin"
    knot_log_info "Launched Konsole on local display. Please log in with Google, then press Enter here to verify."
    read -r -p "Press [Enter] once authentication is complete in the opened terminal..."
  elif command -v kitty >/dev/null; then
    systemd-run --user kitty "$agy_bin"
    knot_log_info "Launched Kitty on local display. Please log in with Google, then press Enter here to verify."
    read -r -p "Press [Enter] once authentication is complete in the opened terminal..."
  else
    knot_log_info "Please run '$agy_bin' in an interactive graphical terminal to complete Google OAuth sign-in."
    read -r -p "Press [Enter] once authentication is complete..."
  fi

  if antigravity_check_auth_local; then
    knot_log_ok "Antigravity CLI authentication verified successfully!"
  else
    knot_log_warn "Antigravity CLI authentication could not be verified automatically. You can test later with 'knot swarm test local'."
  fi
}

# Query Hub node telemetry or heartbeat cache
antigravity_get_hub_telemetry() {
  local target_id="$1"
  local target_host="$2"
  local user_home
  user_home="$(knot_detect_user_home)"
  local hub_db="$user_home/.config/knot/hub.db"

  if [ -r "$hub_db" ] && command -v sqlite3 >/dev/null; then
    local db_out=""
    if db_out="$(sqlite3 -separator '|' "$hub_db" "SELECT agy_version, agy_auth, status, last_heartbeat FROM nodes WHERE id = '$target_id' OR hostname = '$target_host' ORDER BY last_heartbeat DESC LIMIT 1;" 2>&1)"; then
      if [ -n "$db_out" ]; then
        echo "$db_out"
        return 0
      fi
    fi
  fi

  local hub_url="${KNOT_HUB_URL:-https://127.0.0.1:4242}"
  local rest_out=""
  if rest_out="$(python3 -c "
import urllib.request, ssl, json, sys
try:
    ctx = ssl._create_unverified_context()
    req = urllib.request.Request('$hub_url/nodes', headers={'Accept': 'application/json'})
    with urllib.request.urlopen(req, timeout=1.5, context=ctx) as r:
        nodes = json.loads(r.read().decode('utf-8'))
        for n in nodes:
            if n.get('id') == '$target_id' or n.get('hostname') == '$target_host':
                v = n.get('agy_version') or ''
                a = n.get('agy_auth') or ''
                s = n.get('status') or ''
                h = n.get('last_heartbeat') or 0
                print(f'{v}|{a}|{s}|{h}')
                sys.exit(0)
except Exception as e:
    sys.stderr.write(f'Notice: Hub probe failed: {e}\n')
sys.exit(1)
" 2>&1)"; then
    if [ -n "$rest_out" ]; then
      echo "$rest_out"
      return 0
    fi
  fi

  return 1
}

# Show swarm status across all registered mesh nodes
antigravity_swarm_status() {
  echo -e "${C_BOLD}--- Knot Antigravity Swarm Status ---${C_RESET}"
  printf "%-12s %-16s %-12s %-16s %-12s\n" "NODE" "HOST" "CLI VERSION" "AUTH STATUS" "LATENCY"
  printf "%-12s %-16s %-12s %-16s %-12s\n" "----" "----" "-----------" "-----------" "-------"

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
      local id host
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      [ -n "$id" ] || continue
      if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
      seen_nodes+=("$id")

      local ver="missing" auth_status="UNKNOWN" latency="-"
      local test_out="" rc=0

      # 1. Fetch Hub telemetry / heartbeat cache upfront
      local telem_ver="" telem_auth="" telem_status="" telem_ts=0
      local telem=""
      if telem="$(antigravity_get_hub_telemetry "$id" "$host" 2>&1)"; then
        if [ -n "$telem" ]; then
          IFS='|' read -r telem_ver telem_auth telem_status telem_ts <<< "$telem"
        fi
      fi

      # 2. Upfront CLI Version detection
      if [ "$host" = "$my_host" ]; then
        if antigravity_detect_cli; then
          local v_out=""
          if v_out="$(antigravity_get_version 2>&1)"; then
            ver="$v_out"
          fi
        else
          ver="${C_RED}NOT INSTALLED${C_RESET}"
          auth_status="${C_RED}UNAVAILABLE${C_RESET}"
        fi
      else
        local remote_ver="" rv_rc=0
        if remote_ver="$(timeout 5 "$KNOT_ROOT/bin/knot" exec "$id" "export PATH=\"\$HOME/.local/bin:\$HOME/.local/share/knot/shims:/usr/local/bin:/usr/bin:/bin:\$PATH\"; agy --version" 2>&1)"; then
          local parsed_ver
          parsed_ver="$(echo "$remote_ver" | tr -d '\r' | tail -n1 | awk '{print $NF}')"
          if [ -n "$parsed_ver" ] && [[ "$parsed_ver" =~ ^[0-9] ]]; then
            ver="$parsed_ver"
          elif [ -n "$parsed_ver" ]; then
            ver="$parsed_ver"
          elif [ -n "$telem_ver" ] && [ "$telem_ver" != "unknown" ]; then
            ver="$telem_ver"
          else
            ver="installed"
          fi
        else
          rv_rc=$?
          if echo "$remote_ver" | grep -qi "command not found"; then
            ver="${C_RED}NOT INSTALLED${C_RESET}"
            auth_status="${C_RED}UNAVAILABLE${C_RESET}"
          elif [ -n "$telem_ver" ] && [ "$telem_ver" != "unknown" ] && [ "$telem_ver" != "not_found" ]; then
            ver="$telem_ver"
          elif [ $rv_rc -eq 124 ]; then
            ver="timeout"
            auth_status="${C_YELLOW}SSH TIMED OUT${C_RESET}"
          else
            ver="unreachable"
            auth_status="${C_RED}UNREACHABLE${C_RESET}"
          fi
        fi
      fi

      # 3. Auth status evaluation
      if [ "$auth_status" = "UNKNOWN" ]; then
        if [ "$host" = "$my_host" ]; then
          if ! antigravity_is_kwallet_unlocked && ! antigravity_has_oauth_token_file; then
            auth_status="${C_YELLOW}KWALLET LOCKED${C_RESET}"
          elif [ "$telem_auth" = "AUTHENTICATED" ]; then
            auth_status="${C_GREEN}AUTHENTICATED${C_RESET}"
            latency="<10ms (hub)"
          else
            test_out="$(timeout 15 antigravity_exec_node "local" "ping" 2>&1)" || rc=$?
            if [ $rc -eq 0 ] && echo "$test_out" | grep -q '"status":[[:space:]]*"SUCCESS"'; then
              auth_status="${C_GREEN}AUTHENTICATED${C_RESET}"
              local dur
              dur="$(echo "$test_out" | grep -o '"duration_seconds":[0-9.]*' | cut -d: -f2 | awk '{printf "%.2fs", $1}')"
              if [ -n "$dur" ]; then latency="$dur"; fi
            elif echo "$test_out" | grep -qiE 'RESOURCE_EXHAUSTED|"error_code":[[:space:]]*429|code[[:space:]]*429|quota[[:space:]]*exhausted|rate[[:space:]]*limit'; then
              auth_status="${C_YELLOW}QUOTA EXHAUSTED (429)${C_RESET}"
            elif [ $rc -eq 124 ]; then
              auth_status="${C_YELLOW}PROBE TIMED OUT${C_RESET}"
            else
              auth_status="${C_RED}NOT LOGGED IN${C_RESET}"
            fi
          fi
        else
          # Remote node
          if [ "$telem_auth" = "AUTHENTICATED" ]; then
            auth_status="${C_GREEN}AUTHENTICATED${C_RESET}"
            latency="<10ms (hub)"
          else
            local remote_probe="" rp_rc=0
            remote_probe="$(timeout 20 "$KNOT_ROOT/bin/knot" exec "$id" "systemd-run --user --pipe --setenv=\"PATH=\$HOME/.local/bin:\$HOME/.local/share/knot/shims:/usr/local/bin:/usr/bin:/bin\" --setenv=BROWSER=/bin/true --setenv=DE=generic --setenv=XDG_CURRENT_DESKTOP=\"\" --setenv=KDE_FULL_SESSION=\"\" --setenv=KDE_SESSION_VERSION=\"\" agy -p 'ping' --output-format json" 2>&1)" || rp_rc=$?
            if [ $rp_rc -eq 0 ] && echo "$remote_probe" | grep -q '"status":[[:space:]]*"SUCCESS"'; then
              auth_status="${C_GREEN}AUTHENTICATED${C_RESET}"
              local dur
              dur="$(echo "$remote_probe" | grep -o '"duration_seconds":[0-9.]*' | cut -d: -f2 | awk '{printf "%.2fs", $1}')"
              if [ -n "$dur" ]; then latency="$dur"; fi
            elif echo "$remote_probe" | grep -qiE 'kwallet|keyring|secret service|org.freedesktop.secrets|locked'; then
              auth_status="${C_YELLOW}KEYRING LOCKED${C_RESET}"
            elif [ $rp_rc -eq 124 ]; then
              auth_status="${C_YELLOW}PROBE TIMED OUT${C_RESET}"
            elif echo "$remote_probe" | grep -qiE 'RESOURCE_EXHAUSTED|"error_code":[[:space:]]*429|code[[:space:]]*429|quota[[:space:]]*exhausted|rate[[:space:]]*limit'; then
              auth_status="${C_YELLOW}QUOTA EXHAUSTED (429)${C_RESET}"
            elif echo "$remote_probe" | grep -qiE 'authentication required|not logged in|unauthenticated'; then
              auth_status="${C_YELLOW}NOT LOGGED IN${C_RESET}"
            else
              auth_status="${C_RED}AUTH FAILED${C_RESET}"
            fi
          fi
        fi
      fi

      printf "%-12s %-16s %-12b %-25b %-12s\n" "$id" "$host" "$ver" "$auth_status" "$latency"
    done
  done
}

# Run a live test prompt across target node or all nodes
antigravity_swarm_test() {
  local target="${1:-all}"
  local prompt="${2:-Say hello from your node name in 4 words}"

  if [ "$target" = "all" ] || [ "$target" = "--all" ]; then
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
        local id
        id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        [ -n "$id" ] || continue
        if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
        seen_nodes+=("$id")
        antigravity_swarm_test "$id" "$prompt"
      done
    done
    return 0
  fi

  knot_log_info "Dispatching test prompt to node '$target'..."
  echo -e "  Prompt: ${C_CYAN}\"$prompt\"${C_RESET}"

  local raw_out="" rc=0 start_ts end_ts
  start_ts="$(date +%s%N)"
  raw_out="$(antigravity_exec_node "$target" "$prompt" 2>&1)" || rc=$?
  end_ts="$(date +%s%N)"
  local total_sec
  total_sec="$(awk "BEGIN {printf \"%.2f\", ($end_ts - $start_ts) / 1000000000}")"

  local json_line
  json_line="$(echo "$raw_out" | grep -E '^\{.*"status":' | tail -n1)"

  if [ $rc -eq 0 ] && echo "$raw_out" | grep -q '"status":[[:space:]]*"SUCCESS"'; then
    local response dur in_tok out_tok total_tok cid
    if command -v jq >/dev/null && [ -n "$json_line" ]; then
      response="$(echo "$json_line" | jq -r '.response // ""')"
      dur="$(echo "$json_line" | jq -r '(.duration_seconds // 0) | tostring' | awk '{printf "%.2fs", $1}')"
      in_tok="$(echo "$json_line" | jq -r '.usage.input_tokens // "?"')"
      out_tok="$(echo "$json_line" | jq -r '.usage.output_tokens // "?"')"
      total_tok="$(echo "$json_line" | jq -r '.usage.total_tokens // "?"')"
      cid="$(echo "$json_line" | jq -r '.conversation_id // "none"')"
    else
      response="$(echo "$raw_out" | grep -o '"response":[[:space:]]*"[^"]*"' | sed 's/"response":[[:space:]]*"//;s/"$//;s/\\n//g')"
      dur="$(echo "$raw_out" | grep -o '"duration_seconds":[0-9.]*' | cut -d: -f2 | awk '{printf "%.2fs", $1}')"
      in_tok="$(echo "$raw_out" | grep -o '"input_tokens":[0-9]*' | cut -d: -f2)"
      out_tok="$(echo "$raw_out" | grep -o '"output_tokens":[0-9]*' | cut -d: -f2)"
      total_tok="$(echo "$raw_out" | grep -o '"total_tokens":[0-9]*' | cut -d: -f2)"
      cid="$(echo "$raw_out" | grep -o '"conversation_id":[[:space:]]*"[^"]*"' | cut -d'"' -f4)"
    fi

    knot_log_ok "Node '$target' responded successfully!"
    echo -e "  Response:\n${C_GREEN}$response${C_RESET}"
    echo -e "  Latency:    ${C_YELLOW}${dur:-${total_sec}s}${C_RESET} (roundtrip: ${total_sec}s)"
    echo -e "  Tokens:     in: ${in_tok:-?} | out: ${out_tok:-?} | total: ${total_tok:-?}"
    echo -e "  Session ID: ${cid:-none}"
  else
    knot_log_err "Node '$target' failed test execution (exit code $rc):"
    echo "$raw_out"
    return 1
  fi
}

# Display model quotas across the mesh
antigravity_swarm_quota() {
  local target="${1:-all}"
  if [ "$target" = "watch" ] || [ "$target" = "live" ] || [ "$target" = "--live" ] || [ "$target" = "--watch" ]; then
    if [ $# -gt 0 ]; then
      shift
    fi
    exec python3 "$KNOT_ROOT/core/hub/limit_visualizer.py" "$@"
  fi

  local hub_url=""
  if [ -n "${KNOT_HUB_URL:-}" ]; then
    hub_url="$KNOT_HUB_URL"
  else
    hub_url="https://127.0.0.1:4242"
  fi

  python3 "$KNOT_ROOT/core/hub/quota_view.py" "$target" "$hub_url"
}

antigravity_get_my_node() {
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
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local h id
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      if [ "$h" = "$my_host" ]; then
        echo "$id"
        return 0
      fi
    done
  done
  echo "$my_host"
}

# Interactive login and authentication for Antigravity CLI across mesh nodes
antigravity_swarm_auth() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot auth [node_id|sync] [--gui]"
    echo ""
    echo "Authenticate or refresh Antigravity CLI Google login on mesh nodes."
    echo ""
    echo "Options:"
    echo "  [node_id]   Target node ('desktop', 'laptop', 'steamdeck', or local default)"
    echo "  sync        Synchronize tokens from KWallet/Secret Service to ~/.gemini/antigravity-cli/"
    echo "  --gui       Launch Konsole directly on the target machine's graphical screen"
    echo ""
    echo "Examples:"
    echo "  knot auth sync              Sync local token file from KWallet/Secret Service"
    echo "  knot auth sync --all        Sync token files across all mesh nodes"
    echo "  knot auth steamdeck         Interactive terminal login via SSH"
    echo "  knot auth laptop            Interactive terminal login via SSH"
    echo "  knot auth steamdeck --gui   Open terminal window on Steam Deck display"
    return 0
  fi

  if [ "${1:-}" = "sync" ]; then
    shift
    if [ "${1:-}" = "--all" ]; then
      knot_log_info "Synchronizing Antigravity credentials across all mesh nodes..."
      if ! antigravity_sync_credentials; then
        knot_log_warn "Local Antigravity credentials could not be synchronized."
      fi
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
          local id host
          id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
          host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
          [ -n "$id" ] || continue
          if [[ " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then continue; fi
          seen_nodes+=("$id")
          if [ "$host" != "$(knot_detect_hostname)" ] && [ "$id" != "$(knot_detect_hostname)" ]; then
            local sync_err="" sync_rc=0
            sync_err="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$id" "knot auth sync" 2>&1)" || sync_rc=$?
            if [ $sync_rc -ne 0 ]; then
              knot_log_warn "Failed to sync credentials to node '$id' (exit code $sync_rc): $sync_err"
            fi
          fi
        done
      done
      knot_log_ok "Credential sync complete across swarm."
      return 0
    else
      if ! antigravity_sync_credentials; then
        knot_log_warn "Local Antigravity credentials could not be synchronized."
      fi
      local r_out=""
      if ! r_out="$(systemctl --user restart knot-agent.service 2>&1)"; then
        knot_log_warn "Notice: knot-agent.service not running or could not restart: $r_out"
      fi
      knot_log_ok "Local Antigravity credentials synchronized."
      return 0
    fi
  fi

  local my_node
  my_node="$(antigravity_get_my_node)"
  local target="${1:-$my_node}"
  local gui_mode=0

  if [ "$target" = "--gui" ]; then
    gui_mode=1
    target="${2:-$my_node}"
  elif [ "${2:-}" = "--gui" ]; then
    gui_mode=1
  fi

  if [ "$target" = "local" ] || [ "$target" = "$my_node" ]; then
    knot_log_info "Launching interactive Antigravity CLI login on local node ($my_node)..."
    agy
    if ! antigravity_sync_credentials; then
      knot_log_warn "Local Antigravity credentials could not be synchronized."
    fi
    local r_out=""
    if ! r_out="$(systemctl --user restart knot-agent.service 2>&1)"; then
      knot_log_warn "Notice: knot-agent.service not running or restart failed: $r_out"
    fi
    knot_log_ok "Authentication complete and credentials synced."
    return 0
  fi

  if [ $gui_mode -eq 1 ]; then
    knot_log_info "Opening terminal on '$target' display for Antigravity login..."
    local uid="1000"
    if [ "$target" = "steamdeck" ]; then
      uid="1001"
    fi
    local log_file="/tmp/knot_konsole_agy.log"
    ssh "$target" "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$uid nohup konsole -e agy > '$log_file' 2>&1 &"
    knot_log_ok "Konsole opened on $target screen (logging to $log_file). Follow the on-screen prompt to log in."
    return 0
  fi

  knot_log_info "Connecting to '$target' for interactive Antigravity login..."
  echo -e "  ${C_YELLOW}1.${C_RESET} Select ${C_BOLD}1. Google OAuth${C_RESET} using Enter."
  echo -e "  ${C_YELLOW}2.${C_RESET} Click or copy the displayed URL into your browser to log in."
  echo -e "  ${C_YELLOW}3.${C_RESET} Copy the authorization code and paste it right into the prompt below."
  echo ""
  ssh -tt "$target" "agy && knot auth sync"
}
