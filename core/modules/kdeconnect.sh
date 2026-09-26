#!/usr/bin/env bash
set -euo pipefail

# Knot KDE Connect Full-Mesh Synchronization Module

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

kdeconnect_get_qdbus_cmd() {
  if command -v qdbus6 >/dev/null; then
    echo "qdbus6"
    return 0
  elif command -v qdbus >/dev/null; then
    echo "qdbus"
    return 0
  fi
  return 1
}

kdeconnect_get_clipboard() {
  # 1. Prefer wl-paste in active Wayland session if available
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null; then
    local wp_out="" wp_rc=0
    wp_out="$(wl-paste --no-newline 2>&1)" || wp_rc=$?
    if [ $wp_rc -eq 0 ]; then
      printf "%s" "$wp_out"
      return 0
    fi
  fi

  # 2. KDE Plasma 6 Klipper DBus pipeline
  local qdbus_cmd=""
  if qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    local dbus_out="" dbus_rc=0
    dbus_out="$("$qdbus_cmd" org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents 2>&1)" || dbus_rc=$?
    if [ $dbus_rc -eq 0 ]; then
      printf "%s" "$dbus_out"
      return 0
    fi
  fi

  knot_log_err "Failed to read clipboard: neither wl-paste nor Klipper DBus responded successfully"
  return 1
}

kdeconnect_set_clipboard() {
  local payload="${1:-}"
  if [ -z "$payload" ] && [ ! -t 0 ]; then
    payload="$(cat)"
  fi
  if [ -z "$payload" ]; then
    knot_log_err "kdeconnect_set_clipboard: No text or payload provided"
    return 1
  fi

  # 1. Prefer Klipper DBus pipeline (standard across KDE Plasma 6 Wayland)
  local qdbus_cmd=""
  if qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    local q_out="" q_rc=0
    q_out="$("$qdbus_cmd" org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents "$payload" 2>&1)" || q_rc=$?
    if [ $q_rc -eq 0 ]; then
      return 0
    fi
    knot_log_warn "Notice: Klipper DBus setClipboardContents returned $q_rc: $q_out"
  fi

  # 2. Fallback to wl-copy in Wayland session
  if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null; then
    local wc_rc=0
    wl-copy "$payload" || wc_rc=$?
    if [ $wc_rc -eq 0 ]; then
      return 0
    fi
    knot_log_warn "Notice: wl-copy returned non-zero ($wc_rc)"
  fi

  knot_log_err "Failed to set clipboard: neither Klipper DBus nor wl-copy succeeded"
  return 1
}

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
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    qdbus_cmd=""
  fi

  echo ""
  echo -e "\033[1;34m--- Discovered & Paired Devices ---\033[0m"

  if [ -n "$qdbus_cmd" ]; then
    local all_devs_out=""
    if all_devs_out="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false false 2>&1)"; then
      local dev_count=0
      printf "%-20s %-34s %-10s %-8s %-18s\n" "DEVICE NAME" "DEVICE ID" "REACHABLE" "PAIRED" "CLIPBOARD"
      printf "%-20s %-34s %-10s %-8s %-18s\n" "-----------" "---------" "---------" "------" "---------"

      while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        dev_count=$((dev_count + 1))

        local dname="$dev"
        local name_out=""
        if name_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
          [ -n "$name_out" ] && dname="$name_out"
        fi

        local is_reach="false"
        local reach_out=""
        if reach_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isReachable 2>&1)"; then
          is_reach="$reach_out"
        fi

        local is_paired="false"
        local paired_out=""
        if paired_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPaired 2>&1)"; then
          is_paired="$paired_out"
        fi

        local clip_status="N/A"
        if [ "$is_paired" = "true" ]; then
          local clip_out=""
          if clip_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPluginEnabled kdeconnect_clipboard 2>&1)"; then
            if [ "$clip_out" = "true" ]; then
              clip_status="ACTIVE"
            else
              clip_status="DISABLED"
            fi
          else
            clip_status="UNKNOWN"
          fi
        fi

        local reach_display
        if [ "$is_reach" = "true" ]; then
          reach_display=$'\033[32mYES\033[0m'
        else
          reach_display=$'\033[31mNO\033[0m'
        fi

        local paired_display
        if [ "$is_paired" = "true" ]; then
          paired_display=$'\033[32mYES\033[0m'
        else
          paired_display=$'\033[33mNO\033[0m'
        fi

        local clip_display
        if [ "$clip_status" = "ACTIVE" ]; then
          clip_display=$'\033[32mACTIVE\033[0m'
        elif [ "$clip_status" = "DISABLED" ]; then
          clip_display=$'\033[31mDISABLED\033[0m'
        else
          clip_display=$'\033[37m-\033[0m'
        fi

        printf "%-20s %-34s %-19b %-17b %-27b\n" "$dname" "$dev" "$reach_display" "$paired_display" "$clip_display"
      done <<< "$all_devs_out"

      if [ $dev_count -eq 0 ]; then
        echo "  No KDE Connect devices currently discovered or registered."
      fi
    else
      knot_log_warn "Could not query KDE Connect devices via DBus: $all_devs_out"
    fi
  elif command -v kdeconnect-cli >/dev/null; then
    local cli_out=""
    if cli_out="$(kdeconnect-cli -l 2>&1)"; then
      echo "$cli_out"
    else
      knot_log_warn "kdeconnect-cli -l probe returned non-zero: $cli_out"
    fi
  else
    knot_log_warn "Neither qdbus nor kdeconnect-cli installed; device list unavailable"
  fi
}

