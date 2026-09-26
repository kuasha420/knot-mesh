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

kdeconnect_resolve_device_id() {
  local target="$1"
  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_err "qdbus/qdbus6 command not found"
    return 1
  fi

  local dev_list=""
  if dev_list="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>&1)"; then
    for dev in $dev_list; do
      local dname=""
      if dname="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
        if [ "$dev" = "$target" ] || [ "$dname" = "$target" ]; then
          echo "$dev"
          return 0
        fi
      fi
    done
  fi

  # Fallback to SSH probe if target is a reachable hostname / swarm node ID
  local ssh_id=""
  if ssh_id="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$target" "kdeconnect-cli --my-id" 2>&1)"; then
    ssh_id="$(echo "$ssh_id" | tr -d '[:space:]')"
    if [ -n "$ssh_id" ]; then
      echo "$ssh_id"
      return 0
    fi
  fi

  return 1
}

kdeconnect_vmon_status() {
  local target="${1:-}"
  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_err "qdbus/qdbus6 command not found"
    return 1
  fi

  echo -e "\n${C_BOLD}=== KDE Connect Wayland Virtual Monitor Status ===${C_RESET}"
  local has_krdpserver=0
  if command -v krdpserver >/dev/null; then
    has_krdpserver=1
    echo -e "Host Engine (krdp / krdpserver) : ${C_GREEN}INSTALLED${C_RESET}"
  else
    echo -e "Host Engine (krdp / krdpserver) : ${C_YELLOW}MISSING${C_RESET} (Required to host virtual screens)"
  fi

  local has_krdc=0
  if command -v krdc >/dev/null; then
    has_krdc=1
    echo -e "Client Engine (krdc / freerdp)  : ${C_GREEN}INSTALLED${C_RESET}"
  else
    echo -e "Client Engine (krdc / freerdp)  : ${C_YELLOW}MISSING${C_RESET} (Required to render remote streams)"
  fi

  echo ""
  printf "%-14s %-34s %-12s %-14s %-20s\n" "PEER" "DEVICE ID" "VMON READY" "STREAM ACTIVE" "LAST ERROR"
  printf "%-14s %-34s %-12s %-14s %-20s\n" "----" "---------" "----------" "-------------" "----------"

  local dev_list=""
  if ! dev_list="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>&1)"; then
    knot_log_err "Failed to query KDE Connect devices: $dev_list"
    return 1
  fi

  local target_id=""
  if [ -n "$target" ]; then
    if ! target_id="$(kdeconnect_resolve_device_id "$target" 2>&1)"; then
      target_id=""
    fi
  fi

  local count=0
  for dev in $dev_list; do
    if [ -n "$target_id" ] && [ "$dev" != "$target_id" ]; then
      continue
    fi

    local dname=""
    if ! dname="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
      dname="(unknown)"
    fi

    local avail="false"
    local a_out=""
    if a_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.isVirtualMonitorAvailable 2>&1)"; then
      avail="$a_out"
    fi

    local active="false"
    local act_out=""
    if act_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.active 2>&1)"; then
      active="$act_out"
    fi

    local last_err=""
    local err_out=""
    if err_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.lastError 2>&1)"; then
      last_err="$(echo "$err_out" | tr '\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    fi
    [ -z "$last_err" ] && last_err="-"

    local avail_fmt="${C_RED}NO${C_RESET}"
    if [ "$avail" = "true" ]; then
      avail_fmt="${C_GREEN}READY${C_RESET}"
    fi

    local active_fmt="${C_DIM}INACTIVE${C_RESET}"
    if [ "$active" = "true" ]; then
      active_fmt="${C_GREEN}${C_BOLD}ACTIVE${C_RESET}"
    fi

    printf "%-14s %-34s %-21b %-23b %-20s\n" "$dname" "$dev" "$avail_fmt" "$active_fmt" "$last_err"
    count=$((count + 1))
  done

  if [ $count -eq 0 ]; then
    echo "No matching KDE Connect peers found."
  fi
  echo ""
  return 0
}

