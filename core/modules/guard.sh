#!/usr/bin/env bash
set -euo pipefail

# Knot Network Guard - Multi-Swarm Hardware Fencing & Roaming Engine
# Enforces gateway MAC & BSSID fencing with Ethernet-over-Wi-Fi priority,
# 4-second debounce hysteresis, and graceful roaming standalone mode.

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
  local anchor_id="${5:-desktop}"
  local anchor_host="${6:-desktop.local}"
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
ANCHOR_ID="$anchor_id"
ANCHOR_HOST="$anchor_host"
GATEWAY_MAC="${target_mac:-}"
GATEWAY_MACS="${target_mac:-}"
SSID="${target_ssid:-}"
SUBNET="$subnet"
HUB_PORT=4242
ALLOW_NOPASSWD_SUDO="true"
ALLOW_DESKFLOW_KVM="true"
SWARM_EOF
    knot_log_ok "Registered swarm profile: $swarm_conf"
  fi

  # Deploy multi-swarm aware knot-guard runner
  cat << 'SCRIPT_EOF' | sudo tee /usr/local/bin/knot-guard >/dev/null
#!/usr/bin/env bash
set -euo pipefail

# Multi-Swarm Network Guard Runner
# Hardware interface arbitration: Ethernet prioritized over Wi-Fi.
# Debounce hysteresis: 4 seconds before confirming network transition.
# Graceful standalone: sshd kept running key-only; KVM & sudo locked.

STATE_DIR="/run/knot"
mkdir -p "$STATE_DIR"
ACTIVE_SWARM_FILE="$STATE_DIR/active_swarm"
PID_FILE="$STATE_DIR/guard_debounce.pid"

detect_priority_gateway() {
  # 1. Prioritize wired Ethernet default route
  local wired_gw=""
  local ifaces=""
  local link_out=""
  if link_out="$(ip -o link show 2>&1)"; then
    ifaces="$(echo "$link_out" | awk -F': ' '$2 ~ /^(en|eth)/ {print $2}')"
  fi
  for iface in $ifaces; do
    local g=""
    local r_out=""
    if r_out="$(ip -4 route show default dev "$iface" 2>&1)"; then
      g="$(echo "$r_out" | awk '{print $3}' | head -n1)"
    fi
    if [ -n "$g" ]; then
      wired_gw="$g"
      break
    fi
  done
  if [ -n "$wired_gw" ]; then
    echo "$wired_gw"
    return 0
  fi

  # 2. Fall back to wireless default route
  local wireless_gw=""
  local wifaces=""
  if [ -n "$link_out" ]; then
    wifaces="$(echo "$link_out" | awk -F': ' '$2 ~ /^(wl)/ {print $2}')"
  fi
  for iface in $wifaces; do
    local g=""
    local r_out=""
    if r_out="$(ip -4 route show default dev "$iface" 2>&1)"; then
      g="$(echo "$r_out" | awk '{print $3}' | head -n1)"
    fi
    if [ -n "$g" ]; then
      wireless_gw="$g"
      break
    fi
  done
  if [ -n "$wireless_gw" ]; then
    echo "$wireless_gw"
    return 0
  fi

  # 3. Generic default route fallback
  local def_route=""
  if def_route="$(ip -4 route show default 2>&1)"; then
    echo "$def_route" | awk '{print $3}' | head -n1
  fi
}

detect_gateway_mac() {
  local gw
  gw="$(detect_priority_gateway)"
  if [ -z "$gw" ]; then
    echo ""
    return 0
  fi

  # Warm ARP cache if neighbor is not yet resolved
  local neigh_out=""
  if neigh_out="$(ip neigh show "$gw" 2>&1)"; then
    if ! echo "$neigh_out" | grep -q "lladdr"; then
      local ping_out=""
      if ! ping_out="$(ping -c 1 -W 1 "$gw" 2>&1)"; then
        logger -t knot-guard "Dispatched ARP warmup ping to $gw: $ping_out"
      fi
    fi
  fi
  if neigh_out="$(ip neigh show "$gw" 2>&1)"; then
    echo "$neigh_out" | awk '{for(i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' | head -n1
  fi
}

detect_active_ssid() {
  if command -v nmcli >/dev/null; then
    local nm_out=""
    if nm_out="$(nmcli -t -f active,ssid dev wifi 2>&1)"; then
      echo "$nm_out" | awk -F: '$1=="yes"{print $2}' | head -n1
    fi
  elif command -v iwgetid >/dev/null; then
    local iw_out=""
    if iw_out="$(iwgetid -r 2>&1)"; then
      echo "$iw_out"
    fi
  fi
}