kdeconnect_prune_stale() {
  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_warn "qdbus unavailable; cannot prune stale devices via DBus"
    return 0
  fi

  local my_host
  my_host="$(knot_detect_hostname)"
  local my_id
  my_id="$(kdeconnect_get_my_id)"

  local home
  home="$(knot_detect_user_home)"
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

  # Build map of active swarm node hostnames to expected current device IDs
  declare -A active_hosts=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local h nid
      h="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      if [ -n "$h" ]; then active_hosts["$h"]="$nid"; fi
      if [ -n "$nid" ]; then active_hosts["$nid"]="$nid"; fi
    done
  done

  local paired_devs=""
  if ! paired_devs="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>&1)"; then
    return 0
  fi

  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    local dname=""
    if dname="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
      # If this device name matches local hostname or a known swarm member, but has an old/unreachable ID
      local is_reach="false"
      local reach_out=""
      if reach_out="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isReachable 2>&1)"; then
        is_reach="$reach_out"
      fi

      if [ "$dname" = "$my_host" ] || [ "$dev" = "$my_id" ]; then
        knot_log_info "Pruning obsolete self-pairing '$dname' ($dev)..."
        "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.unpair
      elif [ -n "${active_hosts["$dname"]:-}" ] && [ "$is_reach" = "false" ]; then
        local has_reachable_peer=0
        local all_devs=""
        if all_devs="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false false 2>&1)"; then
          while IFS= read -r other_dev; do
            [ -n "$other_dev" ] || continue
            [ "$other_dev" = "$dev" ] && continue
            local other_name=""
            if other_name="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$other_dev" org.kde.kdeconnect.device.name 2>&1)"; then
              if [ "$other_name" = "$dname" ]; then
                local other_reach=""
                if other_reach="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$other_dev" org.kde.kdeconnect.device.isReachable 2>&1)"; then
                  if [ "$other_reach" = "true" ]; then
                    has_reachable_peer=1
                    break
                  fi
                fi
              fi
            fi
          done <<< "$all_devs"
        fi

        if [ $has_reachable_peer -eq 1 ]; then
          knot_log_info "Pruning stale offline duplicate pairing '$dname' ($dev)..."
          "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.unpair
        fi
      fi
    fi
  done <<< "$paired_devs"
}