kdeconnect_vmon_ensure_host_certs() {
  local home
  home="$(knot_detect_user_home)"
  local cert_dir="$home/.local/share/krdpserver"
  local cert_file="$cert_dir/krdp.crt"
  local key_file="$cert_dir/krdp.key"

  if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
    mkdir -p "$cert_dir"
    knot_log_info "Generating local TLS certificate for Wayland Virtual Monitor host (krdpserver)..."
    local gen_out="" gen_rc=0
    gen_out="$(openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$key_file" \
      -out "$cert_file" \
      -days 3650 \
      -subj "/CN=Knot-Mesh-VirtualMonitor" 2>&1)" || gen_rc=$?
    if [ $gen_rc -ne 0 ]; then
      knot_log_err "Failed to generate krdpserver TLS certificate: $gen_out"
      return 1
    fi
    chmod 600 "$key_file"
    chmod 644 "$cert_file"
  fi

  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file krdpserverrc --group General --key Certificate "$cert_file"
    kwriteconfig6 --file krdpserverrc --group General --key CertificateKey "$key_file"
    kwriteconfig6 --file krdpserverrc --group General --key ListeningPort 5900
  fi
  return 0
}

kdeconnect_vmon_seed_client_trust() {
  local target_node="${1:-}"
  local target_port="${2:-22}"
  local target_user="${3:-}"
  local home
  home="$(knot_detect_user_home)"
  local cert_file="$home/.local/share/krdpserver/krdp.crt"

  if [ ! -f "$cert_file" ]; then
    kdeconnect_vmon_ensure_host_certs
  fi

  # 1. Enforce zero-prompt defaults on local client as well
  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file krdcrc --group General --key ShowPreferencesForNewConnections false
    kwriteconfig6 --file krdcrc --group General --key FullscreenOnConnect true
  fi

  # 2. If remote target is specified and reachable, pre-seed FreeRDP certs, KRDC prefs, desktop override, and KWin rules
  if [ -n "$target_node" ] && [ -f "$cert_file" ]; then
    local rip="" r_rc=0
    rip="$("$KNOT_ROOT/bin/knot" resolve "$target_node" "$target_port" 2>&1)" || r_rc=$?
    if [ $r_rc -eq 0 ] && [ -n "$rip" ]; then
      local my_ip
      my_ip="$(knot_detect_lan_ip)"
      local ssh_dest="$target_node"
      if [ -n "$target_user" ] && [ -n "$rip" ]; then
        ssh_dest="${target_user}@${rip}"
      fi

      # 1. Stream knot-vmon-keepalive daemon to remote strand
      if [ -f "$KNOT_ROOT/bin/knot-vmon-keepalive" ]; then
        local ka_out="" ka_rc=0
        ka_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "$target_port" "$ssh_dest" \
          "mkdir -p ~/.local/bin && cat > ~/.local/bin/knot-vmon-keepalive && chmod 755 ~/.local/bin/knot-vmon-keepalive" \
          < "$KNOT_ROOT/bin/knot-vmon-keepalive" 2>&1)" || ka_rc=$?
        if [ $ka_rc -ne 0 ]; then
          knot_log_warn "Notice: Seeding knot-vmon-keepalive returned non-zero ($ka_rc): $ka_out"
        fi
      fi

      local remote_cmd="mkdir -p ~/.config/freerdp/server ~/.local/share/applications && \
cat > ~/.config/freerdp/server/${my_ip}.pem && \
for p in {5900..5950}; do ln -sf ${my_ip}.pem ~/.config/freerdp/server/${my_ip}_\${p}.pem; done && \
cat << 'DESK_EOF' > ~/.local/share/applications/org.kde.krdc.desktop
[Desktop Entry]
Name=KRDC
Exec=/usr/bin/krdc --fullscreen %u
Icon=krdc
Terminal=false
Type=Application
StartupWMClass=krdc
MimeType=x-scheme-handler/vnc;x-scheme-handler/rdp;application/x-krdc;
Categories=Qt;KDE;Network;RemoteAccess;
DESK_EOF
if command -v update-desktop-database >/dev/null; then
  ud_rc=0; update-desktop-database ~/.local/share/applications 2>&1 || ud_rc=\$?
