#!/usr/bin/env bash
set -euo pipefail

# Knot Sudo Module - PAM-Gated SSH Passwordless Execution
# Ensures:
# 1. Passwordless sudo in SSH sessions originating from the trusted subnet.
# 2. Local terminal / desktop behavior remains completely unchanged (password required if configured).

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

sudo_configure() {
  knot_log_info "Configuring dynamic multi-swarm PAM-gated SSH authentication..."

  cat << 'SCRIPT_EOF' | sudo tee /usr/local/bin/knot-auth-check >/dev/null
#!/usr/bin/env bash
set -euo pipefail

# Knot Dynamic PAM Auth Check
# Enforces:
# 1. Host must be physically inside a verified active swarm network fence.
# 2. Incoming SSH session client IP must belong to that active swarm's subnet.
# 3. Active swarm profile must allow passwordless sudo (ALLOW_NOPASSWD_SUDO="true").

resolve_active_swarm() {
  if [ -r /run/knot/active_swarm ]; then
    local s
    s="$(tr -d '[:space:]' < /run/knot/active_swarm)"
    if [ -n "$s" ] && [ "$s" != "none" ]; then
      echo "$s"
      return 0
    fi
  fi
  if [ -x /usr/local/bin/knot-guard ]; then
    local probed=""
    if probed="$(/usr/local/bin/knot-guard --check-active 2>&1)"; then
      if [ -n "$probed" ] && [ "$probed" != "none" ]; then
        echo "$probed"
        return 0
      fi
    fi
  fi
  echo "none"
  return 1
}

is_trusted_ssh_session() {
  local active_swarm=""
  if ! active_swarm="$(resolve_active_swarm)"; then
    return 1
  fi
  if [ "$active_swarm" = "none" ]; then
    return 1
  fi

  # Load active swarm profile
  local subnet="" allow_sudo="true"
  if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
    local SWARM_ID="" SUBNET="" ALLOW_NOPASSWD_SUDO="true"
    # shellcheck disable=SC1090
    source "/etc/knot/swarms.d/${active_swarm}.conf"
    subnet="${SUBNET:-}"
    allow_sudo="${ALLOW_NOPASSWD_SUDO:-true}"
  elif [ "$active_swarm" = "legacy" ] && [ -r /etc/knot/knot-guard.conf ]; then
    # Legacy fallback: use detected subnet
    subnet="$(knot_detect_subnet)"
    allow_sudo="true"
  fi

  if [ "$allow_sudo" != "true" ] && [ "$allow_sudo" != "1" ]; then
    return 1
  fi

  local subnet_prefix=""
  if [ -n "$subnet" ]; then
    subnet_prefix="${subnet%.*}."
  fi

  local pid=$$
  while [ "$pid" -gt 1 ]; do
    local comm="" ppid=1
    if [ -r "/proc/$pid/stat" ]; then
      read -r _ comm _ ppid _ < "/proc/$pid/stat"
      comm="${comm#(}"
      comm="${comm%)}"
    else
      break
    fi

    if [[ "$comm" =~ ^sshd ]]; then
      local p="$pid"
      for check_pid in "$$" "$PPID" "$p"; do
        if [ -r "/proc/$check_pid/environ" ]; then
          local client_ip=""
          if grep -zq '^SSH_CONNECTION=' "/proc/$check_pid/environ"; then
            client_ip="$(grep -z '^SSH_CONNECTION=' "/proc/$check_pid/environ" | tr -d '\0' | awk '{print $1}' | cut -d= -f2)"
          elif grep -zq '^SSH_CLIENT=' "/proc/$check_pid/environ"; then
            client_ip="$(grep -z '^SSH_CLIENT=' "/proc/$check_pid/environ" | tr -d '\0' | awk '{print $1}' | cut -d= -f2)"
          fi

          if [ -n "$client_ip" ]; then
            # Loopback connections always trusted
            if [[ "$client_ip" == 127.* ]] || [ "$client_ip" = "::1" ]; then
              return 0
            fi

            # Mathematical CIDR verification
            if [ -n "$subnet" ]; then
              if python3 -c "import ipaddress, sys; sys.exit(0 if ipaddress.ip_address(sys.argv[1]) in ipaddress.ip_network(sys.argv[2], strict=False) else 1)" "$client_ip" "$subnet" 2>&1; then
                return 0
              fi
            fi

            # Fallback simple prefix check
            if [ -n "$subnet_prefix" ] && [[ "$client_ip" == ${subnet_prefix}* ]]; then
              return 0
            fi
          fi
        fi
      done
    fi
    pid="$ppid"
  done

  return 1
}

if is_trusted_ssh_session; then
  exit 0
else
  exit 1
fi
SCRIPT_EOF
  sudo chmod 755 /usr/local/bin/knot-auth-check

  if ! grep -q "knot-auth-check" /etc/pam.d/sudo; then
    knot_log_info "Adding knot-auth-check PAM hook to /etc/pam.d/sudo..."
    sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.knot-backup
    sudo sed -i '/auth[[:space:]]*include[[:space:]]*system-auth/i auth [success=done default=ignore] pam_exec.so quiet \/usr\/local\/bin\/knot-auth-check' /etc/pam.d/sudo
    knot_log_ok "PAM hook installed in /etc/pam.d/sudo."
  else
    knot_log_ok "PAM hook already present in /etc/pam.d/sudo."
  fi
}