check_active_network() {
  local current_mac
  current_mac="$(detect_gateway_mac | tr '[:upper:]' '[:lower:]')"
  local current_ssid
  current_ssid="$(detect_active_ssid)"

  local conf_files=()
  if [ -d /etc/knot/swarms.d ]; then
    for f in /etc/knot/swarms.d/*.conf; do
      [ -r "$f" ] && conf_files+=("$f")
    done
  fi
  for f in /home/*/.config/knot/swarms/*/swarm.conf; do
    [ -r "$f" ] && conf_files+=("$f")
  done

  for conf in "${conf_files[@]}"; do
    local SWARM_ID="" GATEWAY_MAC="" GATEWAY_MACS="" SSID=""
    # shellcheck disable=SC1090
    source "$conf"

    local target_macs="${GATEWAY_MACS:-$GATEWAY_MAC}"

    # Primary match: Gateway MAC
    if [ -n "$current_mac" ] && [ -n "$target_macs" ]; then
      for m in $(echo "$target_macs" | tr ',' ' '); do
        if [ "$current_mac" = "$(echo "$m" | tr '[:upper:]' '[:lower:]')" ]; then
          echo "$SWARM_ID"
          return 0
        fi
      done
    fi

    # Secondary match: Wi-Fi SSID
    if [ -n "$current_ssid" ] && [ -n "${SSID:-}" ] && [ "$current_ssid" = "$SSID" ]; then
      echo "$SWARM_ID"
      return 0
    fi
  done

  echo "none"
  return 0
}

sync_active_swarm() {
  local target_swarm="$1"
  echo "$target_swarm" > "$ACTIVE_SWARM_FILE"

  for udir in /home/*; do
    [ -d "$udir" ] || continue
    local sdir="$udir/.local/state/knot"
    if [ -d "$sdir" ]; then
      local uname
      uname="$(basename "$udir")"
      if [ "$(id -u)" -eq 0 ]; then
        echo "$target_swarm" > "$sdir/active_swarm.tmp"
        chown "$uname":"$uname" "$sdir/active_swarm.tmp"
        mv -f "$sdir/active_swarm.tmp" "$sdir/active_swarm"
      elif [ "${USER:-}" = "$uname" ]; then
        echo "$target_swarm" > "$sdir/active_swarm.tmp"
        mv -f "$sdir/active_swarm.tmp" "$sdir/active_swarm"
      fi
    fi
  done
}

is_local_anchor() {
  local s_id="$1"
  local my_host=""
  if [ -r /etc/hostname ]; then
    my_host="$(tr -d '[:space:]' < /etc/hostname)"
  elif command -v hostname >/dev/null; then
    my_host="$(hostname)"
  fi

  local swarm_conf=""
  if [ -r "/etc/knot/swarms.d/${s_id}.conf" ]; then
    swarm_conf="/etc/knot/swarms.d/${s_id}.conf"
  else
    for u_conf in /home/*/.config/knot/swarms/${s_id}/swarm.conf; do
      if [ -r "$u_conf" ]; then
        swarm_conf="$u_conf"
        break
      fi
    done
  fi

  local anchor_id="" anchor_host=""
  if [ -n "$swarm_conf" ] && [ -r "$swarm_conf" ]; then
    anchor_id="$(awk -F= '/^ANCHOR_ID=/ {print $2}' "$swarm_conf" | tr -d '"'\'' ')"
    anchor_host="$(awk -F= '/^ANCHOR_HOST=/ {print $2}' "$swarm_conf" | tr -d '"'\'' ')"
  fi

  if [ -n "$anchor_host" ] && [ "$my_host" = "$anchor_host" ]; then
    return 0
  fi
  if [ -n "$anchor_id" ] && [ "$my_host" = "$anchor_id" ]; then
    return 0
  fi

  local nodes_dirs=""
  if [ -d "/etc/knot/swarms.d/${s_id}/nodes" ]; then
    nodes_dirs="/etc/knot/swarms.d/${s_id}/nodes"
  fi
  for u_ndir in /home/*/.config/knot/swarms/${s_id}/nodes; do
    if [ -d "$u_ndir" ]; then
      nodes_dirs="$nodes_dirs $u_ndir"
    fi
  done

  for ndir in $nodes_dirs; do
    if [ -d "$ndir" ] && [ -n "$anchor_id" ] && [ -r "$ndir/${anchor_id}.json" ]; then
      local m_host=""
      m_host="$(awk -F'"' '/"hostname":/ {print $4}' "$ndir/${anchor_id}.json")"
      if [ "$m_host" = "$my_host" ]; then
        return 0
      fi
      if grep -q "\"$my_host\"" "$ndir/${anchor_id}.json"; then
        return 0
      fi
    fi
  done

  return 1
}

run_user_service_cmd() {
  local uid="$1"
  local uname="$2"
  shift 2
  local cmd_str="$*"
  local cmd_out=""
  if [ "$(id -u)" -eq "$uid" ]; then
    if ! cmd_out="$("$@" 2>&1)"; then
      logger -t knot-guard -- "Notice executing $cmd_str for $uname: $cmd_out"
    fi
  else
    if ! cmd_out="$(sudo -u "$uname" XDG_RUNTIME_DIR="/run/user/$uid" "$@" 2>&1)"; then
      logger -t knot-guard -- "Notice executing $cmd_str for $uname: $cmd_out"
    fi
  fi
}

dispatch_user_services() {
  local role="$1" # "anchor", "strand", or "standalone"

  local uids=""
  for udir in /run/user/*; do
    [ -d "$udir" ] || continue
    local u
    u="$(basename "$udir")"
    if [ "$u" -ge 1000 ]; then
      uids="$uids $u"
    fi
  done

  local cur_u
  cur_u="$(id -u)"
  if [ "$cur_u" -ge 1000 ]; then
    if ! echo "$uids" | grep -qw "$cur_u"; then
      uids="$uids $cur_u"
    fi
  fi

  for u in $uids; do
    local uname=""
    if uname="$(id -nu "$u" 2>&1)"; then
      case "$role" in
        anchor)
          run_user_service_cmd "$u" "$uname" systemctl --user start knot-hub.service
          run_user_service_cmd "$u" "$uname" systemctl --user restart knot-deskflow.service
          run_user_service_cmd "$u" "$uname" systemctl --user start knot-stripd.service
          ;;
        strand)
          run_user_service_cmd "$u" "$uname" systemctl --user stop knot-hub.service
          run_user_service_cmd "$u" "$uname" systemctl --user restart knot-deskflow.service
          run_user_service_cmd "$u" "$uname" systemctl --user stop knot-stripd.service
          ;;
        standalone)
          run_user_service_cmd "$u" "$uname" systemctl --user stop knot-hub.service
          run_user_service_cmd "$u" "$uname" systemctl --user stop knot-deskflow.service
          run_user_service_cmd "$u" "$uname" systemctl --user stop knot-stripd.service
          ;;
      esac
    fi
  done
}

reconcile_state() {
  local active_swarm
  active_swarm="$(check_active_network)"

  if [ "$active_swarm" != "none" ]; then
    sync_active_swarm "$active_swarm"
    logger -t knot-guard "Verified swarm network fence: [$active_swarm]."

    # Ensure OpenSSH is active for mesh operations
    if ! systemctl is-active --quiet sshd; then
      local sshd_err=""
      if ! sshd_err="$(systemctl start sshd 2>&1)"; then
        logger -t knot-guard "Failed to start sshd: $sshd_err"
      fi
    fi

    # Trigger autologin check if Anchor is reachable
    if [ -x /usr/local/bin/knot ]; then
      local auto_out=""
      if ! auto_out="$(/usr/local/bin/knot autologin check 2>&1)"; then
        logger -t knot-guard "Autologin check notice: $auto_out"
      fi
    fi

    # Dynamic role orchestration (Anchor Server vs Strand Client)
    if is_local_anchor "$active_swarm"; then
      logger -t knot-guard "Node is ANCHOR for swarm [$active_swarm]. Orchestrating Hub & Deskflow Server."
      dispatch_user_services "anchor"
    else
      logger -t knot-guard "Node is STRAND for swarm [$active_swarm]. Orchestrating Deskflow Client."
      dispatch_user_services "strand"
    fi
  else
    sync_active_swarm "none"
    logger -t knot-guard "Outside trusted swarm network fence. Transitioning to Graceful Standalone mode."

    # Graceful Standalone Mode:
    # 1. sshd remains RUNNING (key-only with UFW rate limiting)
    if ! systemctl is-active --quiet sshd; then
      local sshd_err=""
      if ! sshd_err="$(systemctl start sshd 2>&1)"; then
        logger -t knot-guard "Failed to ensure sshd in standalone mode: $sshd_err"
      fi
    fi

    # 2. Stop Deskflow & Hub across all sessions
    dispatch_user_services "standalone"
  fi
}

# Subcommands: --check-active or status
if [ "${1:-}" = "--check-active" ] || [ "${1:-}" = "status" ]; then
  active="$(check_active_network)"
  echo "$active"
  if [ "$active" != "none" ]; then
    exit 0
  else
    exit 1
  fi
fi

# Immediate evaluation flag (skip debounce)
if [ "${1:-}" = "--immediate" ]; then
  reconcile_state
  exit 0
fi

# Debounce hysteresis engine: 4-second delay before steady-state reconciliation
debounce_and_reconcile() {
  if [ -f "$PID_FILE" ] && [ -r "$PID_FILE" ]; then
    local old_pid
    old_pid="$(< "$PID_FILE")"
    if [ -n "$old_pid" ]; then
      local check_probe=""
      if check_probe="$(kill -0 "$old_pid" 2>&1)"; then
        local kill_probe=""
        if ! kill_probe="$(kill "$old_pid" 2>&1)"; then
          logger -t knot-guard "Notice terminating previous debounce pid $old_pid: $kill_probe"
        fi
      fi
    fi
  fi

  echo $$ > "$PID_FILE"
  sleep 4
  rm -f "$PID_FILE"
  reconcile_state
}

debounce_and_reconcile
SCRIPT_EOF
  sudo chmod 755 /usr/local/bin/knot-guard

  # Install NetworkManager dispatcher script with debounce invocation
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
ExecStart=/usr/local/bin/knot-guard --immediate
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
  sudo /usr/local/bin/knot-guard --immediate
  knot_log_ok "Knot Multi-Swarm Network Guard deployed and active."
}
