#!/usr/bin/env bash
set -euo pipefail

# Knot Core Library - System Inspection & Utilities

C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_PURPLE='\033[0;35m'
C_GRAY='\033[90m'
C_DIM='\033[2m'
C_BOLD='\033[1m'

knot_log_info() { echo -e "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
knot_log_ok()   { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
knot_log_warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
knot_log_err()  { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; }

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
export KNOT_VERSION="${KNOT_VERSION:-1.0.0-rc3}"


knot_detect_user() {
  if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
    echo "${SUDO_USER}"
  else
    whoami
  fi
}

knot_detect_user_home() {
  if [ -n "${HOME:-}" ]; then
    echo "$HOME"
    return 0
  fi
  local u
  u="$(knot_detect_user)"
  eval echo "~${u}"
}

knot_detect_sshd_port() {
  local p=""
  if [ -f "/etc/ssh/sshd_config.d/10-knot-keyonly.conf" ]; then
    p="$(awk '/^[[:space:]]*Port[[:space:]]+[0-9]+/ {print $2}' /etc/ssh/sshd_config.d/10-knot-keyonly.conf)"
  fi
  if [ -z "$p" ] && command -v sshd >/dev/null; then
    if sudo -n true; then
      p="$(sudo -n /usr/bin/sshd -T | awk 'tolower($1) == "port" {print $2}' | head -n1)"
    fi
  fi
  if [ -n "$p" ]; then
    echo "$p"
  else
    echo "22"
  fi
}

knot_detect_gateway() {
  ip route show default | awk '/default/ {print $3}' | head -n1
}

knot_detect_gateway_mac() {
  local gw
  gw="$(knot_detect_gateway)"
  if [ -z "$gw" ]; then
    echo ""
    return 0
  fi
  # Warm ARP cache with a single ping probe if neighbor is not yet resolved
  if ! ip neigh show "$gw" | grep -q "lladdr"; then
    if ! ping -c 1 -W 1 "$gw" >/dev/null; then
      : # Initial ping warmup might receive no reply, neigh table will still be inspected
    fi
  fi
  ip neigh show "$gw" | awk '{for(i=1;i<=NF;i++) if ($i=="lladdr") print $(i+1)}' | head -n1
}

knot_detect_active_ssid() {
  if command -v nmcli >/dev/null; then
    nmcli -t -f active,ssid dev wifi | awk -F: '$1=="yes"{print $2}' | head -n1
  elif command -v iwgetid >/dev/null; then
    iwgetid -r
  fi
}

knot_detect_subnet() {
  local gw
  gw="$(knot_detect_gateway)"
  if [ -n "$gw" ]; then
    echo "${gw%.*}.0/24"
  else
    local local_ip
    local_ip="$(ip -4 addr show scope global | awk '$1 == "inet" {print $2; exit}')"
    if [ -n "$local_ip" ]; then
      echo "${local_ip%/*}/24"
    else
      echo "127.0.0.1/32"
    fi
  fi
}

knot_detect_lan_ip() {
  local gw=""
  local gw_out=""
  if gw_out="$(ip -4 route show default 2>&1)"; then
    gw="$(echo "$gw_out" | awk '{print $3}' | head -n1)"
  fi
  if [ -n "$gw" ]; then
    local src_out=""
    if src_out="$(ip route get "$gw" 2>&1)"; then
      local ip_found
      ip_found="$(echo "$src_out" | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1)"
      if [ -n "$ip_found" ]; then
        echo "$ip_found"
        return 0
      fi
    fi
  fi

  local fallback_out=""
  if fallback_out="$(ip -4 addr show scope global 2>&1)"; then
    local fb_ip
    fb_ip="$(echo "$fallback_out" | awk '$1 == "inet" {print $2; exit}' | cut -d/ -f1)"
    if [ -n "$fb_ip" ]; then
      echo "$fb_ip"
      return 0
    fi
  fi

  echo "127.0.0.1"
}

knot_detect_network_interfaces() {
  local ifaces
  ifaces="$(ip -o link show | awk -F': ' '{print $2}' | grep -v -E '^(lo|docker|virbr|veth|br-|waydroid)')"
  for iface in $ifaces; do
    local mac=""
    if [ -r "/sys/class/net/$iface/address" ]; then
      mac="$(< "/sys/class/net/$iface/address")"
    fi
    local type="ethernet"
    if [ -d "/sys/class/net/$iface/wireless" ]; then
      type="wifi"
    fi
    local ip
    ip="$(ip -4 -o addr show dev "$iface" | awk '{print $4}' | cut -d/ -f1 | head -n1)"
    if [ -n "$mac" ] && [ "$mac" != "00:00:00:00:00:00" ]; then
      echo "$iface|$type|$mac|$ip"
    fi
  done
}

knot_detect_hostname() {
  local h=""
  if command -v uname >/dev/null; then
    h="$(uname -n)"
  fi
  if [ -z "$h" ] && command -v hostnamectl >/dev/null; then
    local out=""
    if out="$(hostnamectl --static)"; then
      h="$out"
    fi
  fi
  if [ -z "$h" ] && [ -r /etc/hostname ]; then
    h="$(tr -d '[:space:]' < /etc/hostname)"
  fi
  if [ -z "$h" ] && command -v hostname >/dev/null; then
    h="$(hostname)"
  fi
  if [ -n "$h" ]; then
    echo "$h"
  else
    echo "localhost"
  fi
}

knot_detect_firewalls() {
  local found=()
  if command -v ufw >/dev/null; then
    local ufw_status
    if ufw_status="$(sudo -n ufw status 2>/dev/null)"; then
      if echo "$ufw_status" | grep -q "Status: active"; then
        found+=("ufw")
      fi
    fi
  fi
  if command -v firewall-cmd >/dev/null; then
    if sudo -n firewall-cmd --state >/dev/null 2>&1; then
      found+=("firewalld")
    fi
  fi
  if [ ${#found[@]} -eq 0 ]; then
    if command -v nft >/dev/null && sudo -n nft list ruleset 2>/dev/null | grep -q "table"; then
      found+=("nftables")
    elif command -v iptables >/dev/null && sudo -n iptables -L -n 2>/dev/null | grep -q "Chain"; then
      found+=("iptables")
    else
      found+=("none")
    fi
  fi
  echo "${found[*]}"
}

# Returns list of existing swarm config file paths
knot_list_swarm_profiles() {
  local files=()
  if [ -d "/etc/knot/swarms.d" ]; then
    for f in /etc/knot/swarms.d/*.conf; do
      [ -e "$f" ] || continue
      files+=("$f")
    done
  fi
  local user_home
  user_home="$(knot_detect_user_home)"
  if [ -d "$user_home/.config/knot/swarms" ]; then
    for f in "$user_home/.config/knot/swarms/"*.conf; do
      [ -e "$f" ] || continue
      files+=("$f")
    done
  fi
  echo "${files[*]}"
}

# Returns active swarm ID (reads environment override, /run/knot/active_swarm, state dir, or first profile)
knot_get_active_swarm() {
  # 0. Explicit environment override
  if [ -n "${KNOT_ACTIVE_SWARM:-}" ]; then
    echo "$KNOT_ACTIVE_SWARM"
    return 0
  fi

  local run_dir="${KNOT_RUNTIME_DIR:-/run/knot}"

  # 1. System runtime fence file
  if [ -r "$run_dir/active_swarm" ]; then
    local s
    s="$(tr -d '[:space:]' < "$run_dir/active_swarm")"
    if [ -n "$s" ]; then
      echo "$s"
      return 0
    fi
  fi

  # 2. User state directory
  local user_home
  user_home="$(knot_detect_user_home)"
  local state_file="$user_home/.local/state/knot/active_swarm"
  if [ -r "$state_file" ]; then
    local s
    s="$(tr -d '[:space:]' < "$state_file")"
    if [ -n "$s" ]; then
      echo "$s"
      return 0
    fi
  fi

  # 3. Fallback to user swarm directories
  if [ -d "$user_home/.config/knot/swarms" ]; then
    for f in "$user_home/.config/knot/swarms"/*/swarm.conf; do
      [ -e "$f" ] || continue
      local base
      base="$(basename "$(dirname "$f")")"
      echo "$base"
      return 0
    done
  fi

  # 4. Fallback to first available system profile
  if [ -d "/etc/knot/swarms.d" ]; then
    for f in /etc/knot/swarms.d/*.conf; do
      [ -e "$f" ] || continue
      local base
      base="$(basename "$f" .conf)"
      echo "$base"
      return 0
    done
  fi

  echo "none"
}

# Sets active swarm ID across /run/knot and user state
knot_set_active_swarm() {
  local swarm_id="${1:-none}"
  local run_dir="${KNOT_RUNTIME_DIR:-/run/knot}"
  
  # 1. System runtime directory
  if [ -d "$run_dir" ] || [ -w "$(dirname "$run_dir")" ]; then
    if [ ! -d "$run_dir" ]; then
      mkdir -p "$run_dir"
    fi
    if [ -w "$run_dir/active_swarm" ]; then
      echo "$swarm_id" > "$run_dir/active_swarm"
    elif [ -w "$run_dir" ]; then
      echo "$swarm_id" > "$run_dir/active_swarm.tmp"
      if ! mv -f "$run_dir/active_swarm.tmp" "$run_dir/active_swarm" 2>&1; then
        if [ -w "$run_dir/active_swarm" ]; then
          cat "$run_dir/active_swarm.tmp" > "$run_dir/active_swarm"
        elif command -v sudo >/dev/null; then
          if sudo -n true 2>&1; then
            echo "$swarm_id" | sudo tee "$run_dir/active_swarm" >/dev/null
          fi
        fi
        rm -f "$run_dir/active_swarm.tmp"
      fi
    elif command -v sudo >/dev/null; then
      if sudo -n true 2>&1; then
        echo "$swarm_id" | sudo tee "$run_dir/active_swarm" >/dev/null
      fi
    fi
  elif command -v sudo >/dev/null; then
    if sudo -n true 2>&1; then
      sudo mkdir -p "$run_dir"
      echo "$swarm_id" | sudo tee "$run_dir/active_swarm" >/dev/null
    fi
  fi

  # 2. User state directory
  local user_home
  user_home="$(knot_detect_user_home)"
  local state_dir="$user_home/.local/state/knot"
  mkdir -p "$state_dir"
  echo "$swarm_id" > "$state_dir/active_swarm.tmp"
  mv -f "$state_dir/active_swarm.tmp" "$state_dir/active_swarm"
}

# Loads a specific swarm profile into current shell environment
knot_load_swarm_profile() {
  local target_id="${1:-}"
  if [ -z "$target_id" ]; then
    target_id="$(knot_get_active_swarm)"
  fi

  if [ -z "$target_id" ] || [ "$target_id" = "none" ]; then
    return 1
  fi

  local conf=""
  if [ -r "/etc/knot/swarms.d/${target_id}.conf" ]; then
    conf="/etc/knot/swarms.d/${target_id}.conf"
  else
    local user_home
    user_home="$(knot_detect_user_home)"
    if [ -r "$user_home/.config/knot/swarms/${target_id}.conf" ]; then
      conf="$user_home/.config/knot/swarms/${target_id}.conf"
    elif [ -r "$user_home/.config/knot/swarms/${target_id}/swarm.conf" ]; then
      conf="$user_home/.config/knot/swarms/${target_id}/swarm.conf"
    fi
  fi

  if [ -n "$conf" ] && [ -r "$conf" ]; then
    SWARM_ID="$target_id"
    SWARM_NAME="$target_id"
    ANCHOR_ID="desktop"
    ANCHOR_HOST="desktop.local"
    GATEWAY_MAC=""
    GATEWAY_MACS=""
    SSID=""
    SUBNET=""
    HUB_PORT=4242
    ALLOW_NOPASSWD_SUDO="true"
    ALLOW_DESKFLOW_KVM="true"
    # shellcheck disable=SC1090
    source "$conf"
    return 0
  fi
  return 1
}

knot_get_nodes_dir() {
  local home
  home="$(knot_detect_user_home)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"

  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    if [ -d "$home/.config/knot/swarms/${active_swarm}/nodes" ]; then
      echo "$home/.config/knot/swarms/${active_swarm}/nodes"
      return 0
    elif [ -d "/etc/knot/swarms.d/${active_swarm}/nodes" ]; then
      echo "/etc/knot/swarms.d/${active_swarm}/nodes"
      return 0
    fi
  fi

  echo ""
  return 1
}

knot_get_manifest_path() {
  local node_id="$1"
  local nodes_dir
  if nodes_dir="$(knot_get_nodes_dir)"; then
    if [ -f "$nodes_dir/${node_id}.json" ]; then
      echo "$nodes_dir/${node_id}.json"
      return 0
    fi
  fi
  return 1
}

# Returns 0 if current node is the Anchor of the active swarm, 1 otherwise
knot_is_anchor() {
  local my_host
  my_host="$(knot_detect_hostname)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local anchor_id="desktop"
  local anchor_host="desktop"

  if knot_load_swarm_profile "$active_swarm"; then
    anchor_id="${ANCHOR_ID:-desktop}"
    anchor_host="${ANCHOR_HOST:-desktop}"
  fi

  if [ "$my_host" = "$anchor_host" ] || [ "$my_host" = "$anchor_id" ]; then
    return 0
  fi

  local a_manifest=""
  if a_manifest="$(knot_get_manifest_path "$anchor_id" 2>/dev/null)"; then
    local a_host
    a_host="$(awk -F'"' '/"hostname":/ {print $4}' "$a_manifest" 2>/dev/null || true)"
    if [ -n "$a_host" ] && [ "$my_host" = "$a_host" ]; then
      return 0
    fi
  fi

  return 1
}