fi
if command -v kwriteconfig6 >/dev/null; then
  kwriteconfig6 --file krdcrc --group General --key ShowPreferencesForNewConnections false
  kwriteconfig6 --file krdcrc --group General --key FullscreenOnConnect true
  kwriteconfig6 --file krdcrc --group RDP --key ScaleToSize true
  for p in {5900..5950}; do
    for h in \"rdp://${my_ip}:\${p}\" \"rdp://user@${my_ip}:\${p}\"; do
      kwriteconfig6 --file krdcrc --group hostpreferences --group \"\$h\" --key scaleToSize true
      kwriteconfig6 --file krdcrc --group hostpreferences --group \"\$h\" --key fullscreenScale true
      kwriteconfig6 --file krdcrc --group hostpreferences --group \"\$h\" --key windowedScale true
      kwriteconfig6 --file krdcrc --group hostpreferences --group \"\$h\" --key showLocalCursor false
    done
  done
  curr_rules=\"\$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>&1)\" || curr_rules=\"\"
  if [[ \",\${curr_rules},\" != *\",krdc_fullscreen,\"* ]]; then
    new_rules=\"\${curr_rules:+\${curr_rules},}krdc_fullscreen\"
    kwriteconfig6 --file kwinrulesrc --group General --key rules \"\$new_rules\"
  fi
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key description \"KRDC Always Fullscreen\"
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key desktopfile \"org.kde.krdc\"
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key desktopfilerule 2
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key wmclass \"org.kde.krdc\"
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key wmclassmatch 2
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key types 1
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key fullscreen true
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key fullscreenrule 2
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key noborder true
  kwriteconfig6 --file kwinrulesrc --group krdc_fullscreen --key noborderrule 2
  if command -v qdbus6 >/dev/null; then
    q_rc=0; qdbus6 org.kde.KWin /KWin reconfigure 2>&1 || q_rc=\$?
  elif command -v qdbus >/dev/null; then
    q_rc=0; qdbus org.kde.KWin /KWin reconfigure 2>&1 || q_rc=\$?
  fi
fi"

      local s_out="" s_rc=0
      s_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "$target_port" "$ssh_dest" "$remote_cmd" < "$cert_file" 2>&1)" || s_rc=$?
      if [ $s_rc -ne 0 ]; then
        knot_log_warn "Notice: Automated FreeRDP trust and KRDC configuration returned non-zero ($s_rc): $s_out"
      fi
    fi
  fi
  return 0
}

