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
  local primary_dir=""
  if primary_dir="$(knot_get_nodes_dir 2>/dev/null)" && [ -d "$primary_dir" ]; then
    nodes_dirs+=("$primary_dir")
  fi

  for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    if [[ ! " ${nodes_dirs[*]} " =~ " ${d} " ]]; then
      nodes_dirs+=("$d")
    fi
  done

  # 2. Gather existing customDevices (e.g. mobile phones)
  local existing_ips=()
  if [ -f "$cfg_file" ]; then
    local cur_val
    cur_val="$(awk -F= '/^customDevices=/ {print $2}' "$cfg_file" | tr -d ' ')"
    if [ -n "$cur_val" ]; then
      IFS=',' read -ra ADDR <<< "$cur_val"
      for ip in "${ADDR[@]}"; do
        [ -n "$ip" ] && existing_ips+=("$ip")
      done
    fi
  fi

  # 3. Resolve peer node IPs from manifests
  local peer_ips=("${existing_ips[@]}")
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

      local ip
      ip="$("$KNOT_ROOT/bin/knot" resolve "$node_id" "${port:-22}" 2>/dev/null || true)"
      if [ -n "$ip" ] && [ "$ip" != "127.0.0.1" ]; then
        if [[ ! " ${peer_ips[*]} " =~ " ${ip} " ]]; then
          peer_ips+=("$ip")
        fi
      fi
    done
  done

  if [ "${#peer_ips[@]}" -eq 0 ]; then
    knot_log_warn "No peer IPs resolved from swarm manifests for KDE Connect customDevices"
    return 0
  fi

  local joined_ips
  joined_ips="$(IFS=,; echo "${peer_ips[*]}")"

  if [ ! -f "$cfg_file" ]; then
    cat << CFG_EOF > "$cfg_file"
[General]
keyAlgorithm=EC
customDevices=$joined_ips
CFG_EOF
  else
    if grep -q "^customDevices=" "$cfg_file"; then
      sed -i "s/^customDevices=.*/customDevices=$joined_ips/" "$cfg_file"
    else
      if grep -q "\[General\]" "$cfg_file"; then
        sed -i "/\[General\]/a customDevices=$joined_ips" "$cfg_file"
      else
        printf "\n[General]\ncustomDevices=%s\n" "$joined_ips" >> "$cfg_file"
      fi
    fi
  fi

  knot_log_ok "KDE Connect customDevices configured ($joined_ips) on $my_host"
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
    local reload_out
    if ! reload_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.forceOnNetworkChange 2>&1)"; then
      knot_log_warn "Failed to trigger KDE Connect network reload via DBus: $reload_out"
    fi
  fi

  # Trigger active network probe
  if command -v kdeconnect-cli >/dev/null; then
    local refresh_out
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
  local paired_devs_out
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
    local name_out
    if name_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
      if [ -n "$name_out" ]; then
        dev_name="$name_out"
      fi
    fi

    local clip_state
    if clip_state="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPluginEnabled kdeconnect_clipboard 2>&1)"; then
      if [ "$clip_state" = "true" ]; then
        knot_log_ok "KDE Connect clipboard sharing active for $dev_name ($dev)"
      else
        knot_log_warn "KDE Connect clipboard sharing disabled for $dev_name ($dev); enabling..."
        local set_out
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
