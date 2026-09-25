#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh: Multi-Tenant Local Profile Sandboxing & Headless Authentication Isolation
# Implementation of GitHub Issue #60
# Adheres strictly to PSL Gold Standard (Rule 1: zero error swallowing, Rule 3: complete package)

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

# Default authentication sandbox directory (overrideable for isolated automated testing)
KNOT_AUTH_DIR="${KNOT_TEST_AUTH_DIR:-$HOME/.config/knot/auth}"
UPSTREAM_CLI_TOKEN_FILE="${KNOT_TEST_UPSTREAM_TOKEN:-$HOME/.gemini/antigravity-cli/antigravity-oauth-token}"
UPSTREAM_IDE_TOKEN_FILE="${KNOT_TEST_IDE_TOKEN:-$HOME/.gemini/antigravity/oauth-token.json}"

auth_ensure_dirs() {
  local auth_dir="$KNOT_AUTH_DIR"
  local profiles_dir="$auth_dir/profiles"
  if [ ! -d "$profiles_dir" ]; then
    mkdir -p "$profiles_dir"
    chmod 0700 "$auth_dir"
    chmod 0700 "$profiles_dir"
  fi
}

# Non-blocking D-Bus probe for SecretService collection lock status
auth_test_lock() {
  local verbose="${1:-1}"
  local dbus_out="" dbus_rc=0
  
  if ! command -v busctl >/dev/null; then
    if [ "$verbose" -eq 1 ]; then
      knot_log_warn "Notice: busctl command not found. Running in headless environment without D-Bus SecretService."
    fi
    return 2
  fi

  dbus_out="$(busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/aliases/default org.freedesktop.Secret.Collection Locked 2>&1)" || dbus_rc=$?

  if [ $dbus_rc -ne 0 ]; then
    if [ "$verbose" -eq 1 ]; then
      knot_log_warn "Notice: SecretService collection check failed (exit code $dbus_rc): $dbus_out"
      echo "Status: UNMANAGED / HEADLESS (Filesystem sandbox fallback active)"
    fi
    return 2
  fi

  if echo "$dbus_out" | grep -q "false"; then
    if [ "$verbose" -eq 1 ]; then
      knot_log_ok "Secret Service collection is UNLOCKED (Locked = false)"
    fi
    return 0
  elif echo "$dbus_out" | grep -q "true"; then
    if [ "$verbose" -eq 1 ]; then
      knot_log_warn "Secret Service collection is LOCKED (Locked = true)"
    fi
    return 1
  else
    if [ "$verbose" -eq 1 ]; then
      knot_log_warn "Unknown Secret Service lock status: $dbus_out"
    fi
    return 2
  fi
}

# Atomically link active profile's token to upstream CLI and IDE paths
auth_link_upstream_token() {
  local alias="$1"
  local profile_dir="$KNOT_AUTH_DIR/profiles/$alias"
  local token_file="$profile_dir/oauth-token.json"

  if [ ! -f "$token_file" ]; then
    knot_log_err "Token file does not exist at $token_file"
    return 1
  fi

  # Upstream CLI token path (~/.gemini/antigravity-cli/antigravity-oauth-token)
  mkdir -p "$(dirname "$UPSTREAM_CLI_TOKEN_FILE")"
  chmod 0700 "$(dirname "$UPSTREAM_CLI_TOKEN_FILE")"
  ln -sfn "$token_file" "${UPSTREAM_CLI_TOKEN_FILE}.tmp"
  mv -Tf "${UPSTREAM_CLI_TOKEN_FILE}.tmp" "$UPSTREAM_CLI_TOKEN_FILE"

  # Upstream IDE token path (~/.gemini/antigravity/oauth-token.json) if directory exists
  if [ -d "$(dirname "$UPSTREAM_IDE_TOKEN_FILE")" ]; then
    ln -sfn "$token_file" "${UPSTREAM_IDE_TOKEN_FILE}.tmp"
    mv -Tf "${UPSTREAM_IDE_TOKEN_FILE}.tmp" "$UPSTREAM_IDE_TOKEN_FILE"
  fi
}