kdeconnect_vmon_reconcile_topology_and_scale() {
  local target_node="${1:-}"
  [ -z "$target_node" ] && return 0

  if ! command -v kscreen-doctor >/dev/null; then
    knot_log_warn "kscreen-doctor not available; skipping display topology reconciliation"
    return 0
  fi

  local home
  home="$(knot_detect_user_home)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local topo_file="$home/.config/knot/swarms/${active_swarm}/topology.json"
  if [ ! -f "$topo_file" ]; then
    topo_file="/etc/knot/swarms.d/${active_swarm}/topology.json"
  fi

  knot_log_info "Reconciling display topology and HiDPI scaling for virtual monitor on '$target_node'..."

  local vmon_name="" vmon_w=0 vmon_h=0
  local primary_name="" primary_w=0 primary_h=0 primary_scale=1
  local found=0

  for _ in {1..20}; do
    local js_out="" j_rc=0
    js_out="$(kscreen-doctor -j 2>&1)" || j_rc=$?
    if [ $j_rc -eq 0 ] && [ -n "$js_out" ]; then
      local p_out="" p_rc=0
      p_out="$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    outputs = data.get("outputs", [])
    primary = None
    vmon = None
    for o in outputs:
        name = o.get("name", "")
        if name.startswith("Virtual") and o.get("enabled"):
            vmon = o
        elif o.get("connected") and o.get("enabled") and not name.startswith("Virtual"):
            if primary is None or o.get("priority", 99) < primary.get("priority", 99):
                primary = o
    if vmon and primary:
        v_name = vmon["name"]
        v_w = vmon.get("size", {}).get("width", 3072)
        v_h = vmon.get("size", {}).get("height", 1728)
        p_name = primary["name"]
        p_w = primary.get("size", {}).get("width", 1920)
        p_h = primary.get("size", {}).get("height", 1080)
        p_s = primary.get("scale", 1.0)
        print(f"{v_name}|{v_w}|{v_h}|{p_name}|{p_w}|{p_h}|{p_s}")
except Exception as e:
    sys.stderr.write(f"parse error: {e}\n")
    sys.exit(1)
' "$js_out" 2>&1)" || p_rc=$?
      if [ $p_rc -eq 0 ] && [ -n "$p_out" ]; then
        IFS='|' read -r vmon_name vmon_w vmon_h primary_name primary_w primary_h primary_scale <<< "$p_out"
        found=1
        break
      fi
    fi
    sleep 0.5
  done

  if [ $found -eq 0 ] || [ -z "$vmon_name" ] || [ -z "$primary_name" ]; then
    knot_log_warn "Could not identify virtual and primary outputs in KWin after activation"
    return 0
  fi

  # Determine layout direction from topology.json
  local direction="left"
  if [ -f "$topo_file" ]; then
    local dir_calc="" d_rc=0
    dir_calc="$(python3 -c '
import sys, json, os
topo_file = sys.argv[1]
target = sys.argv[2]
try:
    with open(topo_file) as f:
        topo = json.load(f)
    anchor = topo.get("anchor", "desktop")
    layout = topo.get("layout", {}).get(anchor, {})
    direction = "left"
    for d in ["left", "right", "up", "down"]:
        spec = layout.get(d)
        if isinstance(spec, dict) and spec.get("node") == target:
            direction = d
            break
        elif isinstance(spec, list):
            if any(isinstance(x, dict) and x.get("node") == target for x in spec):
                direction = d
                break
    print(direction)
except Exception:
    print("left")
' "$topo_file" "$target_node" 2>&1)" || d_rc=$?
    if [ $d_rc -eq 0 ] && [ -n "$dir_calc" ]; then
      direction="$dir_calc"
    fi
  fi

  # Calculate target scale & positioning
  local layout_args=""
  layout_args="$(python3 -c '
import sys
vmon_name = sys.argv[1]
v_w = int(sys.argv[2])
v_h = int(sys.argv[3])
primary_name = sys.argv[4]
p_w = int(sys.argv[5])
p_h = int(sys.argv[6])
p_scale = float(sys.argv[7])
direction = sys.argv[8]

v_scale = 2 if v_w >= 2560 else 1
v_log_w = int(round(v_w / v_scale))
v_log_h = int(round(v_h / v_scale))
p_log_w = int(round(p_w / p_scale))
p_log_h = int(round(p_h / p_scale))

# Bottom-align displays to ensure continuous taskbar and boundary alignment
diff_h = v_log_h - p_log_h

if direction == "left":
    if diff_h >= 0:
        v_pos = "0,0"
        p_pos = f"{v_log_w},{diff_h}"
    else:
        v_pos = f"0,{-diff_h}"
        p_pos = f"{v_log_w},0"
elif direction == "right":
    if diff_h >= 0:
        p_pos = f"0,{diff_h}"
        v_pos = f"{p_log_w},0"
    else:
        p_pos = "0,0"
        v_pos = f"{p_log_w},{-diff_h}"
elif direction == "up":
    v_pos = "0,0"
    p_pos = f"0,{v_log_h}"
elif direction == "down":
    p_pos = "0,0"
    v_pos = f"0,{p_log_h}"
else:
    if diff_h >= 0:
        v_pos = "0,0"
        p_pos = f"{v_log_w},{diff_h}"
    else:
        v_pos = f"0,{-diff_h}"
        p_pos = f"{v_log_w},0"

print(f"output.{vmon_name}.scale.{v_scale} output.{vmon_name}.position.{v_pos} output.{primary_name}.position.{p_pos} output.{primary_name}.priority.1|{v_scale}|{v_pos}|{p_pos}|{v_log_w}|{v_log_h}")
' "$vmon_name" "$vmon_w" "$vmon_h" "$primary_name" "$primary_w" "$primary_h" "$primary_scale" "$direction" 2>&1)"

  local ks_args="" v_s="" v_p="" p_p="" v_lw="" v_lh=""
  IFS='|' read -r ks_args v_s v_p p_p v_lw v_lh <<< "$layout_args"

  local ks_out="" ks_rc=0
  # shellcheck disable=SC2086
  ks_out="$(kscreen-doctor $ks_args 2>&1)" || ks_rc=$?
  if [ $ks_rc -ne 0 ]; then
    knot_log_warn "Notice: kscreen-doctor returned $ks_rc: $ks_out"
    return 1
  fi

  knot_log_ok "Harmonized display topology: '$vmon_name' (${vmon_w}x${vmon_h} @ scale ${v_s} -> logical ${v_lw}x${v_lh}) placed $direction at $v_p; primary '$primary_name' at $p_p"
  return 0
}

