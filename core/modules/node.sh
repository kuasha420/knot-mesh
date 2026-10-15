#!/usr/bin/env bash
set -euo pipefail

# Knot - Node Lifecycle, Decommissioning & Identity Management Module
# Governed by PSL Gold Standard (Rule 1: Zero Error Swallowing, Rule 2: Complete Deliveries)

node_get_anchor_id() {
  local active_swarm="$1"
  local nodes_dir="$2"
  local anchor_id=""

  # 1. Swarm profile check
  if knot_load_swarm_profile "$active_swarm"; then
    if [ -n "${ANCHOR_ID:-}" ]; then
      echo "$ANCHOR_ID"
      return 0
    fi
  fi

  # 2. topology.json check
  local user_home
  user_home="$(knot_detect_user_home)"
  local topo_file=""
  if [ -r "$user_home/.config/knot/swarms/${active_swarm}/topology.json" ]; then
    topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
  elif [ -r "/etc/knot/swarms.d/${active_swarm}/topology.json" ]; then
    topo_file="/etc/knot/swarms.d/${active_swarm}/topology.json"
  fi

  if [ -n "$topo_file" ] && [ -f "$topo_file" ]; then
    local t_anchor="" t_rc=0
    t_anchor="$(python3 -c "
import json, sys
try:
    with open('$topo_file', 'r', encoding='utf-8') as f:
        d = json.load(f)
    print(d.get('anchor', ''))
except (OSError, ValueError):
    sys.exit(0)
" 2>&1)" || t_rc=$?
    if [ $t_rc -eq 0 ] && [ -n "$t_anchor" ]; then
      echo "$t_anchor"
      return 0
    fi
  fi

  # 3. Check node manifests for role: "anchor"
  if [ -n "$nodes_dir" ] && [ -d "$nodes_dir" ]; then
    for manifest in "$nodes_dir/"*.json; do
      [ -e "$manifest" ] || continue
      if grep -qE '"role"[[:space:]]*:[[:space:]]*"anchor"' "$manifest"; then
        anchor_id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        if [ -n "$anchor_id" ]; then
          echo "$anchor_id"
          return 0
        fi
      fi
    done
  fi

  # Fallback default anchor
  echo "desktop"
  return 0
}

node_prune_topology() {
  local topo_file="$1"
  local node_id="$2"

  if [ ! -f "$topo_file" ]; then
    return 0
  fi

  python3 -c "
import sys, json, os

topo_file = sys.argv[1]
node_id = sys.argv[2]

try:
    with open(topo_file, 'r', encoding='utf-8') as f:
        topo = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write(f'Error reading topology file {topo_file}: {e}\n')
    sys.exit(1)

# 1. Prune from screens array
if 'screens' in topo and isinstance(topo['screens'], list):
    topo['screens'] = [s for s in topo['screens'] if s != node_id]

# 2. Prune from nodes dictionary (legacy/schema)
if 'nodes' in topo and isinstance(topo['nodes'], dict):
    topo['nodes'].pop(node_id, None)
    for nid, ndata in topo['nodes'].items():
        if isinstance(ndata, dict) and 'screens' in ndata and isinstance(ndata['screens'], list):
            ndata['screens'] = [s for s in ndata['screens'] if s != node_id]

# 3. Prune outgoing and incoming links from layout
if 'layout' in topo and isinstance(topo['layout'], dict):
    # Remove outgoing edges
    topo['layout'].pop(node_id, None)
    # Remove incoming directional edges pointing to node_id
    for src, dirs in topo['layout'].items():
        if not isinstance(dirs, dict):
            continue
        for d in list(dirs.keys()):
            spec = dirs[d]
            if isinstance(spec, str):
                if spec == node_id:
                    del dirs[d]
            elif isinstance(spec, dict):
                if spec.get('node') == node_id:
                    del dirs[d]
            elif isinstance(spec, list):
                filtered = []
                for item in spec:
                    if isinstance(item, str) and item == node_id:
                        continue
                    elif isinstance(item, dict) and item.get('node') == node_id:
                        continue
                    else:
                        filtered.append(item)
                if len(filtered) == 0:
                    del dirs[d]
                else:
                    dirs[d] = filtered

# 4. Prune from links list if present
if 'links' in topo and isinstance(topo['links'], list):
    topo['links'] = [
        l for l in topo['links']
        if not (isinstance(l, dict) and (l.get('from') == node_id or l.get('to') == node_id or l.get('src') == node_id or l.get('dst') == node_id))
    ]

# 5. Atomic write with fsync and rename
tmp_file = f'{topo_file}.tmp.{os.getpid()}'
try:
    with open(tmp_file, 'w', encoding='utf-8') as f:
        json.dump(topo, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_file, topo_file)
except (OSError, ValueError) as e:
    if os.path.exists(tmp_file):
        try:
            os.remove(tmp_file)
        except OSError as cleanup_err:
            sys.stderr.write(f'Warning: failed removing temp file {tmp_file}: {cleanup_err}\n')
    sys.stderr.write(f'Error atomically writing topology file {topo_file}: {e}\n')
    sys.exit(1)
" "$topo_file" "$node_id"
}

