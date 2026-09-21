#!/usr/bin/env bash
set -euo pipefail

# Knot KDE Connect Full-Mesh Synchronization Module

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

kdeconnect_get_my_id() {
  if ! command -v kdeconnect-cli >/dev/null; then
    knot_log_err "kdeconnect-cli is not installed on this host"
    return 1
  fi
  local id
  id="$(kdeconnect-cli --my-id | tr -d '[:space:]')"
  if [ -z "$id" ]; then
    knot_log_err "Failed to determine local KDE Connect device ID"
    return 1
  fi
  echo "$id"
}

kdeconnect_configure_custom_devices() {
  local home
  home="$(knot_detect_user_home)"
  local cfg_dir="$home/.config/kdeconnect"
  mkdir -p "$cfg_dir"

  local cfg_file="$cfg_dir/config"
  local my_host
  my_host="$(knot_detect_hostname)"

  # 1. Discover all swarm node directories
  local nodes_dirs=()
  if command -v knot_get_nodes_dir >/dev/null; then
    local primary_dir=""
    if primary_dir="$(knot_get_nodes_dir)" && [ -d "$primary_dir" ]; then
      nodes_dirs+=("$primary_dir")
    fi
  fi

  for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    if [[ ! " ${nodes_dirs[*]} " =~ " ${d} " ]]; then
      nodes_dirs+=("$d")
    fi
  done

  # 2. Resolve peer node IPs from manifests
  local peer_ips=()
  local seen_nodes=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local node_id h port
      node_id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      port="$(awk -F': ' '/"port":/ {print $2}' "$manifest" | tr -d ', ')"
      if [ -z "$node_id" ] || [ "$h" = "$my_host" ] || [ "$node_id" = "$my_host" ]; then
        continue
      fi
      if [[ " ${seen_nodes[*]} " =~ " ${node_id} " ]]; then
        continue
      fi
      seen_nodes+=("$node_id")

      local ip=""
      if ip="$("$KNOT_ROOT/bin/knot" resolve "$node_id" "${port:-22}")"; then
        if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
          if [[ ! " ${peer_ips[*]} " =~ " ${ip} " ]]; then
            peer_ips+=("$ip")
          fi
        fi
      else
        knot_log_warn "Failed to resolve IP for peer node $node_id"
      fi
    done
  done

  if [ "${#peer_ips[@]}" -eq 0 ]; then
    knot_log_warn "No peer IPs resolved from swarm manifests for KDE Connect customDevices"
    return 0
  fi

  local joined_ips
  joined_ips="$(IFS=,; echo "${peer_ips[*]}")"

  # Safe atomic INI injection preserving existing entries and case
  python3 - << PY_INI
import configparser
import os

cfg_file = "$cfg_file"
new_ips_str = "$joined_ips"
new_ips = [x.strip() for x in new_ips_str.split(",") if x.strip()]

config = configparser.RawConfigParser()
config.optionxform = lambda opt: opt

if os.path.isfile(cfg_file):
    config.read(cfg_file)

if not config.has_section("General"):
    config.add_section("General")

existing_ips = []
if config.has_option("General", "customDevices"):
    cur = config.get("General", "customDevices")
    existing_ips = [x.strip() for x in cur.split(",") if x.strip()]

for ip in new_ips:
    if ip not in existing_ips:
        existing_ips.append(ip)

config.set("General", "customDevices", ",".join(existing_ips))
if not config.has_option("General", "keyAlgorithm"):
    config.set("General", "keyAlgorithm", "EC")

cfg_dir = os.path.dirname(cfg_file)
os.makedirs(cfg_dir, exist_ok=True)
tmp_file = cfg_file + ".tmp"
with open(tmp_file, "w") as f:
    config.write(f, space_around_delimiters=False)
os.replace(tmp_file, cfg_file)
PY_INI

  knot_log_ok "KDE Connect customDevices atomically configured ($joined_ips) on $my_host"
}

kdeconnect_status() {
  local my_id
  if ! my_id="$(kdeconnect_get_my_id)"; then
    knot_log_warn "KDE Connect is not running or not installed on local host"
    return 1
  fi
  local my_host
  my_host="$(knot_detect_hostname)"

  echo -e "\033[1;36m=== KDE Connect Status on $my_host ===\033[0m"
  echo "  Local Device ID: $my_id"

  local home
  home="$(knot_detect_user_home)"
  local cfg_file="$home/.config/kdeconnect/config"
  if [ -f "$cfg_file" ]; then
    local custom_devs
    custom_devs="$(awk -F= '/^customDevices=/ {print $2}' "$cfg_file" | tr -d ' ')"
    echo "  Configured customDevices: ${custom_devs:-none}"
  else
    echo "  Configured customDevices: (config file not found)"
  fi

  local qdbus_cmd=""
  if command -v qdbus6 >/dev/null; then
    qdbus_cmd="qdbus6"
  elif command -v qdbus >/dev/null; then
    qdbus_cmd="qdbus"
  fi

  echo ""
  echo -e "\033[1;34m--- Discovered / Paired Devices ---\033[0m"
  if command -v kdeconnect-cli >/dev/null; then
    local cli_out=""
    if cli_out="$(kdeconnect-cli -a 2>&1)"; then
      echo "$cli_out"
    else
      knot_log_warn "kdeconnect-cli -a probe returned non-zero: $cli_out"
    fi
  fi

  if [ -n "$qdbus_cmd" ]; then
    local paired_devs_out=""
    if paired_devs_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>&1)"; then
      echo ""
      echo -e "\033[1;34m--- DBus Clipboard Plugin Status ---\033[0m"
      local has_any=0
      while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        has_any=1
        local dname="$dev"
        local name_out=""
        if name_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
          [ -n "$name_out" ] && dname="$name_out"
        fi
        local clip_state=""
        if clip_state="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPluginEnabled kdeconnect_clipboard 2>&1)"; then
          if [ "$clip_state" = "true" ]; then
            echo -e "  $dname ($dev): \033[32mCLIPBOARD ACTIVE\033[0m"
          else
            echo -e "  $dname ($dev): \033[33mCLIPBOARD DISABLED\033[0m"
          fi
        else
          echo -e "  $dname ($dev): \033[31mCLIPBOARD QUERY FAILED\033[0m"
        fi
      done <<< "$paired_devs_out"
      if [ $has_any -eq 0 ]; then
        echo "  No paired devices currently connected via DBus."
      fi
    else
      knot_log_warn "Could not query KDE Connect paired devices via DBus: $paired_devs_out"
    fi
  else
    knot_log_warn "Neither qdbus6 nor qdbus installed; DBus clipboard plugin state unavailable"
  fi
}