kdeconnect_vmon_reset_primary_display() {
  if ! command -v kscreen-doctor >/dev/null; then
    return 0
  fi
  local js_out="" j_rc=0
  js_out="$(kscreen-doctor -j 2>&1)" || j_rc=$?
  if [ $j_rc -eq 0 ] && [ -n "$js_out" ]; then
    local p_out="" p_rc=0
    p_out="$(python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
    outputs = data.get("outputs", [])
    primary = None
    for o in outputs:
        name = o.get("name", "")
        if o.get("connected") and o.get("enabled") and not name.startswith("Virtual"):
            if primary is None or o.get("priority", 99) < primary.get("priority", 99):
                primary = o
    if primary:
        print(primary["name"])
except Exception as e:
    sys.stderr.write(f"parse error: {e}\n")
    sys.exit(1)
' "$js_out" 2>&1)" || p_rc=$?
    if [ $p_rc -eq 0 ] && [ -n "$p_out" ]; then
      local k_rc=0
      kscreen-doctor "output.${p_out}.position.0,0" "output.${p_out}.priority.1" 2>&1 || k_rc=$?
      if [ $k_rc -ne 0 ]; then
        knot_log_warn "Notice: kscreen-doctor primary reset returned $k_rc"
      else
        knot_log_ok "Reset primary display '$p_out' to (0,0)."
      fi
    fi
  fi
  return 0
}