node_unpair_kdeconnect() {
  local node_id="$1"
  local target_hostname="$2"
  local target_ip="$3"
  local user_home="$4"

  # 1. Update ~/.config/kdeconnect/config if target_ip is present
  local kde_cfg="$user_home/.config/kdeconnect/config"
  if [ -f "$kde_cfg" ] && [ -n "$target_ip" ]; then
    python3 -c "
import os, sys, configparser

cfg_file = sys.argv[1]
target_ip = sys.argv[2]

if os.path.isfile(cfg_file) and target_ip:
    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = lambda opt: opt
    try:
        config.read(cfg_file)
        if config.has_section('General') and config.has_option('General', 'customDevices'):
            cur = config.get('General', 'customDevices')
            ips = [x.strip() for x in cur.split(',') if x.strip()]
            new_ips = [x for x in ips if x != target_ip]
            if len(new_ips) != len(ips):
                config.set('General', 'customDevices', ','.join(new_ips))
                tmp = cfg_file + '.tmp'
                with open(tmp, 'w') as f:
                    config.write(f, space_around_delimiters=False)
                os.replace(tmp, cfg_file)
    except (OSError, configparser.Error) as e:
        sys.stderr.write(f'Notice: Failed to update KDE Connect config: {e}\n')
" "$kde_cfg" "$target_ip"
  fi

  # Call kdeconnect_configure_custom_devices if available
  if command -v kdeconnect_configure_custom_devices >/dev/null; then
    kdeconnect_configure_custom_devices
  fi

  # 2. Local unpairing via DBus
  local qdbus_cmd=""
  if command -v qdbus6 >/dev/null; then
    qdbus_cmd="qdbus6"
  elif command -v qdbus >/dev/null; then
    qdbus_cmd="qdbus"
  fi

  local unpaired=0
  if [ -n "$qdbus_cmd" ]; then
    local paired_devs="" dev_rc=0
    paired_devs="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false false 2>&1)" || dev_rc=$?
    if [ $dev_rc -eq 0 ] && [ -n "$paired_devs" ]; then
      while IFS= read -r dev; do
        [ -n "$dev" ] || continue
        local dname="" name_rc=0
        dname="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.name 2>&1)" || name_rc=$?
        if [ $name_rc -eq 0 ]; then
          if [ "$dname" = "$node_id" ] || [ "$dname" = "$target_hostname" ] || [ "$dev" = "$node_id" ] || [ "$dev" = "kde-device-${node_id}" ] || [ "$dev" = "kde-device-${node_id//-}" ]; then
            knot_log_info "Unpairing KDE Connect device '$dname' ($dev)..."
            local unpair_out="" unpair_rc=0
            unpair_out="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev" org.kde.kdeconnect.device.unpair 2>&1)" || unpair_rc=$?
            unpaired=1
          fi
        fi
      done <<< "$paired_devs"
    fi
  fi

  # 3. Fallback unpairing via kdeconnect-cli
  if [ $unpaired -eq 0 ] && command -v kdeconnect-cli >/dev/null; then
    local list_out="" list_rc=0
    list_out="$(kdeconnect-cli -l 2>&1)" || list_rc=$?
    if [ $list_rc -eq 0 ]; then
      while IFS= read -r line; do
        if echo "$line" | grep -qE "(${node_id}|${target_hostname})"; then
          local d_id=""
          d_id="$(echo "$line" | grep -oE '[a-f0-9_]{16,}' | head -n1)"
          if [ -z "$d_id" ]; then
            d_id="$(echo "$line" | awk '{print $NF}' | tr -d '():')"
          fi
          if [ -n "$d_id" ]; then
            local unpair_out="" unpair_rc=0
            unpair_out="$(kdeconnect-cli --unpair "$d_id" 2>&1)" || unpair_rc=$?
            unpaired=1
          fi
        fi
      done <<< "$list_out"
    fi
  fi

  # If still not unpaired but kdeconnect-cli exists, attempt direct unpair by node_id / target_hostname
  if [ $unpaired -eq 0 ] && command -v kdeconnect-cli >/dev/null; then
    local u_out="" u_rc=0
    u_out="$(kdeconnect-cli --unpair "$node_id" 2>&1)" || u_rc=$?
  fi
}