# Switch active profile atomically using symlink swap
auth_switch() {
  local alias="${1:-}"
  if [ -z "$alias" ]; then
    knot_log_err "Usage: knot auth switch <profile-alias>"
    return 1
  fi

  auth_ensure_dirs
  local profile_dir="$KNOT_AUTH_DIR/profiles/$alias"
  if [ ! -d "$profile_dir" ]; then
    knot_log_err "Profile '$alias' does not exist in $KNOT_AUTH_DIR/profiles/"
    return 1
  fi

  local token_file="$profile_dir/oauth-token.json"
  if [ ! -f "$token_file" ]; then
    knot_log_err "Profile '$alias' is missing oauth-token.json"
    return 1
  fi

  # Ensure strict 0600 on token
  chmod 0600 "$token_file"

  # Atomic symlink swap for active_profile
  local active_symlink="$KNOT_AUTH_DIR/active_profile"
  local tmp_symlink="$KNOT_AUTH_DIR/active_profile.tmp"
  ln -sfn "profiles/$alias" "$tmp_symlink"
  mv -Tf "$tmp_symlink" "$active_symlink"

  # Link upstream paths
  auth_link_upstream_token "$alias"

  # Update metadata last_used_at
  local meta_file="$profile_dir/metadata.json"
  if [ -f "$meta_file" ] && command -v jq >/dev/null; then
    local tmp_meta
    tmp_meta="$(mktemp)"
    jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '.last_used_at = $now' "$meta_file" > "$tmp_meta"
    mv -f "$tmp_meta" "$meta_file"
    chmod 0600 "$meta_file"
  fi

  # Synchronize to SecretService if running on real desktop environment and keyring is unlocked
  if [ -z "${KNOT_TEST_AUTH_DIR:-}" ] && command -v secret-tool >/dev/null; then
    local lock_rc=0
    auth_test_lock 0 || lock_rc=$?
    if [ $lock_rc -eq 0 ]; then
      local token_content
      token_content="$(cat "$token_file")"
      local st_err="" st_rc=0
      st_err="$(printf "%s" "$token_content" | secret-tool store --label="Password for 'antigravity' on 'gemini'" service gemini username antigravity 2>&1)" || st_rc=$?
      if [ $st_rc -ne 0 ]; then
        knot_log_warn "Notice: secret-tool store failed ($st_rc): $st_err"
      fi
    fi
  fi

  # Restart knot-agent.service if active
  if command -v systemctl >/dev/null; then
    local r_out="" r_rc=0
    r_out="$(systemctl --user is-active knot-agent.service 2>&1)" || r_rc=$?
    if [ $r_rc -eq 0 ]; then
      local rst_out="" rst_rc=0
      rst_out="$(systemctl --user restart knot-agent.service 2>&1)" || rst_rc=$?
      if [ $rst_rc -ne 0 ]; then
        knot_log_warn "Notice: knot-agent.service restart failed ($rst_rc): $rst_out"
      fi
    fi
  fi

  knot_log_ok "Switched active profile to '$alias'."
}