kdeconnect_vmon_reconcile_plasma_panel() {
  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    return 0
  fi

  knot_log_info "Ensuring auxiliary Plasma panel on extended virtual display..."

  local script="
var targetScreen = 1;
if (screenCount > 1) {
  var p = panels();
  var found = false;
  var orphanedPanel = null;
  for (var i = 0; i < p.length; ++i) {
    if (p[i].screen === targetScreen) {
      found = true;
      break;
    }
    if (p[i].screen === -1 && p[i].widgets().length >= 4) {
      orphanedPanel = p[i];
    }
  }
  if (!found) {
    if (orphanedPanel) {
      orphanedPanel.screen = targetScreen;
      print('re-attached');
    } else {
      var panel = new Panel;
      panel.screen = targetScreen;
      panel.location = 'bottom';
      panel.height = 44;
      panel.addWidget('org.kde.plasma.kickoff');
      panel.addWidget('org.kde.plasma.pager');
      panel.addWidget('org.kde.plasma.icontasks');
      panel.addWidget('org.kde.plasma.marginsseparator');
      panel.addWidget('org.kde.plasma.systemtray');
      panel.addWidget('org.kde.plasma.digitalclock');
      panel.addWidget('org.kde.plasma.showdesktop');
      print('created');
    }
  } else {
    print('already_present');
  }
} else {
  print('single_screen');
}
"
  # Poll up to 10 times (5 seconds) waiting for Plasma to see the extended screen
  local res="" r_rc=0
  for _ in {1..10}; do
    res="$("$qdbus_cmd" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$script" 2>&1)" || r_rc=$?
    if [ $r_rc -eq 0 ] && [ "$res" != "single_screen" ]; then
      break
    fi
    sleep 0.5
  done

  case "$res" in
    re-attached)
      knot_log_ok "Restored persistent Plasma panel to virtual display."
      ;;
    created)
      knot_log_ok "Provisioned auxiliary Plasma panel on virtual display."
      ;;
    already_present)
      knot_log_info "Plasma panel already active on virtual display."
      ;;
    *)
      knot_log_info "Plasma auxiliary panel status: $res"
      ;;
  esac
  return 0
}