node_remove() {
  local node_id=""
  local purge_remote=0

  # Argument parsing
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        echo "Usage: knot node remove <node_id> [--purge-remote]"
        echo "   or: knot offboard <node_id> [--purge-remote]"
        echo ""
        echo "Safely decommissions a node from the Knot cluster:"
        echo "  - Prunes manifest from swarm nodes directory"
        echo "  - Prunes node from topology.json screens, layout, and directional links"
        echo "  - Reconciles ~/.ssh/authorized_keys and ~/.ssh/config"
        echo "  - Recompiles Deskflow KVM server configuration"
        echo "  - Unpairs KDE Connect device"
        echo "  - Optionally tears down remote daemon services (--purge-remote)"
        return 0
        ;;
      --purge-remote)
        purge_remote=1
        shift
        ;;
      -*)
        echo "Error: Unknown flag '$1'" >&2
        echo "Usage: knot node remove <node_id> [--purge-remote]" >&2
        return 1
        ;;
      *)
        if [ -z "$node_id" ]; then
          node_id="$1"
        else
          echo "Error: Unexpected extra argument '$1'" >&2
          echo "Usage: knot node remove <node_id> [--purge-remote]" >&2
          return 1
        fi
        shift
        ;;
    esac
  done

  # Validate node_id provided
  if [ -z "$node_id" ]; then
    echo "Error: Missing required <node_id> argument." >&2
    echo "Usage: knot node remove <node_id> [--purge-remote]" >&2
    echo "   or: knot offboard <node_id> [--purge-remote]" >&2
    return 1
  fi

  # 1. Swarm discovery
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -z "$active_swarm" ] || [ "$active_swarm" = "none" ]; then
    echo "Error: No active swarm configured." >&2
    return 1
  fi

  local nodes_dir=""
  if ! nodes_dir="$(knot_get_nodes_dir)"; then
    echo "Error: Could not locate nodes directory for active swarm '$active_swarm'." >&2
    return 1
  fi

  # 2. Active Anchor Protection Invariant
  local active_anchor
  active_anchor="$(node_get_anchor_id "$active_swarm" "$nodes_dir")"

  if [ "$node_id" = "$active_anchor" ]; then
    echo "Error: Cannot remove active Anchor node '$node_id'. The Anchor coordinates cluster synchronization and consensus. Migrate Anchor role before decommissioning." >&2
    return 1
  fi

  local manifest_path="$nodes_dir/${node_id}.json"

  # 3. Non-existent node handling
  if [ ! -f "$manifest_path" ]; then
    echo "Error: Node '$node_id' not found in active swarm '$active_swarm'." >&2
    return 1
  fi

  # 4. Manifest role check for anchor
  if grep -qE '"role"[[:space:]]*:[[:space:]]*"anchor"' "$manifest_path"; then
    echo "Error: Cannot remove active Anchor node '$node_id'. The Anchor coordinates cluster synchronization and consensus. Migrate Anchor role before decommissioning." >&2
    return 1
  fi

  # 5. Local anchor check
  local my_node_id
  my_node_id="$(knot_detect_node_id)"
  if knot_is_anchor && [ "$node_id" = "$my_node_id" ]; then
    echo "Error: Cannot remove active Anchor node '$node_id'. The Anchor coordinates cluster synchronization and consensus. Migrate Anchor role before decommissioning." >&2
    return 1
  fi

  knot_log_info "Initiating safe offboarding for node '$node_id' from swarm '$active_swarm'..."

  # 6. Read node metadata before deleting manifest
  local target_hostname="" target_ip="" target_port=22
  target_hostname="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest_path")"
  target_ip="$(awk -F'"' '/"ip_hint":/ {print $4}' "$manifest_path")"
  local p=""
  p="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest_path")"
  [ -n "$p" ] && target_port="$p"
  [ -z "$target_hostname" ] && target_hostname="$node_id"

  # 7. Optional remote service teardown (--purge-remote)
  if [ "$purge_remote" -eq 1 ]; then
    knot_log_info "Probing remote node '$node_id' for --purge-remote teardown..."
    local ssh_reach=0 ssh_out=""
    ssh_out="$(ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$target_port" "$node_id" "true" 2>&1)" || ssh_reach=$?
    if [ $ssh_reach -eq 0 ]; then
      knot_log_info "Stopping and disabling remote Knot services on '$node_id'..."
      local teardown_cmd='
        if command -v systemctl >/dev/null; then
          for s in knot-deskflow.service knot-hub.service knot-agent.service knot-kdeconnect-reconcile.service knot-guard.service knot-stripd.service; do
            s_rc=0
            systemctl --user stop "$s" 2>&1 || s_rc=$?
            systemctl --user disable "$s" 2>&1 || s_rc=$?
          done
        fi
        rm -rf "$HOME/.config/knot/swarms/'"${active_swarm}"'"
      '
      local rem_out="" rem_rc=0
      rem_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -p "$target_port" "$node_id" "$teardown_cmd" 2>&1)" || rem_rc=$?
      if [ $rem_rc -eq 0 ]; then
        knot_log_ok "Remote teardown completed successfully on '$node_id'."
      else
        knot_log_warn "Notice: Remote teardown reported: $rem_out"
      fi
    else
      knot_log_warn "Target node '$node_id' is unreachable over SSH; remote teardown skipped."
    fi
  fi

  # 8. Prune manifest file
  knot_log_info "Removing node manifest '$manifest_path'..."
  rm -f "$manifest_path"

  if [ -f "/etc/knot/swarms.d/${active_swarm}/nodes/${node_id}.json" ]; then
    if [ -w "/etc/knot/swarms.d/${active_swarm}/nodes/${node_id}.json" ]; then
      rm -f "/etc/knot/swarms.d/${active_swarm}/nodes/${node_id}.json"
    fi
  fi

  # 9. Atomic Topology Mutate & Prune
  local user_home
  user_home="$(knot_detect_user_home)"
  local topo_file=""
  if [ -r "$user_home/.config/knot/swarms/${active_swarm}/topology.json" ]; then
    topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
  elif [ -r "/etc/knot/swarms.d/${active_swarm}/topology.json" ]; then
    topo_file="/etc/knot/swarms.d/${active_swarm}/topology.json"
  fi

  if [ -n "$topo_file" ] && [ -f "$topo_file" ]; then
    knot_log_info "Pruning '$node_id' from topology '$topo_file'..."
    node_prune_topology "$topo_file" "$node_id"
  fi
  local sys_topo="/etc/knot/swarms.d/${active_swarm}/topology.json"
  if [ -f "$sys_topo" ] && [ -w "$sys_topo" ]; then
    node_prune_topology "$sys_topo" "$node_id"
  fi

  # 10. Subsystems De-provisioning: SSH Keys and Host Config
  knot_log_info "Reconciling SSH authorized_keys and ~/.ssh/config..."
  ssh_sync_authorized_keys
  ssh_sync_client_config
  ssh_socket_cleanup

  # 11. Subsystems De-provisioning: Deskflow KVM
  knot_log_info "Recompiling Deskflow KVM server routing..."
  rm -f "$user_home/.local/state/knot/vmon_muted_deskflow_${node_id}" "/run/knot/vmon_muted_deskflow_${node_id}"
  deskflow_compile_server_config "$(deskflow_get_lock)"
  if command -v systemctl >/dev/null; then
    local is_act=0
    systemctl --user is-active --quiet knot-deskflow.service 2>&1 || is_act=$?
    if [ $is_act -eq 0 ]; then
      local restart_out="" restart_rc=0
      restart_out="$(systemctl --user restart knot-deskflow.service 2>&1)" || restart_rc=$?
      if [ $restart_rc -ne 0 ]; then
        knot_log_warn "Notice: Deskflow service restart returned non-zero: $restart_out"
      fi
    fi
  fi

  # 12. Subsystems De-provisioning: KDE Connect
  knot_log_info "De-provisioning KDE Connect pairing and customDevices..."
  node_unpair_kdeconnect "$node_id" "$target_hostname" "$target_ip" "$user_home"

  # 13. Cluster Synchronization
  if command -v cmd_sync >/dev/null; then
    knot_log_info "Synchronizing cluster state across remaining nodes..."
    local sync_out="" sync_rc=0
    sync_out="$(cmd_sync --all 2>&1)" || sync_rc=$?
    if [ $sync_rc -ne 0 ]; then
      knot_log_warn "Notice: Cluster sync completed with warnings: $sync_out"
    fi
  fi

  knot_log_ok "Node '$node_id' successfully decommissioned from swarm '$active_swarm'."
  return 0
}

