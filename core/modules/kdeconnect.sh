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

  # Gather peer node IPs from Knot registry
  local peer_ips=()
  for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
    [ -e "$manifest" ] || continue
    local h
    h="$(grep -o '"hostname":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"
    if [ "$h" = "$my_host" ]; then
      continue
    fi
    local node_id
    node_id="$(grep -o '"id":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"
    local port
    port="$(grep -o '"port":[[:space:]]*[0-9]*' "$manifest" | awk '{print $NF}')"
    local ip
    ip="$("$KNOT_ROOT/bin/knot" resolve "$node_id" "$port")"
    if [ -n "$ip" ]; then
      peer_ips+=("$ip")
    fi
  done

  if [ "${#peer_ips[@]}" -eq 0 ]; then
    knot_log_warn "No peer IPs resolved from registry for KDE Connect customDevices"
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
    if grep -q "customDevices=" "$cfg_file"; then
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