kdeconnect_pair() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: knot kdeconnect pair <node_id|device_id>"
    return 1
  fi

  if ! command -v kdeconnect-cli >/dev/null; then
    knot_log_err "kdeconnect-cli is not installed on this host"
    return 1
  fi

  local dev_id="$target"
  local dev_name=""

  # Search discovered devices for matching name or ID
  local list_out=""
  if list_out="$(kdeconnect-cli -a --id-name 2>&1)"; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      local lid lname
      lid="$(echo "$line" | awk '{print $1}')"
      lname="$(echo "$line" | awk '{$1=""; print substr($0,2)}')"
      if [ "$lid" = "$target" ] || [ "$lname" = "$target" ]; then
        dev_id="$lid"
        dev_name="$lname"
        break
      fi
    done <<< "$list_out"
  fi

  # If not matched by cli discovery, check swarm manifests for hostname matching target
  if [ "$dev_id" = "$target" ]; then
    local home
    home="$(knot_detect_user_home)"
    for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
      [ -d "$d" ] || continue
      for mf in "$d/"*.json; do
        [ -e "$mf" ] || continue
        local nid
        nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
        if [ "$nid" = "$target" ]; then
          knot_log_info "Matched target '$target' in swarm manifests."
          break 2
        fi
      done
    done
  fi

  knot_log_info "Initiating KDE Connect pairing request to '$dev_id'${dev_name:+ ($dev_name)}..."
  local pair_out=""
  if pair_out="$(kdeconnect-cli --pair -d "$dev_id" 2>&1)"; then
    knot_log_ok "Pairing request dispatched to $dev_id. Please accept the prompt on the remote device."
    [ -n "$pair_out" ] && echo "$pair_out"
  else
    knot_log_err "Pairing request failed for $dev_id: $pair_out"
    return 1
  fi
}

kdeconnect_sync_mesh() {
  kdeconnect_configure_custom_devices

  local my_id
  my_id="$(kdeconnect_get_my_id)"
  local my_host
  my_host="$(knot_detect_hostname)"

  local qdbus_cmd=""
  if command -v qdbus6 >/dev/null; then
    qdbus_cmd="qdbus6"
  elif command -v qdbus >/dev/null; then
    qdbus_cmd="qdbus"
  fi

  # Trigger network discovery reload if DBus is available
  if [ -n "$qdbus_cmd" ]; then
    local reload_out=""
    if ! reload_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.forceOnNetworkChange 2>&1)"; then
      knot_log_warn "Failed to trigger KDE Connect network reload via DBus: $reload_out"
    fi
  fi

  # Trigger active network probe
  if command -v kdeconnect-cli >/dev/null; then
    local refresh_out=""
    if ! refresh_out="$(kdeconnect-cli --refresh 2>&1)"; then
      knot_log_warn "KDE Connect CLI refresh probe failed: $refresh_out"
    fi
  fi

  knot_log_info "KDE Connect local ID: $my_id on $my_host"

  if [ -z "$qdbus_cmd" ]; then
    knot_log_warn "Neither qdbus6 nor qdbus found; skipping clipboard plugin verification"
    return 0
  fi

  # Query paired device IDs
  local paired_devs_out=""
  if ! paired_devs_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>&1)"; then
    knot_log_warn "Could not query KDE Connect paired devices via DBus: $paired_devs_out"
    return 0
  fi

  local paired_ids=()
  while IFS= read -r dev; do
    [ -n "$dev" ] && paired_ids+=("$dev")
  done <<< "$paired_devs_out"

  knot_log_info "Active paired devices: ${paired_ids[*]:-none}"

  # Enforce kdeconnect_clipboard plugin enabled for all paired devices
  for dev in "${paired_ids[@]}"; do
    local dev_name="$dev"
    local name_out=""
    if name_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
      if [ -n "$name_out" ]; then
        dev_name="$name_out"
      fi
    fi

    local clip_state=""
    if clip_state="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPluginEnabled kdeconnect_clipboard 2>&1)"; then
      if [ "$clip_state" = "true" ]; then
        knot_log_ok "KDE Connect clipboard sharing active for $dev_name ($dev)"
      else
        knot_log_warn "KDE Connect clipboard sharing disabled for $dev_name ($dev); enabling..."
        local set_out=""
        if set_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true 2>&1)"; then
          knot_log_ok "Enabled KDE Connect clipboard sharing for $dev_name ($dev)"
        else
          knot_log_err "Failed to enable clipboard plugin for $dev_name ($dev): $set_out"
        fi
      fi
    else
      knot_log_warn "Failed to query clipboard plugin state for $dev_name ($dev): $clip_state"
    fi
  done
}