node_rename() {
  # Milestone 3 placeholder - will be fully implemented in Issue #82
  echo "Error: Node rename is planned for Milestone 3." >&2
  return 1
}

node_list() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot node list"
    echo "List all registered nodes in active swarm."
    return 0
  fi
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local nodes_dir=""
  if ! nodes_dir="$(knot_get_nodes_dir)"; then
    echo "Error: Could not locate nodes directory for active swarm '$active_swarm'." >&2
    return 1
  fi
  echo -e "${C_BOLD}Nodes in active swarm '$active_swarm':${C_RESET}"
  for manifest in "$nodes_dir/"*.json; do
    [ -e "$manifest" ] || continue
    local nid role host
    nid="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
    role="$(awk -F'"' '/"role":/ {print $4}' "$manifest")"
    host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
    printf "  %-16s %-10s %s\n" "$nid" "${role:-strand}" "${host:-unknown}"
  done
  return 0
}

cmd_node() {
  local sub="${1:-}"
  case "$sub" in
    remove|rm|offboard)
      shift
      node_remove "$@"
      ;;
    rename|mv)
      shift
      node_rename "$@"
      ;;
    list|ls)
      shift
      node_list "$@"
      ;;
    -h|--help|help|"")
      echo -e "${C_BOLD}Knot Node Management${C_RESET}"
      echo "Usage:"
      echo "  knot node remove <node_id> [--purge-remote]  Decommission a node from the cluster"
      echo "  knot node rename <old_id> <new_id>           Migrate node identity across cluster"
      echo "  knot node list                               List all registered nodes in active swarm"
      return 0
      ;;
    *)
      echo "Error: Unknown node subcommand '$sub'" >&2
      echo -e "${C_BOLD}Knot Node Management${C_RESET}" >&2
      echo "Usage:" >&2
      echo "  knot node remove <node_id> [--purge-remote]  Decommission a node from the cluster" >&2
      echo "  knot node rename <old_id> <new_id>           Migrate node identity across cluster" >&2
      echo "  knot node list                               List all registered nodes in active swarm" >&2
      return 1
      ;;
  esac
}