kdeconnect_pair_node() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: knot kdeconnect pair <node_id|device_id>"
    return 1
  fi

  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_err "Neither qdbus6 nor qdbus found on local host"
    return 1
  fi

  local my_id
  my_id="$(kdeconnect_get_my_id)"
  local my_host
  my_host="$(knot_detect_hostname)"

  # Resolve target node manifest
  local target_node="$target"
  local target_host="$target"
  local target_ip=""
  local target_port=22
  local home
  home="$(knot_detect_user_home)"

  for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    for mf in "$d/"*.json; do
      [ -e "$mf" ] || continue
      local nid nhost nport
      nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
      nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$mf")"
      nport="$(awk -F': ' '/"port":/ {print $2}' "$mf" | tr -d ', ')"
      if [ "$nid" = "$target" ] || [ "$nhost" = "$target" ]; then
        target_node="$nid"
        target_host="$nhost"
        target_port="${nport:-22}"
        break 2
      fi
    done
  done

  # Resolve target IP
  local rip=""
  if rip="$("$KNOT_ROOT/bin/knot" resolve "$target_node" "$target_port" 2>&1)"; then
    target_ip="$rip"
  fi

  # Query remote target's active KDE Connect device ID via SSH
  local target_kde_id=""
  local ssh_out="" ssh_rc=0
  ssh_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target_node" "kdeconnect-cli --my-id" 2>&1)" || ssh_rc=$?
  if [ $ssh_rc -eq 0 ] && [ -n "$ssh_out" ]; then
    target_kde_id="$(echo "$ssh_out" | tr -d '[:space:]')"
  fi

  if [ -z "$target_kde_id" ]; then
    target_kde_id="$target"
  fi

  knot_log_info "Target node '$target_node' resolved to KDE Connect device ID: $target_kde_id"

  # Ensure both sides have customDevices configured and discovery refreshed
  kdeconnect_configure_custom_devices
  "$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.forceOnNetworkChange
  if [ "$target_node" != "$my_host" ]; then
    local rem_force_out="" rem_force_rc=0
    rem_force_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target_node" "qdbus6 org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.forceOnNetworkChange" 2>&1)" || rem_force_rc=$?
  fi

  # Prune any stale pairings
  kdeconnect_prune_stale
  if [ "$target_node" != "$my_host" ]; then
    local rem_prune_out="" rem_prune_rc=0
    rem_prune_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target_node" "qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.unpair" 2>&1)" || rem_prune_rc=$?
  fi

  # Check if already paired
  local is_paired="false"
  local pair_check=""
  if pair_check="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.isPaired 2>&1)"; then
    is_paired="$pair_check"
  fi

  if [ "$is_paired" = "true" ]; then
    knot_log_ok "Already paired with '$target_node' ($target_kde_id)"
    "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true
    return 0
  fi

  knot_log_info "Dispatching automated zero-interaction pairing request to $target_kde_id..."
  local req_out="" req_rc=0
  req_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.requestPairing 2>&1)" || req_rc=$?
  if [ $req_rc -ne 0 ]; then
    kdeconnect-cli --pair -d "$target_kde_id"
  fi

  # Accept pairing request remotely over SSH out-of-band trust channel
  knot_log_info "Accepting pairing request on remote node '$target_node' via authenticated SSH trust..."
  local accepted=0
  for _ in {1..8}; do
    sleep 0.5
    local r_acc="" r_rc=0
    r_acc="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$target_node" "
      if qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.isPairRequestedByPeer 2>&1 | grep -q true; then
        qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.acceptPairing
        qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true
        echo 'ACCEPTED'
      fi
    " 2>&1)" || r_rc=$?

    if [ $r_rc -eq 0 ] && echo "$r_acc" | grep -q "ACCEPTED"; then
      accepted=1
      break
    fi
  done

  # Fallback: reverse pairing initiation from target to local
  if [ $accepted -eq 0 ]; then
    knot_log_info "Attempting reverse pairing initiation from '$target_node' to local..."
    local r_req="" r_req_rc=0
    r_req="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$target_node" "qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.requestPairing" 2>&1)" || r_req_rc=$?
    for _ in {1..8}; do
      sleep 0.5
      local is_peer_req=""
      if is_peer_req="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.isPairRequestedByPeer 2>&1)"; then
        if [ "$is_peer_req" = "true" ]; then
          "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.acceptPairing
          "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true
          accepted=1
          break
        fi
      fi
    done
  fi

  # Verify pairing status locally
  local verify_ok=0
  for _ in {1..10}; do
    sleep 0.5
    local v_check=""
    if v_check="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.isPaired 2>&1)"; then
      if [ "$v_check" = "true" ]; then
        verify_ok=1
        break
      fi
    fi
  done

  if [ $verify_ok -eq 1 ]; then
    "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_kde_id" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true
    local rem_clip_out="" rem_clip_rc=0
    rem_clip_out="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$target_node" "qdbus6 org.kde.kdeconnect /modules/kdeconnect/devices/$my_id org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true" 2>&1)" || rem_clip_rc=$?
    knot_log_ok "Successfully paired with '$target_node' ($target_kde_id) and activated clipboard sharing."
    return 0
  else
    knot_log_err "Pairing handshake with '$target_node' timed out or was not confirmed."
    return 1
  fi
}