kdeconnect_vmon_start() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: knot kdeconnect vmon start <node_id|device_id>"
    return 1
  fi

  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_err "qdbus/qdbus6 command not found"
    return 1
  fi

  # 1. Verify local host prerequisites
  if ! command -v krdpserver >/dev/null; then
    knot_log_err "Local host lacks 'krdpserver' (from package 'krdp'). Run 'sudo pacman -S krdp' or 'knot repair local'."
    return 1
  fi

  # 2. Ensure local host TLS certificates & configuration for krdpserver
  kdeconnect_vmon_ensure_host_certs

  # 3. Verify firewall rules for ports 5900-5910/tcp
  local fw_mod="$KNOT_ROOT/core/modules/firewall.sh"
  if [ -f "$fw_mod" ]; then
    # shellcheck source=../../core/modules/firewall.sh
    source "$fw_mod"
    firewall_verify_vmon
  fi

  # 4. Resolve target node manifest & seed zero-prompt client trust
  local target_node=""
  local target_port=22
  local target_user=""
  local home
  home="$(knot_detect_user_home)"
  for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
    [ -d "$d" ] || continue
    for mf in "$d/"*.json; do
      [ -e "$mf" ] || continue
      local nid nhost nport nuser
      nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
      nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$mf")"
      nport="$(awk -F': ' '/"port":/ {print $2}' "$mf" | tr -d ', ')"
      nuser="$(awk -F'"' '/"user":/ {print $4}' "$mf")"
      if [ "$nid" = "$target" ] || [ "$nhost" = "$target" ]; then
        target_node="$nid"
        target_port="${nport:-22}"
        target_user="$nuser"
        break 2
      fi
    done
  done

  if [ -n "$target_node" ]; then
    kdeconnect_vmon_seed_client_trust "$target_node" "$target_port" "$target_user"
    # Launch remote keepalive daemon to ensure strand session remains unlocked and active
    local rip="" r_rc=0
    rip="$("$KNOT_ROOT/bin/knot" resolve "$target_node" "$target_port" 2>&1)" || r_rc=$?
    if [ $r_rc -eq 0 ] && [ -n "$rip" ]; then
      local ssh_dest="$target_node"
      if [ -n "${target_user:-}" ] && [ -n "$rip" ]; then
        ssh_dest="${target_user}@${rip}"
      fi
      local k_rc=0
      ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -p "$target_port" "$ssh_dest" \
        "mkdir -p ~/.local/state/knot && nohup python3 ~/.local/bin/knot-vmon-keepalive </dev/null > ~/.local/state/knot/vmon-keepalive.log 2>&1 &" || k_rc=$?
      if [ $k_rc -ne 0 ]; then
        knot_log_warn "Notice: Spawning knot-vmon-keepalive on '$target_node' returned non-zero: $k_rc"
      fi
    fi
  fi

  # 5. Resolve target device ID
  local target_id=""
  if ! target_id="$(kdeconnect_resolve_device_id "$target" 2>&1)"; then
    knot_log_err "Could not resolve target '$target' to a paired KDE Connect device ID."
    return 1
  fi

  local dev_name=""
  if ! dev_name="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id" org.kde.kdeconnect.device.name 2>&1)"; then
    dev_name="$target"
  fi

  knot_log_info "Initiating Wayland Virtual Monitor stream to '$dev_name' ($target_id)..."

  # 6. Check readiness on remote device
  local avail="false"
  local a_out=""
  if a_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.isVirtualMonitorAvailable 2>&1)"; then
    avail="$a_out"
  fi

  if [ "$avail" != "true" ]; then
    local err_msg=""
    if ! err_msg="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.lastError 2>&1)"; then
      err_msg=""
    fi
    knot_log_err "Target '$dev_name' is not ready for Virtual Monitor: ${err_msg:-Remote client missing RDP client or krdc}"
    return 1
  fi

  # 7. Request Virtual Monitor
  local req_out="" req_rc=0
  req_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.requestVirtualMonitor 2>&1)" || req_rc=$?

  if [ $req_rc -ne 0 ]; then
    knot_log_err "Failed to invoke requestVirtualMonitor on DBus: $req_out"
    return 1
  fi

  if [ "$req_out" != "true" ]; then
    local err_msg=""
    if ! err_msg="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.lastError 2>&1)"; then
      err_msg=""
    fi
    knot_log_err "Virtual Monitor request was rejected by KDE Connect: ${err_msg:-Unknown error}"
    return 1
  fi

  # 8. Verify stream activation
  local is_active=0
  for _ in {1..10}; do
    sleep 0.5
    local act_chk=""
    if act_chk="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.active 2>&1)"; then
      if [ "$act_chk" = "true" ]; then
        is_active=1
        break
      fi
    fi
  done

  if [ $is_active -eq 1 ]; then
    knot_log_ok "Wayland Virtual Monitor active! KWin virtual display created and streaming to '$dev_name' via RDP."

    # 9. Reconcile topology placement and HiDPI scaling
    kdeconnect_vmon_reconcile_topology_and_scale "$target_node"

    # 10. Reconcile persistent Plasma panel
    kdeconnect_vmon_reconcile_plasma_panel

    # 11. Mute Deskflow KVM crossover to target node (prevent boundary conflicts)
    if [ -n "$target_node" ]; then
      local df_mod="$KNOT_ROOT/core/modules/deskflow.sh"
      if [ -f "$df_mod" ]; then
        # shellcheck source=../../core/modules/deskflow.sh
        source "$df_mod"
        deskflow_mute_node "$target_node"
        knot_log_info "Deskflow KVM crossover to '$target_node' muted (use 'knot display toggle-kvm' to switch)"
      fi
    fi

    echo -e "${C_DIM}Run 'knot display stop $target' to teardown the virtual monitor stream.${C_RESET}"
    return 0
  else
    local err_msg=""
    if ! err_msg="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$target_id/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.lastError 2>&1)"; then
      err_msg=""
    fi
    knot_log_warn "Virtual Monitor request dispatched, but active stream state not yet confirmed: ${err_msg:-waiting for client connection}"
    return 0
  fi
}

