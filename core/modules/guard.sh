#!/usr/bin/env bash
set -euo pipefail

# Knot Network Guard - Dynamically enables sshd only on verified home network

KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

guard_configure() {
  local target_mac="${1:-}"
  if [ -z "$target_mac" ]; then
    target_mac="$(knot_detect_gateway_mac)"
  fi

  local target_ssid="${2:-}"
  if [ -z "$target_ssid" ]; then
    target_ssid="$(knot_detect_active_ssid)"
  fi

  local swarm_id="${3:-home}"
  local swarm_name="${4:-Home Swarm}"
  local subnet
  subnet="$(knot_detect_subnet)"

  knot_log_info "Configuring Knot Multi-Swarm Network Guard..."
  sudo mkdir -p /etc/knot/swarms.d

  # Write swarm profile if not already present or if parameters provided
  local swarm_conf="/etc/knot/swarms.d/${swarm_id}.conf"
  if [ ! -f "$swarm_conf" ] || [ -n "${1:-}" ]; then
    cat << SWARM_EOF | sudo tee "$swarm_conf" >/dev/null
SWARM_ID="$swarm_id"
SWARM_NAME="$swarm_name"
ANCHOR_ID="desktop"
GATEWAY_MAC="${target_mac:-}"
SSID="${target_ssid:-}"
SUBNET="$subnet"
HUB_PORT=4242
ALLOW_NOPASSWD_SUDO="true"
SWARM_EOF
    knot_log_ok "Registered swarm profile: $swarm_conf"
  fi

  # Deploy multi-swarm aware knot-guard runner
  cat << 'SCRIPT_EOF' | sudo tee /usr/local/bin/knot-guard >/dev/null
#!/usr/bin/env bash
set -euo pipefail

# Multi-Swarm Network Guard
# Verifies current gateway MAC and SSID against /etc/knot/swarms.d/*.conf profiles.
# Enables sshd and auto-unlock strictly inside verified hardware fences.

STATE_DIR="/run/knot"
mkdir -p "$STATE_DIR"
ACTIVE_SWARM_FILE="$STATE_DIR/active_swarm"

detect_gateway_mac() {
  local gw
  gw="$(ip route show default | awk '/default/ {print $3}' | head -n1)"
  if [ -z "$gw" ]; then
    echo ""
    return 0
  fi
  if ! ip neigh show "$gw" | grep -q "lladdr"; then
    if ! ping -c 1 -W 1 "$gw" >/dev/null; then
      : # Initial probe warmup
    fi
  fi
  ip neigh show "$gw" | awk '{for(i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' | head -n1
}

detect_active_ssid() {
  if command -v nmcli >/dev/null; then
    nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}' | head -n1
  elif command -v iwgetid >/dev/null; then
    iwgetid -r
  fi
}

check_active_network() {
  local current_mac
  current_mac="$(detect_gateway_mac | tr '[:upper:]' '[:lower:]')"
  local current_ssid
  current_ssid="$(detect_active_ssid)"

  # 1. Check all swarm profiles in /etc/knot/swarms.d/*.conf
  if [ -d /etc/knot/swarms.d ]; then
    for conf in /etc/knot/swarms.d/*.conf; do
      [ -r "$conf" ] || continue
      local SWARM_ID="" GATEWAY_MAC="" SSID=""
      # shellcheck disable=SC1090
      source "$conf"

      local target_mac_lower
      target_mac_lower="$(echo "${GATEWAY_MAC:-}" | tr '[:upper:]' '[:lower:]')"

      # Match on Gateway MAC (Primary)
      if [ -n "$current_mac" ] && [ -n "$target_mac_lower" ] && [ "$current_mac" = "$target_mac_lower" ]; then
        echo "$SWARM_ID"
        return 0
      fi

      # Secondary Match on Wi-Fi SSID if MAC matching was inconclusive
      if [ -n "$current_ssid" ] && [ -n "${SSID:-}" ] && [ "$current_ssid" = "$SSID" ]; then
        echo "$SWARM_ID"
        return 0
      fi
    done
  fi

  # 2. Check legacy /etc/knot/knot-guard.conf fallback
  if [ -r /etc/knot/knot-guard.conf ]; then
    local TARGET_MAC="" TARGET_SSID=""
    # shellcheck disable=SC1091
    source /etc/knot/knot-guard.conf
    local target_mac_lower
    target_mac_lower="$(echo "${TARGET_MAC:-}" | tr '[:upper:]' '[:lower:]')"
    if [ -n "$current_mac" ] && [ -n "$target_mac_lower" ] && [ "$current_mac" = "$target_mac_lower" ]; then
      echo "legacy"
      return 0
    fi
  fi

  echo "none"
  return 1
}

# Subcommand: --check-active or status
if [ "${1:-}" = "--check-active" ] || [ "${1:-}" = "status" ]; then
  active="$(check_active_network)"
  if [ "$active" != "none" ]; then
    echo "$active"
    exit 0
  else
    echo "none"
    exit 1
  fi
fi

# Main Guard Reconciliation Cycle
active_swarm="$(check_active_network)"

if [ "$active_swarm" != "none" ]; then
  echo "$active_swarm" > "$ACTIVE_SWARM_FILE"
  logger -t knot-guard "Verified swarm network fence: [$active_swarm]. Ensuring sshd is active."

  if ! systemctl is-active --quiet sshd; then
    systemctl start sshd
  fi

  # Trigger auto-login check for Strands if Anchor is available
  if [ -x /usr/local/bin/knot ]; then
    /usr/local/bin/knot autologin check
  fi
else
  echo "none" > "$ACTIVE_SWARM_FILE"
  if systemctl is-active --quiet sshd; then
    logger -t knot-guard "Outside trusted swarm network fence. Stopping sshd for security."
    systemctl stop sshd
  fi
fi
SCRIPT_EOF
  sudo chmod 755 /usr/local/bin/knot-guard

  # Install NetworkManager dispatcher script
  sudo mkdir -p /etc/NetworkManager/dispatcher.d
  cat << 'DISP_EOF' | sudo tee /etc/NetworkManager/dispatcher.d/99-knot-guard.sh >/dev/null
#!/usr/bin/env bash
case "$2" in
  up|down|dhcp4-change)
    /usr/local/bin/knot-guard &
    ;;
esac
DISP_EOF
  sudo chmod 755 /etc/NetworkManager/dispatcher.d/99-knot-guard.sh

  # Install systemd service & timer
  cat << 'UNIT_EOF' | sudo tee /etc/systemd/system/knot-guard.service >/dev/null
[Unit]
Description=Knot Multi-Swarm Network Guard
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/knot-guard
UNIT_EOF

  cat << 'TIMER_EOF' | sudo tee /etc/systemd/system/knot-guard.timer >/dev/null
[Unit]
Description=Periodic Check for Knot Network Guard
After=network.target

[Timer]
OnBootSec=10s
OnUnitActiveSec=60s

[Install]
WantedBy=timers.target
TIMER_EOF

  sudo systemctl daemon-reload
  sudo systemctl enable --now knot-guard.timer
  sudo /usr/local/bin/knot-guard
  knot_log_ok "Knot Multi-Swarm Network Guard deployed and active."
}