kdeconnect_pair_all() {
  knot_log_info "Initiating full-mesh automated zero-interaction pairing across the swarm..."
  kdeconnect_sync_mesh

  local home
  home="$(knot_detect_user_home)"
  local my_host
  my_host="$(knot_detect_hostname)"

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

  local peer_nodes=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local nid nhost
      nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      if [ -n "$nid" ] && [ "$nid" != "$my_host" ] && [ "$nhost" != "$my_host" ]; then
        if [[ ! " ${peer_nodes[*]} " =~ " ${nid} " ]]; then
          peer_nodes+=("$nid")
        fi
      fi
    done
  done

  # 1. Pair local node with all peers
  for peer in "${peer_nodes[@]}"; do
    knot_log_info "--- Pairing local node with $peer ---"
    local p_out="" p_rc=0
    p_out="$(kdeconnect_pair_node "$peer" 2>&1)" || p_rc=$?
    if [ $p_rc -eq 0 ]; then
      echo "$p_out"
    else
      knot_log_warn "Notice: Automated pairing with $peer returned non-zero ($p_rc): $p_out"
    fi
  done

  # 2. Enforce inter-strand pairings between remote nodes
  for ((i=0; i<${#peer_nodes[@]}; i++)); do
    for ((j=i+1; j<${#peer_nodes[@]}; j++)); do
      local node_a="${peer_nodes[i]}"
      local node_b="${peer_nodes[j]}"
      knot_log_info "Verifying peer-to-peer pairing between $node_a and $node_b..."
      local mesh_p_out="" mesh_p_rc=0
      mesh_p_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$node_a" "knot kdeconnect pair $node_b" 2>&1)" || mesh_p_rc=$?
      if [ $mesh_p_rc -eq 0 ]; then
        echo "  -> $node_a <-> $node_b: OK"
      else
        knot_log_warn "Notice: Peer pairing between $node_a and $node_b returned ($mesh_p_rc): $mesh_p_out"
      fi
    done
  done

  kdeconnect_sync_mesh
  knot_log_ok "Full-mesh pairing reconciliation complete."
}

kdeconnect_pair() {
  local target="${1:-}"
  if [ "${target:-}" = "-h" ] || [ "${target:-}" = "--help" ]; then
    echo "Usage: knot kdeconnect pair <node_id|--all>"
    echo ""
    echo "Automated zero-interaction trust bootstrapping via SSH mesh identity."
    return 0
  fi

  if [ -z "$target" ]; then
    knot_log_err "Usage: knot kdeconnect pair <node_id|--all>"
    return 1
  fi

  if [ "$target" = "--all" ]; then
    kdeconnect_pair_all
  else
    kdeconnect_pair_node "$target"
  fi
}

kdeconnect_share() {
  local target=""
  local payload=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --target|-t)
        target="$2"
        shift 2
        ;;
      -h|--help)
        echo "Usage: knot kdeconnect share --target <node_id> [<payload>]"
        echo "       knot kdeconnect share --all [<payload>]"
        echo "       cat file.txt | knot kdeconnect share --target <node_id>"
        echo ""
        echo "Pushes text, URLs, or clipboard data directly into the target strand's clipboard."
        return 0
        ;;
      *)
        if [ -z "$payload" ]; then
          payload="$1"
        else
          payload="$payload $1"
        fi
        shift
        ;;
    esac
  done

  # Read from stdin if payload is empty
  if [ -z "$payload" ] && [ ! -t 0 ]; then
    payload="$(cat)"
  fi

  # If still empty, read from local clipboard
  if [ -z "$payload" ]; then
    payload="$(kdeconnect_get_clipboard)"
  fi

  if [ -z "$payload" ]; then
    knot_log_err "No payload provided and clipboard is empty"
    return 1
  fi

  if [ -z "$target" ] || [ "$target" = "--all" ]; then
    kdeconnect_set_clipboard "$payload"
    kdeconnect_sync_clipboard --all
    return 0
  fi

  knot_log_info "Piping payload (${#payload} bytes) directly into target strand '$target' clipboard..."

  # Direct remote injection into Klipper / wl-copy via SSH
  local inj_out="" inj_rc=0
  inj_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target" '
    payload="$(cat)"
    if command -v qdbus6 >/dev/null; then
      qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents "$payload"
    elif command -v qdbus >/dev/null; then
      qdbus org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents "$payload"
    fi
    if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null; then
      wl_err=0
      wl-copy "$payload" || wl_err=$?
    fi
  ' <<< "$payload" 2>&1)" || inj_rc=$?

  if [ $inj_rc -ne 0 ]; then
    knot_log_warn "Remote clipboard injection into '$target' returned ($inj_rc): $inj_out"
  else
    knot_log_ok "Payload successfully set on '$target' clipboard."
  fi

  # If payload is a URL, trigger native browser URL open if paired in KDE Connect
  if [[ "$payload" =~ ^https?:// ]]; then
    local qdbus_cmd=""
    if qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
      local all_devs=""
      if all_devs="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>&1)"; then
        while IFS= read -r dev; do
          [ -n "$dev" ] || continue
          local dname=""
          if dname="$($qdbus_cmd org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
            if [ "$dname" = "$target" ] || [ "$dev" = "$target" ]; then
              local share_out="" share_rc=0
              share_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/share" org.kde.kdeconnect.device.share.shareUrl "$payload" 2>&1)" || share_rc=$?
              if [ $share_rc -eq 0 ]; then
                knot_log_ok "URL dispatched via KDE Connect Share to $dname ($dev)"
              fi
              break
            fi
          fi
        done <<< "$all_devs"
      fi
    fi
  fi
}

kdeconnect_sync_clipboard() {
  local target="${1:---all}"
  local local_clip
  if ! local_clip="$(kdeconnect_get_clipboard)"; then
    knot_log_err "Cannot synchronize clipboard: local clipboard is unreadable or empty"
    return 1
  fi

  if [ -z "$local_clip" ]; then
    knot_log_warn "Local clipboard is empty; nothing to sync"
    return 0
  fi

  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    qdbus_cmd=""
  fi

  if [ "$target" = "--all" ]; then
    knot_log_info "Synchronizing local clipboard (${#local_clip} bytes) across the fleet..."

    # 1. Trigger DBus sendClipboard on all paired devices
    if [ -n "$qdbus_cmd" ]; then
      local paired_devs=""
      if paired_devs="$($qdbus_cmd org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>&1)"; then
        while IFS= read -r dev; do
          [ -n "$dev" ] || continue
          local sc_out="" sc_rc=0
          sc_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/clipboard" org.kde.kdeconnect.device.clipboard.sendClipboard 2>&1)" || sc_rc=$?
        done <<< "$paired_devs"
      fi
    fi

    # 2. Direct injection into all swarm members for 100% reliability
    local home
    home="$(knot_detect_user_home)"
    local my_host
    my_host="$(knot_detect_hostname)"
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

    for ndir in "${nodes_dirs[@]}"; do
      for manifest in "$ndir/"*.json; do
        [ -e "$manifest" ] || continue
        local nid nhost
        nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        if [ -n "$nid" ] && [ "$nid" != "$my_host" ] && [ "$nhost" != "$my_host" ]; then
          local sync_out="" sync_rc=0
          sync_out="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$nid" '
            payload="$(cat)"
            if command -v qdbus6 >/dev/null; then
              qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents "$payload"
            elif command -v qdbus >/dev/null; then
              qdbus org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents "$payload"
            fi
            if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-copy >/dev/null; then
              wl_err=0
              wl-copy "$payload" || wl_err=$?
            fi
          ' <<< "$local_clip" 2>&1)" || sync_rc=$?

          if [ $sync_rc -eq 0 ]; then
            echo "  [✓] $nid: synchronized"
          else
            knot_log_warn "  [!] $nid: sync returned $sync_rc ($sync_out)"
          fi
        fi
      done
    done
    knot_log_ok "Clipboard synchronization broadcast complete."
  else
    knot_log_info "Synchronizing clipboard to target '$target'..."
    kdeconnect_share --target "$target" "$local_clip"
  fi
}

kdeconnect_test_clipboard() {
  local target="${1:---all}"
  local test_token="knot-test-clipboard-$(date +%s)-$RANDOM-$(knot_detect_hostname)"

  knot_log_info "=== KDE Connect Clipboard E2E Verification Sweep ==="
  knot_log_info "Generated verification test token: $test_token"

  # 1. Set local clipboard
  kdeconnect_set_clipboard "$test_token"

  # 2. Sync to target(s)
  kdeconnect_sync_clipboard "$target"
  sleep 1.5

  local home
  home="$(knot_detect_user_home)"
  local my_host
  my_host="$(knot_detect_hostname)"

  local targets_to_test=()
  if [ "$target" = "--all" ]; then
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

    for ndir in "${nodes_dirs[@]}"; do
      for manifest in "$ndir/"*.json; do
        [ -e "$manifest" ] || continue
        local nid nhost
        nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        if [ -n "$nid" ] && [ "$nid" != "$my_host" ] && [ "$nhost" != "$my_host" ]; then
          targets_to_test+=("$nid")
        fi
      done
    done
  else
    targets_to_test+=("$target")
  fi

  local all_ok=1
  for node in "${targets_to_test[@]}"; do
    local r_clip="" r_rc=0
    r_clip="$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$node" '
      if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wl-paste >/dev/null; then
        wp_out="" wp_rc=0
        wp_out="$(wl-paste --no-newline 2>&1)" || wp_rc=$?
        if [ $wp_rc -eq 0 ]; then
          printf "%s" "$wp_out"
          exit 0
        fi
      fi
      if command -v qdbus6 >/dev/null; then
        qdbus6 org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents
      elif command -v qdbus >/dev/null; then
        qdbus org.kde.klipper /klipper org.kde.klipper.klipper.getClipboardContents
      fi
    ' 2>&1)" || r_rc=$?

    local stripped_r
    stripped_r="$(echo "$r_clip" | tr -d '\r\n')"
    local stripped_expected
    stripped_expected="$(echo "$test_token" | tr -d '\r\n')"

    if [ "$stripped_r" = "$stripped_expected" ]; then
      knot_log_ok "Node '$node': Clipboard round-trip verified (token matches)."
    else
      knot_log_err "Node '$node': Clipboard mismatch! Expected '$stripped_expected', received '$stripped_r' (rc=$r_rc)"
      all_ok=0
    fi
  done

  if [ $all_ok -eq 1 ]; then
    knot_log_ok "All tested nodes passed clipboard verification!"
    return 0
  else
    knot_log_err "One or more nodes failed clipboard verification."
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
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    qdbus_cmd=""
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

kdeconnect_reconcile() {
  knot_log_info "Reconciling KDE Connect mesh health & pairings..."

  # 1. Prune obsolete or collision-causing device IDs
  kdeconnect_prune_stale

  # 2. Synchronize IP hints and verify local daemon
  kdeconnect_sync_mesh

  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_warn "Neither qdbus6 nor qdbus found; skipping DBus pairing reconciliation"
    return 0
  fi

  local home my_host
  home="$(knot_detect_user_home)"
  my_host="$(knot_detect_hostname)"

  # 3. Discover known active swarm peers from manifests
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

  local peer_nodes=()
  local peer_hosts=()
  local peer_ips=()
  for ndir in "${nodes_dirs[@]}"; do
    for manifest in "$ndir/"*.json; do
      [ -e "$manifest" ] || continue
      local nid nhost nip
      nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      nip="$(awk -F'"' '/"ip_hint":/ {print $4}' "$manifest")"
      if [ -n "$nid" ] && [ "$nid" != "$my_host" ] && [ "$nhost" != "$my_host" ]; then
        if [[ ! " ${peer_nodes[*]} " =~ " ${nid} " ]]; then
          peer_nodes+=("$nid")
          peer_hosts+=("${nhost:-$nid}")
          peer_ips+=("${nip:-}")
        fi
      fi
    done
  done

  if [ "${#peer_nodes[@]}" -eq 0 ]; then
    knot_log_info "No remote swarm peers found to reconcile."
    return 0
  fi

  # 4. Handle incoming pending pairing requests from verified swarm peers
  local all_devs_out="" all_devs_rc=0
  if all_devs_out="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false false 2>&1)"; then
    while IFS= read -r dev; do
      [ -n "$dev" ] || continue
      local pair_req=""
      if pair_req="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.isPairRequestedByPeer 2>&1)"; then
        if [ "$pair_req" = "true" ]; then
          local dev_name=""
          if ! dev_name="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
            dev_name=""
          fi

          # Check if this device matches a known swarm peer
          local matched_peer=""
          for ((p=0; p<${#peer_nodes[@]}; p++)); do
            if [ "$dev_name" = "${peer_nodes[p]}" ] || [ "$dev_name" = "${peer_hosts[p]}" ]; then
              matched_peer="${peer_nodes[p]}"
              break
            fi
          done

          if [ -n "$matched_peer" ]; then
            # Strict reciprocal SSH trust probe
            local ssh_probe="" probe_rc=0
            if ssh_probe="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$matched_peer" "echo ok" 2>&1)"; then
              knot_log_info "Auto-accepting verified pairing request from swarm peer '$matched_peer' ($dev)..."
              local acc_out=""
              if acc_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.acceptPairing 2>&1)"; then
                "$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true
                knot_log_ok "Accepted pairing and activated clipboard for '$matched_peer'."
              else
                knot_log_warn "Notice: acceptPairing for '$matched_peer' returned: $acc_out"
              fi
            else
              knot_log_warn "Notice: Device '$dev_name' requested pairing but failed reciprocal SSH verification: $ssh_probe"
            fi
          fi
        fi
      fi
    done <<< "$all_devs_out"
  fi

  # 5. Check all known swarm peers: are they reachable but unpaired?
  for peer in "${peer_nodes[@]}"; do
    local is_reachable=0
    local reach_probe=""
    if reach_probe="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" "echo ok" 2>&1)"; then
      is_reachable=1
    fi

    if [ $is_reachable -eq 1 ]; then
      # Resolve remote peer's KDE Connect device ID
      local peer_kde_id="" id_rc=0
      if peer_kde_id="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$peer" "kdeconnect-cli --my-id" 2>&1)"; then
        peer_kde_id="$(echo "$peer_kde_id" | tr -d '[:space:]')"
      else
        id_rc=1
      fi

      local is_paired=0
      if [ $id_rc -eq 0 ] && [ -n "$peer_kde_id" ]; then
        local p_check=""
        if p_check="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$peer_kde_id" org.kde.kdeconnect.device.isPaired 2>&1)"; then
          if [ "$p_check" = "true" ]; then
            is_paired=1
          fi
        fi
      fi

      if [ $is_paired -eq 0 ]; then
        knot_log_warn "Swarm peer '$peer' is online but NOT paired in KDE Connect. Initiating automated pairing..."
        local p_err="" p_rc=0
        if p_err="$(kdeconnect_pair_node "$peer" 2>&1)"; then
          knot_log_ok "Successfully self-healed pairing with '$peer'."
        else
          p_rc=$?
          knot_log_warn "Notice: Automated re-pairing with '$peer' returned ($p_rc): $p_err"
        fi
      else
        # Already paired: verify clipboard plugin is enabled
        if [ -n "$peer_kde_id" ]; then
          local clip_out=""
          if ! clip_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$peer_kde_id" org.kde.kdeconnect.device.setPluginEnabled kdeconnect_clipboard true 2>&1)"; then
            knot_log_warn "Notice: Could not enable clipboard plugin for '$peer': $clip_out"
          fi
        fi
      fi
    else
      knot_log_info "Swarm peer '$peer' is offline/unreachable on LAN ($reach_probe). Skipping."
    fi
  done

  knot_log_ok "KDE Connect mesh reconciliation completed."
  return 0
}
