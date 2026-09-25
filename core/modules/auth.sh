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

  knot_log_info "Initiating upstream login for profile '$alias'..."
  if [ $no_browser -eq 1 ]; then
    "$agy_bin" login --no-browser || "$agy_bin"
  else
    "$agy_bin"
  fi

  # After login, harvest token from upstream token file
  local upstream_token="$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
  if [ ! -s "$upstream_token" ]; then
    upstream_token="$HOME/.gemini/antigravity-cli/oauth-token.json"
  fi

  if [ ! -s "$upstream_token" ]; then
    knot_log_err "Authentication finished but token file not found at $upstream_token."
    return 1
  fi

  local token_dest="$profile_dir/oauth-token.json"
  cp -f "$upstream_token" "$token_dest"
  chmod 0600 "$token_dest"

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

# Top-level dispatcher for `knot auth`
cmd_auth() {
  local sub="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi

  case "$sub" in
    login)
      auth_login "$@"
      ;;
    import)
      auth_import "$@"
      ;;
    list)
      auth_list "$@"
      ;;
    status)
      auth_status "$@"
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
      # Preserves backward compatibility with legacy `knot auth sync [--all]`
      antigravity_swarm_auth sync "$@"
      ;;
    -h|--help)
      echo -e "${C_BOLD}knot auth - Multi-Tenant Authentication & Local Profile Sandboxing${C_RESET}"
      echo "Usage:"
      echo "  knot auth login <profile-alias> [--no-browser]  Guided OAuth login into a dedicated profile"
      echo "  knot auth list                                  List local profiles and active selection"
      echo "  knot auth status [--json]                       Inspect active token health & lock state"
      echo "  knot auth switch <profile-alias>                Atomically activate a local profile"
      echo "  knot auth remove <profile-alias>                Remove a local profile from sandbox"
      echo "  knot auth test-lock                             Non-blocking D-Bus SecretService probe"
      echo "  knot auth sync [--all]                          Synchronize credentials across mesh"
      echo "  knot auth [node_id] [--gui]                     Remote interactive login via SSH"
      return 0
      ;;
    *)
      # Fallback to existing node-specific interactive auth if argument is a node name or --gui
      antigravity_swarm_auth "$sub" "$@"
      ;;
  esac
}