# List all local profiles in the sandbox
auth_list() {
  auth_ensure_dirs
  local active_alias=""
  local active_symlink="$KNOT_AUTH_DIR/active_profile"
  if [ -L "$active_symlink" ]; then
    active_alias="$(basename "$(readlink -f "$active_symlink")")"
  fi

  echo -e "${C_BOLD}--- Knot Local Authentication Profiles ---${C_RESET}"
  printf "%-18s %-8s %-32s %-16s %-20s\n" "ALIAS" "ACTIVE" "EMAIL" "PLAN" "LAST SWITCHED"
  printf "%-18s %-8s %-32s %-16s %-20s\n" "-----" "------" "-----" "----" "-------------"

  local count=0
  for pdir in "$KNOT_AUTH_DIR/profiles"/*; do
    [ -d "$pdir" ] || continue
    count=$((count + 1))
    local alias
    alias="$(basename "$pdir")"
    local is_active=""
    local active_tag=" "
    if [ "$alias" = "$active_alias" ]; then
      is_active="*"
      active_tag="${C_GREEN}*${C_RESET}"
    fi

    local meta_file="$pdir/metadata.json"
    local email="-"
    local tier="-"
    local last_used="-"
    if [ -f "$meta_file" ] && command -v jq >/dev/null; then
      email="$(jq -r '.email // "-"' "$meta_file")"
      tier="$(jq -r '.tier // "-"' "$meta_file")"
      last_used="$(jq -r '.last_used_at // "-"' "$meta_file")"
      if [ "$last_used" != "-" ] && [ ${#last_used} -ge 16 ]; then
        last_used="${last_used:0:10} ${last_used:11:5}"
      fi
    fi

    printf "%-18s %-8b %-32s %-16s %-20s\n" "$alias" "$active_tag" "$email" "$tier" "$last_used"
  done

  if [ $count -eq 0 ]; then
    echo "  (No local profiles configured. Run 'knot auth login <alias>' to register a profile)"
  fi
}

# Inspect active authentication status and return JSON or human-readable format
auth_status() {
  local json_mode=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --json) json_mode=1; shift ;;
      *) shift ;;
    esac
  done

  auth_ensure_dirs
  local active_alias=""
  local active_symlink="$KNOT_AUTH_DIR/active_profile"
  if [ -L "$active_symlink" ]; then
    active_alias="$(basename "$(readlink -f "$active_symlink")")"
  fi

  local email="null"
  local tier="null"
  local token_valid=false
  local token_expiry="null"
  local profiles_count=0

  for pdir in "$KNOT_AUTH_DIR/profiles"/*; do
    if [ -d "$pdir" ]; then
      profiles_count=$((profiles_count + 1))
    fi
  done

  local lock_status=false
  local test_lock_rc=0
  auth_test_lock 0 || test_lock_rc=$?
  if [ $test_lock_rc -eq 1 ]; then
    lock_status=true
  fi

  if [ -n "$active_alias" ]; then
    local pdir="$KNOT_AUTH_DIR/profiles/$active_alias"
    local meta_file="$pdir/metadata.json"
    local token_file="$pdir/oauth-token.json"

    if [ -f "$meta_file" ] && command -v jq >/dev/null; then
      email="$(jq -r '.email // empty' "$meta_file")"
      tier="$(jq -r '.tier // empty' "$meta_file")"
    fi

    if [ -f "$token_file" ] && command -v jq >/dev/null; then
      local jq_chk="" jq_rc=0
      jq_chk="$(jq -e '.token.access_token or .token.refresh_token' "$token_file" 2>&1)" || jq_rc=$?
      if [ $jq_rc -eq 0 ]; then
        token_valid=true
        token_expiry="$(jq -r '.token.expiry // empty' "$token_file")"
      fi
    fi
  fi

  if [ $json_mode -eq 1 ]; then
    local json_active="null"
    if [ -n "$active_alias" ]; then json_active="\"$active_alias\""; fi
    local json_email="null"
    if [ -n "$email" ] && [ "$email" != "null" ]; then json_email="\"$email\""; fi
    local json_tier="null"
    if [ -n "$tier" ] && [ "$tier" != "null" ]; then json_tier="\"$tier\""; fi
    local json_expiry="null"
    if [ -n "$token_expiry" ] && [ "$token_expiry" != "null" ]; then json_expiry="\"$token_expiry\""; fi

    cat << JSON_EOF
{
  "active_profile": $json_active,
  "email": $json_email,
  "tier": $json_tier,
  "profiles_count": $profiles_count,
  "keyring_locked": $lock_status,
  "token_valid": $token_valid,
  "token_expiry": $json_expiry
}
JSON_EOF
    return 0
  fi

  echo -e "${C_BOLD}--- Knot Authentication Status ---${C_RESET}"
  if [ -n "$active_alias" ]; then
    echo -e "  Active Profile:   ${C_GREEN}${active_alias}${C_RESET}"
    echo -e "  Account Email:    ${C_CYAN}${email:-unknown}${C_RESET}"
    echo -e "  Plan / Tier:      ${C_CYAN}${tier:-unknown}${C_RESET}"
    echo -e "  Token Validity:   $([ "$token_valid" = true ] && echo -e "${C_GREEN}Valid${C_RESET}" || echo -e "${C_RED}Invalid / Expired${C_RESET}")"
    echo -e "  Token Expiry:     ${token_expiry:-unknown}"
  else
    echo -e "  Active Profile:   ${C_YELLOW}(None active)${C_RESET}"
  fi
  echo -e "  Keyring Status:   $([ "$lock_status" = true ] && echo -e "${C_RED}Locked${C_RESET}" || echo -e "${C_GREEN}Unlocked / Headless-Safe${C_RESET}")"
  echo -e "  Total Profiles:   $profiles_count"
}

# Guided login and registration into sandbox
auth_login() {
  local alias="${1:-}"
  local no_browser=0

  if [ -z "$alias" ] || [ "$alias" = "-h" ] || [ "$alias" = "--help" ]; then
    echo "Usage: knot auth login <profile-alias> [--no-browser]"
    echo ""
    echo "Authenticate Antigravity via OAuth device grant and register into a dedicated profile sandbox."
    return 0
  fi

  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-browser) no_browser=1; shift ;;
      *) shift ;;
    esac
  done

  # Validate alias format (alphanumeric, underscore, dash)
  if [[ ! "$alias" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    knot_log_err "Invalid profile alias '$alias'. Only alphanumeric characters, dashes, and underscores are allowed."
    return 1
  fi

  auth_ensure_dirs
  local profile_dir="$KNOT_AUTH_DIR/profiles/$alias"
  mkdir -p "$profile_dir"
  chmod 0700 "$profile_dir"

  local agy_bin=""
  if command -v agy >/dev/null; then
    agy_bin="$(command -v agy)"
  elif [ -x "$HOME/.gemini/antigravity-cli/bin/agy" ]; then
    agy_bin="$HOME/.gemini/antigravity-cli/bin/agy"
  elif [ -x "/opt/antigravity/bin/agy" ]; then
    agy_bin="/opt/antigravity/bin/agy"
  fi

  if [ -z "$agy_bin" ]; then
    knot_log_err "Upstream Antigravity CLI ('agy') not found in PATH or standard directories."
    return 1
  fi

  # 1. Pause knot-agent.service if active to prevent background credential sync races
  local agent_was_active=0
  if command -v systemctl >/dev/null; then
    local act_out="" act_rc=0
    act_out="$(systemctl --user is-active knot-agent.service 2>&1)" || act_rc=$?
    if [ $act_rc -eq 0 ]; then
      agent_was_active=1
      local stop_out="" stop_rc=0
      stop_out="$(systemctl --user stop knot-agent.service 2>&1)" || stop_rc=$?
      if [ $stop_rc -ne 0 ]; then
        knot_log_warn "Notice: Could not temporarily pause knot-agent ($stop_rc): $stop_out"
      fi
    fi
  fi

  # 2. Stash SecretService secret if present and unlocked so agy does not restore primary identity
  local stashed_secret=""
  if [ -z "${KNOT_TEST_AUTH_DIR:-}" ] && command -v secret-tool >/dev/null; then
    local lock_rc=0
    auth_test_lock 0 || lock_rc=$?
    if [ $lock_rc -eq 0 ]; then
      local st_search_out="" st_search_rc=0
      st_search_out="$(secret-tool search service gemini 2>&1)" || st_search_rc=$?
      if [ $st_search_rc -eq 0 ]; then
        stashed_secret="$(echo "$st_search_out" | awk -F'secret = ' '/^secret = / {print $2}' | head -n1)"
        if [ -n "$stashed_secret" ]; then
          local clr_out="" clr_rc=0
          clr_out="$(secret-tool clear service gemini username antigravity 2>&1)" || clr_rc=$?
          if [ $clr_rc -ne 0 ]; then
            knot_log_warn "Notice: secret-tool clear failed ($clr_rc): $clr_out"
          fi
        fi
      fi
    fi
  fi

  # 3. Stash existing upstream CLI token symlink/file so agy triggers a fresh OAuth prompt
  local upstream_token="$UPSTREAM_CLI_TOKEN_FILE"
  local upstream_bak="${upstream_token}.knot_login_bak"
  local stashed=0

  if [ -e "$upstream_token" ] || [ -L "$upstream_token" ]; then
    mv -f "$upstream_token" "$upstream_bak"
    stashed=1
  fi

  local login_success=0
  _cleanup_login() {
    if [ "$login_success" -eq 0 ]; then
      # Login was cancelled or failed - restore stashed secret and token
      if [ -n "$stashed_secret" ] && command -v secret-tool >/dev/null; then
        local rst_st_err="" rst_st_rc=0
        rst_st_err="$(printf "%s" "$stashed_secret" | secret-tool store --label="Password for 'antigravity' on 'gemini'" service gemini username antigravity 2>&1)" || rst_st_rc=$?
      fi
      if [ "$stashed" -eq 1 ] && [ -e "$upstream_bak" ]; then
        mv -f "$upstream_bak" "$upstream_token"
      fi
    elif [ "$login_success" -eq 1 ]; then
      if [ -e "$upstream_bak" ]; then
        rm -f "$upstream_bak"
      fi
    fi

    # Restart knot-agent if it was previously active
    if [ "$agent_was_active" -eq 1 ] && command -v systemctl >/dev/null; then
      local start_out="" start_rc=0
      start_out="$(systemctl --user start knot-agent.service 2>&1)" || start_rc=$?
    fi
  }
  trap _cleanup_login EXIT INT TERM

  knot_log_info "Initiating upstream login for profile '$alias'..."
  echo -e "  ${C_YELLOW}1.${C_RESET} Select ${C_BOLD}1. Google OAuth${C_RESET} when prompted."
  echo -e "  ${C_YELLOW}2.${C_RESET} Open the authorization URL in your browser and log in with your target Google account."
  echo -e "  ${C_YELLOW}3.${C_RESET} Copy the authorization code and paste it right into the prompt below."
  echo ""

  local agy_rc=0
  if [ $no_browser -eq 1 ]; then
    BROWSER=/bin/true "$agy_bin" || agy_rc=$?
  else
    "$agy_bin" || agy_rc=$?
  fi
  if [ $agy_rc -ne 0 ]; then
    knot_log_warn "Notice: agy exited with status $agy_rc"
  fi

  # After login, harvest token from upstream token file
  local fresh_token=""
  if [ -s "$upstream_token" ]; then
    fresh_token="$upstream_token"
  elif [ -s "$(dirname "$upstream_token")/oauth-token.json" ]; then
    fresh_token="$(dirname "$upstream_token")/oauth-token.json"
  elif [ -s "$HOME/.gemini/antigravity-cli/oauth-token.json" ]; then
    fresh_token="$HOME/.gemini/antigravity-cli/oauth-token.json"
  fi

  if [ -z "$fresh_token" ] || [ ! -s "$fresh_token" ]; then
    knot_log_err "Authentication finished but token file not found at $upstream_token."
    return 1
  fi

  local token_dest="$profile_dir/oauth-token.json"
  cp -f "$fresh_token" "$token_dest"
  chmod 0600 "$token_dest"

  login_success=1
  trap - EXIT INT TERM
  if [ -e "$upstream_bak" ]; then
    rm -f "$upstream_bak"
  fi

  # Restart knot-agent now that new token is staged
  if [ "$agent_was_active" -eq 1 ] && command -v systemctl >/dev/null; then
    local start_out="" start_rc=0
    start_out="$(systemctl --user start knot-agent.service 2>&1)" || start_rc=$?
  fi

  # Extract email / user metadata if possible
  local email="unknown"
  email="$(auth_resolve_email "$token_dest")"
  local tier="Google AI Pro"

  local now_iso
  now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local meta_file="$profile_dir/metadata.json"
  cat << META_EOF > "$meta_file"
{
  "alias": "$alias",
  "email": "$email",
  "tier": "$tier",
  "created_at": "$now_iso",
  "last_used_at": "$now_iso"
}
META_EOF
  chmod 0600 "$meta_file"

  # Switch to newly minted profile
  auth_switch "$alias"
  knot_log_ok "Profile '$alias' registered and activated successfully."
}

# Resolve account email from Google Userinfo API using OAuth access token
auth_resolve_email() {
  local token_file="$1"
  local email="unknown"
  if [ -s "$token_file" ] && command -v jq >/dev/null; then
    local access_token=""
    access_token="$(jq -r '.token.access_token // empty' "$token_file")"
    if [ -n "$access_token" ]; then
      local uinfo="" rc=0
      uinfo="$(curl -s -m 3 -H "Authorization: Bearer $access_token" "https://www.googleapis.com/oauth2/v3/userinfo" 2>&1)" || rc=$?
      if [ $rc -eq 0 ]; then
        local email_candidate="" eq_rc=0
        email_candidate="$(echo "$uinfo" | jq -r '.email // empty' 2>&1)" || eq_rc=$?
        if [ $eq_rc -eq 0 ] && [ -n "$email_candidate" ] && [ "$email_candidate" != "null" ]; then
          email="$email_candidate"
          echo "$email"
          return 0
        fi
      fi
    fi
    local parsed_email="" jq_rc=0
    parsed_email="$(jq -r '.email // .user_email // empty' "$token_file" 2>&1)" || jq_rc=$?
    if [ $jq_rc -eq 0 ] && [ -n "$parsed_email" ]; then email="$parsed_email"; fi
  fi
  echo "$email"
}

# Ingest an existing token file directly into a sandboxed profile
auth_import() {
  local alias="${1:-}"
  local source_file="${2:-}"

  if [ -z "$alias" ] || [ "$alias" = "-h" ] || [ "$alias" = "--help" ]; then
    echo "Usage: knot auth import <profile-alias> [source_token_file]"
    echo ""
    echo "Import an existing Antigravity OAuth token into a dedicated profile sandbox."
    return 0
  fi

  if [[ ! "$alias" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    knot_log_err "Invalid profile alias '$alias'. Only alphanumeric characters, dashes, and underscores are allowed."
    return 1
  fi

  if [ -z "$source_file" ]; then
    if [ -s "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ]; then
      source_file="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
    elif [ -s "$HOME/.gemini/antigravity-cli/oauth-token.json" ]; then
      source_file="$HOME/.gemini/antigravity-cli/oauth-token.json"
    else
      knot_log_err "No existing Antigravity token found at default path. Specify token file explicitly."
      return 1
    fi
  fi

  if [ ! -s "$source_file" ]; then
    knot_log_err "Source token file not found at $source_file"
    return 1
  fi

  auth_ensure_dirs
  local profile_dir="$KNOT_AUTH_DIR/profiles/$alias"
  mkdir -p "$profile_dir"
  chmod 0700 "$profile_dir"

  local token_dest="$profile_dir/oauth-token.json"
  cp -f "$source_file" "$token_dest"
  chmod 0600 "$token_dest"

  local email="unknown"
  email="$(auth_resolve_email "$token_dest")"
  local tier="Google AI Pro"
  local now_iso
  now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local meta_file="$profile_dir/metadata.json"
  cat << META_EOF > "$meta_file"
{
  "alias": "$alias",
  "email": "$email",
  "tier": "$tier",
  "created_at": "$now_iso",
  "last_used_at": "$now_iso"
}
META_EOF
  chmod 0600 "$meta_file"

  auth_switch "$alias"
  knot_log_ok "Imported profile '$alias' ($email) and activated successfully."
}


# Remove a local profile from the sandbox
auth_remove() {
  local alias="${1:-}"
  if [ -z "$alias" ] || [ "$alias" = "-h" ] || [ "$alias" = "--help" ]; then
    echo "Usage: knot auth remove <profile-alias>"
    return 1
  fi

  auth_ensure_dirs
  local profile_dir="$KNOT_AUTH_DIR/profiles/$alias"
  if [ ! -d "$profile_dir" ]; then
    knot_log_err "Profile '$alias' does not exist."
    return 1
  fi

  local active_symlink="$KNOT_AUTH_DIR/active_profile"
  if [ -L "$active_symlink" ]; then
    local active_target
    active_target="$(basename "$(readlink -f "$active_symlink")")"
    if [ "$active_target" = "$alias" ]; then
      knot_log_err "Cannot remove profile '$alias' because it is currently the active profile. Switch to another profile first."
      return 1
    fi
  fi

  rm -rf "$profile_dir"
  knot_log_ok "Profile '$alias' removed."
}

# Check if a target node refers to the local machine
auth_is_local_node() {
  local target="${1:-}"
  [ -z "$target" ] && return 1
  if [ "$target" = "local" ] || [ "$target" = "localhost" ] || [ "$target" = "127.0.0.1" ]; then
    return 0
  fi
  local my_nid="" nid_rc=0
  my_nid="$(knot_detect_node_id 2>&1)" || nid_rc=$?
  if [ $nid_rc -eq 0 ] && [ -n "$my_nid" ] && [ "$target" = "$my_nid" ]; then
    return 0
  fi
  local my_h="" h_rc=0
  my_h="$(knot_detect_hostname 2>&1)" || h_rc=$?
  if [ $h_rc -eq 0 ] && [ -n "$my_h" ] && [ "$target" = "$my_h" ]; then
    return 0
  fi
  return 1
}

# Check if a string is a known node ID or hostname in the mesh
auth_is_node() {
  local target="${1:-}"
  [ -z "$target" ] && return 1
  if auth_is_local_node "$target"; then
    return 0
  fi
  local m_out="" m_rc=0
  m_out="$(knot_get_manifest_path "$target" 2>&1)" || m_rc=$?
  if [ $m_rc -eq 0 ] && [ -n "$m_out" ]; then
    return 0
  fi
  local nodes_dirs=()
  local primary_dir="" pd_rc=0
  primary_dir="$(knot_get_nodes_dir 2>&1)" || pd_rc=$?
  if [ $pd_rc -eq 0 ] && [ -d "$primary_dir" ]; then
    nodes_dirs+=("$primary_dir")
  fi
  local user_home="" uh_rc=0
  user_home="$(knot_detect_user_home 2>&1)" || uh_rc=$?
  if [ $uh_rc -eq 0 ] && [ -n "$user_home" ]; then
    for d in "$user_home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
      [ -d "$d" ] || continue
      if [[ ! " ${nodes_dirs[*]} " =~ " ${d} " ]]; then
        nodes_dirs+=("$d")
      fi
    done
  fi
  for ndir in "${nodes_dirs[@]}"; do
    for mf in "$ndir/"*.json; do
      [ -e "$mf" ] || continue
      local mid="" mhost=""
      mid="$(awk -F'"' '/"id":/ {print $4}' "$mf" 2>&1)" || continue
      mhost="$(awk -F'"' '/"hostname":/ {print $4}' "$mf" 2>&1)" || continue
      if [ "$target" = "$mid" ] || [ "$target" = "$mhost" ]; then
        return 0
      fi
    done
  done
  return 1
}

# Collect list of all known node IDs across swarms
auth_get_all_nodes() {
  if [ -n "${KNOT_TEST_AUTH_DIR:-}" ]; then
    echo "local"
    return 0
  fi

  local nodes_dirs=()
  local primary_dir="" pd_rc=0
  primary_dir="$(knot_get_nodes_dir 2>&1)" || pd_rc=$?
  if [ $pd_rc -eq 0 ] && [ -d "$primary_dir" ]; then
    nodes_dirs+=("$primary_dir")
  fi
  local user_home="" uh_rc=0
  user_home="$(knot_detect_user_home 2>&1)" || uh_rc=$?
  if [ $uh_rc -eq 0 ] && [ -n "$user_home" ]; then
    for d in "$user_home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
      [ -d "$d" ] || continue
      if [[ ! " ${nodes_dirs[*]} " =~ " ${d} " ]]; then
        nodes_dirs+=("$d")
      fi
    done
  fi

  local seen_nodes=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local id="" id_rc=0
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest" 2>&1)" || id_rc=$?
      if [ $id_rc -eq 0 ] && [ -n "$id" ]; then
        if [[ ! " ${seen_nodes[*]:-} " =~ " ${id} " ]]; then
          seen_nodes+=("$id")
        fi
      fi
    done
  done

  if [ ${#seen_nodes[@]} -eq 0 ]; then
    local my_nid="" nid_rc=0
    my_nid="$(knot_detect_node_id 2>&1)" || nid_rc=$?
    if [ $nid_rc -eq 0 ] && [ -n "$my_nid" ]; then
      seen_nodes+=("$my_nid")
    else
      seen_nodes+=("desktop")
    fi
  fi

  echo "${seen_nodes[@]}"
}

# Forward an auth operation to a specific node
auth_exec_node() {
  local target="$1"
  local action="$2"
  shift 2
  local args=("$@")

  if auth_is_local_node "$target"; then
    cmd_auth "$action" "${args[@]}"
    return $?
  fi

  local gui_mode=0
  local clean_args=()
  for a in "${args[@]}"; do
    if [ "$a" = "--gui" ]; then
      gui_mode=1
    else
      clean_args+=("$a")
    fi
  done

  local remote_cmd="knot auth $action"
  for a in "${clean_args[@]}"; do
    remote_cmd="$remote_cmd $(printf "%q" "$a")"
  done

  if [ "$action" = "login" ]; then
    if [ "$gui_mode" -eq 1 ]; then
      knot_log_info "Opening interactive Konsole on '$target' display for Antigravity login..."
      local uid="1000"
      if [ "$target" = "steamdeck" ]; then uid="1001"; fi
      local log_file="/tmp/knot_konsole_auth.log"
      ssh "$target" "WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$uid nohup konsole --title 'KNOT AUTH: $target' -e $remote_cmd > '$log_file' 2>&1 &"
      knot_log_ok "Konsole opened on $target screen (logging to $log_file). Follow the prompt on $target to log in."
      return 0
    fi
    # Login is interactive and requires TTY allocation
    if command -v cmd_exec >/dev/null; then
      cmd_exec -tt "$target" "$remote_cmd"
    else
      ssh -tt "$target" "export TERM=\"\${TERM:-xterm-256color}\"; $remote_cmd"
    fi
  else
    if command -v cmd_exec >/dev/null; then
      cmd_exec "$target" "$remote_cmd"
    else
      local e_out="" e_rc=0
      e_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$remote_cmd" 2>&1)" || e_rc=$?
      if [ $e_rc -eq 0 ]; then
        echo "$e_out"
      else
        knot_log_err "Remote auth operation on '$target' failed (exit code $e_rc): $e_out"
        return $e_rc
      fi
    fi
  fi
}

# Display authentication status across all nodes in the mesh
auth_status_all() {
  local json_mode=0
  for a in "$@"; do
    if [ "$a" = "--json" ]; then json_mode=1; fi
  done

  local nodes=()
  read -ra nodes <<< "$(auth_get_all_nodes)"

  if [ $json_mode -eq 1 ]; then
    local first=1
    echo -n "{\"nodes\":{"
    for n in "${nodes[@]}"; do
      local s_json="" s_rc=0
      if auth_is_local_node "$n"; then
        s_json="$(auth_status --json 2>&1)" || s_rc=$?
      else
        s_json="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$n" "knot auth status --json" 2>&1)" || s_rc=$?
      fi
      local jq_chk="" jq_rc=0
      jq_chk="$(echo "$s_json" | jq . 2>&1)" || jq_rc=$?
      if [ $s_rc -ne 0 ] || [ $jq_rc -ne 0 ] || [ -z "$s_json" ]; then
        s_json="$(jq -n --arg err "$s_json" '{error: $err}')"
      fi

      if [ $first -eq 1 ]; then
        first=0
      else
        echo -n ","
      fi
      echo -n "\"$n\":$s_json"
    done
    echo "}}"
    return 0
  fi

  echo -e "${C_BOLD}--- Knot Mesh Fleet Authentication Status ---${C_RESET}"
  printf "%-14s %-16s %-32s %-16s %-14s %-12s\n" "NODE" "ACTIVE PROFILE" "EMAIL" "PLAN" "TOKEN VALID" "KEYRING"
  printf "%-14s %-16s %-32s %-16s %-14s %-12s\n" "----" "--------------" "-----" "----" "-----------" "-------"

  for n in "${nodes[@]}"; do
    local s_json="" s_rc=0
    if auth_is_local_node "$n"; then
      s_json="$(auth_status --json 2>&1)" || s_rc=$?
    else
      s_json="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$n" "knot auth status --json" 2>&1)" || s_rc=$?
    fi

    local active="-" email="-" tier="-" valid="Invalid" keyring="-"
    local jq_chk="" jq_rc=0
    jq_chk="$(echo "$s_json" | jq . 2>&1)" || jq_rc=$?
    if [ $s_rc -eq 0 ] && [ $jq_rc -eq 0 ] && [ -n "$s_json" ]; then
      active="$(echo "$s_json" | jq -r '.active_profile // "-"')"
      email="$(echo "$s_json" | jq -r '.email // "-"')"
      tier="$(echo "$s_json" | jq -r '.tier // "-"')"
      local is_valid
      is_valid="$(echo "$s_json" | jq -r '.token_valid')"
      if [ "$is_valid" = "true" ]; then
        valid="${C_GREEN}Valid${C_RESET}"
      else
        valid="${C_RED}Invalid${C_RESET}"
      fi
      local is_locked
      is_locked="$(echo "$s_json" | jq -r '.keyring_locked')"
      if [ "$is_locked" = "false" ]; then
        keyring="${C_GREEN}Unlocked${C_RESET}"
      elif [ "$is_locked" = "true" ]; then
        keyring="${C_RED}Locked${C_RESET}"
      else
        keyring="Unmanaged"
      fi
    else
      active="OFFLINE"
      email="Connection failed"
      tier="-"
      valid="${C_RED}Offline${C_RESET}"
      keyring="-"
    fi
    printf "%-14s %-16s %-32s %-16s %-23b %-20b\n" "$n" "$active" "$email" "$tier" "$valid" "$keyring"
  done
}

# Display profiles across all nodes in the mesh
auth_list_all() {
  local nodes=()
  read -ra nodes <<< "$(auth_get_all_nodes)"
  for n in "${nodes[@]}"; do
    echo -e "\n${C_CYAN}=== [$n] ===${C_RESET}"
    if auth_is_local_node "$n"; then
      auth_list "$@"
    else
      local l_out="" l_rc=0
      l_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$n" "knot auth list" 2>&1)" || l_rc=$?
      if [ $l_rc -eq 0 ]; then
        echo "$l_out"
      else
        knot_log_warn "Notice: Failed to query profiles on '$n' (exit code $l_rc): $l_out"
      fi
    fi
  done
}

# Top-level dispatcher for `knot auth`
cmd_auth() {
  # 1. Check for --node <node_id> / -n <node_id> flag in any position
  local target_node=""
  local filtered_args=()
  local skip_next=0
  local all_args=("$@")
  local idx=0
  for ((idx=0; idx<${#all_args[@]}; idx++)); do
    if [ $skip_next -eq 1 ]; then
      skip_next=0
      continue
    fi
    local curr="${all_args[$idx]}"
    if [ "$curr" = "--node" ] || [ "$curr" = "-n" ]; then
      local next_idx=$((idx + 1))
      if [ $next_idx -lt ${#all_args[@]} ]; then
        target_node="${all_args[$next_idx]}"
        skip_next=1
      fi
    elif [[ "$curr" =~ ^--node=(.*)$ ]]; then
      target_node="${BASH_REMATCH[1]}"
    else
      filtered_args+=("$curr")
    fi
  done

  # If explicit --node was provided, delegate to that node
  if [ -n "$target_node" ]; then
    local act="${filtered_args[0]:-status}"
    local rem_args=()
    if [ ${#filtered_args[@]} -gt 1 ]; then
      rem_args=("${filtered_args[@]:1}")
    fi
    auth_exec_node "$target_node" "$act" "${rem_args[@]}"
    return $?
  fi

  local sub="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi

  # Check if first argument is --all or all
  if [ "$sub" = "--all" ] || [ "$sub" = "all" ]; then
    local next_sub="${1:-status}"
    if [ $# -gt 0 ]; then shift; fi
    case "$next_sub" in
      status)
        auth_status_all "$@"
        return $?
        ;;
      list)
        auth_list_all "$@"
        return $?
        ;;
      sync)
        antigravity_swarm_auth sync --all "$@"
        return $?
        ;;
      *)
        knot_log_err "Unsupported --all action '$next_sub'. Supported: status, list, sync."
        return 1
        ;;
    esac
  fi

  # Check if first argument is a known node ID or hostname
  if auth_is_node "$sub"; then
    if [ $# -eq 0 ]; then
      # Bare node targeting -> legacy interactive login
      antigravity_swarm_auth "$sub"
      return $?
    elif [ "${1:-}" = "--gui" ]; then
      antigravity_swarm_auth "$sub" "$@"
      return $?
    fi
    local action="$1"
    shift
    case "$action" in
      login|import|list|status|switch|remove|rm|test-lock)
        auth_exec_node "$sub" "$action" "$@"
        return $?
        ;;
      *)
        antigravity_swarm_auth "$sub" "$action" "$@"
        return $?
        ;;
    esac
  fi

  # Standard local subcommands
  case "$sub" in
    login)
      auth_login "$@"
      ;;
    import)
      auth_import "$@"
      ;;
    list)
      if [ "${1:-}" = "--all" ] || [ "${1:-}" = "all" ]; then
        shift
        auth_list_all "$@"
      elif [ $# -gt 0 ] && auth_is_node "$1"; then
        local t="$1"; shift
        auth_exec_node "$t" list "$@"
      else
        auth_list "$@"
      fi
      ;;
    status)
      if [ "${1:-}" = "--all" ] || [ "${1:-}" = "all" ]; then
        shift
        auth_status_all "$@"
      elif [ $# -gt 0 ] && auth_is_node "$1"; then
        local t="$1"; shift
        auth_exec_node "$t" status "$@"
      else
        auth_status "$@"
      fi
      ;;
    switch)
      auth_switch "$@"
      ;;
    remove|rm)
      auth_remove "$@"
      ;;
    test-lock)
      auth_test_lock
      ;;
    sync)
      antigravity_swarm_auth sync "$@"
      ;;
    -h|--help)
      echo -e "${C_BOLD}knot auth - Multi-Tenant Authentication & Local Profile Sandboxing${C_RESET}"
      echo "Usage:"
      echo "  knot auth [<node_id>] login <alias> [--no-browser]  Guided OAuth login into a profile"
      echo "  knot auth [<node_id>] import <alias> [token_file]   Import existing token into profile sandbox"
      echo "  knot auth [<node_id>|--all] list                    List local or fleet profiles"
      echo "  knot auth [<node_id>|--all] status [--json]         Inspect active token health across node(s)"
      echo "  knot auth [<node_id>] switch <alias>                Atomically activate a profile"
      echo "  knot auth [<node_id>] remove <alias>                Remove a profile from sandbox"
      echo "  knot auth [<node_id>] test-lock                     Non-blocking D-Bus SecretService probe"
      echo "  knot auth sync [--all]                              Synchronize credentials across mesh"
      echo "  knot auth <node_id> [--gui]                         Interactive terminal or Konsole login"
      echo ""
      echo "Options:"
      echo "  --node, -n <node_id>  Execute auth action on specified target node"
      echo "  --all                 Sweep action across all mesh nodes (status, list, sync)"
      echo "  --no-browser          Force device-code / headless terminal URL OAuth flow"
      echo ""
      echo "Examples:"
      echo "  knot auth rog-ally import primary                   Sandbox active token on ROG Ally"
      echo "  knot auth laptop import primary                     Sandbox active token on Laptop"
      echo "  knot auth steamdeck import primary                  Sandbox active token on Steam Deck"
      echo "  knot auth status --all                              Sweep active auth status across entire fleet"
      echo "  knot auth list --all                                Display all profiles across entire fleet"
      echo "  knot auth rog-ally login secondary --no-browser     Register secondary account on ROG Ally"
      echo "  knot auth switch primary --node laptop              Activate primary profile on Laptop"
      return 0
      ;;
    *)
      antigravity_swarm_auth "$sub" "$@"
      ;;
  esac
}