kdeconnect_vmon_stop() {
  local target="${1:-}"
  local qdbus_cmd=""
  if ! qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    knot_log_err "qdbus/qdbus6 command not found"
    return 1
  fi

  local dev_list=""
  if ! dev_list="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices true true 2>&1)"; then
    knot_log_err "Failed to query KDE Connect devices: $dev_list"
    return 1
  fi

  local target_id=""
  local target_node=""
  local target_port=22
  local target_user=""
  local home
  home="$(knot_detect_user_home)"

  if [ -n "$target" ]; then
    for d in "$home/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
      [ -d "$d" ] || continue
      for mf in "$d/"*.json; do
        [ -e "$mf" ] || continue
        local nid nhost nport nuser
        nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
        nhost="$(awk -F'"' '/"hostname":/ {print $4}' "$mf")"
        nport="$(awk -F': ' '/"port":/ {print $2}' "$mf" | tr -d ', ')"
        nuser="$(awk -F'"' '/"user":/ {print $4}' "$mf")"
        if [ "$nid" = "$target" ] || [ "$nhost" = "$target" ]; then
          target_node="$nid"
          target_port="${nport:-22}"
          target_user="$nuser"
          break 2
        fi
      done
    done

    if ! target_id="$(kdeconnect_resolve_device_id "$target" 2>&1)"; then
      knot_log_err "Could not resolve target '$target' to a paired KDE Connect device ID."
      return 1
    fi
  fi

  local stopped_any=0
  for dev in $dev_list; do
    if [ -n "$target_id" ] && [ "$dev" != "$target_id" ]; then
      continue
    fi

    local dname=""
    if ! dname="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)"; then
      dname="$dev"
    fi

    local active="false"
    local act_out=""
    if act_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.active 2>&1)"; then
      active="$act_out"
    fi

    if [ "$active" = "true" ] || [ -n "$target" ]; then
      knot_log_info "Stopping Virtual Monitor stream for '$dname' ($dev)..."
      local stop_out=""
      if ! stop_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.stop 2>&1)"; then
        knot_log_warn "Notice: stop returned: $stop_out"
      fi
      knot_log_ok "Virtual Monitor stopped for '$dname'."
      stopped_any=1
    fi
  done

  # 1. Reset primary display coordinates in KWin (if shifted)
  kdeconnect_vmon_reset_primary_display

  # 2. Unmute Deskflow KVM crossover
  local df_mod="$KNOT_ROOT/core/modules/deskflow.sh"
  if [ -f "$df_mod" ]; then
    # shellcheck source=../../core/modules/deskflow.sh
    source "$df_mod"
    if [ -n "$target_node" ]; then
      deskflow_unmute_node "$target_node"
      knot_log_info "Deskflow KVM crossover to '$target_node' unmuted"
    else
      for f in /run/knot/vmon_muted_deskflow_*; do
        [ -e "$f" ] || continue
        local nid="${f##*vmon_muted_deskflow_}"
        deskflow_unmute_node "$nid"
      done
    fi
  fi

  # 3. Remote viewer cleanup if target is a known swarm node
  if [ -n "$target_node" ]; then
    local rip="" r_rc=0
    rip="$("$KNOT_ROOT/bin/knot" resolve "$target_node" "$target_port" 2>&1)" || r_rc=$?
    if [ $r_rc -eq 0 ] && [ -n "$rip" ]; then
      local ssh_dest="$target_node"
      if [ -n "${target_user:-}" ] && [ -n "$rip" ]; then
        ssh_dest="${target_user}@${rip}"
      fi
      local my_ip
      my_ip="$(knot_detect_lan_ip)"
      local k_rc=0
      ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new -p "$target_port" "$ssh_dest" \
        "pid_file=\"/run/user/\$(id -u)/knot-vmon-keepalive.pid\"; if [ -f \"\$pid_file\" ]; then k_pid=\$(cat \"\$pid_file\"); kill \"\$k_pid\" 2>&1 || k_rc=\$?; rm -f \"\$pid_file\"; fi; pkill -f 'krdc.*rdp://.*${my_ip}' 2>&1 || k_rc=\$?" || k_rc=$?
    fi
  fi

  if [ $stopped_any -eq 0 ]; then
    knot_log_info "No active Virtual Monitor streams were found running."
  fi
  return 0
}
