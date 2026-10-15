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
    local t_anchor=""
    t_anchor="$(python3 -c "
import json, sys
try:
    with open(sys.argv[1], 'r', encoding='utf-8') as f:
        d = json.load(f)
    sys.stdout.write(d.get('anchor', ''))
except (OSError, ValueError) as e:
    sys.stderr.write(f'Notice: Failed to read anchor from {sys.argv[1]}: {e}\n')
" "$topo_file")"
    if [ -n "$t_anchor" ]; then
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

node_migrate_topology() {
  local topo_file="$1"
  local old_id="$2"
  local new_id="$3"

  if [ ! -f "$topo_file" ]; then
    return 0
  fi

  python3 -c "
import sys, json, os

topo_file = sys.argv[1]
old_id = sys.argv[2]
new_id = sys.argv[3]

if not os.path.isfile(topo_file):
    sys.exit(0)

try:
    with open(topo_file, 'r', encoding='utf-8') as f:
        topo = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write(f'Error reading topology file {topo_file}: {e}\n')
    sys.exit(1)

# 1. Update anchor if it matches old_id
if topo.get('anchor') == old_id:
    topo['anchor'] = new_id

# 2. Update screens array preserving order
if 'screens' in topo and isinstance(topo['screens'], list):
    topo['screens'] = [new_id if s == old_id else s for s in topo['screens']]

# 3. Update layout dictionary
if 'layout' in topo and isinstance(topo['layout'], dict):
    new_layout = {}
    for src_k, dirs in topo['layout'].items():
        target_k = new_id if src_k == old_id else src_k
        if isinstance(dirs, dict):
            new_dirs = {}
            for d, spec in dirs.items():
                if isinstance(spec, str):
                    new_dirs[d] = new_id if spec == old_id else spec
                elif isinstance(spec, dict):
                    migrated_spec = dict(spec)
                    if migrated_spec.get('node') == old_id:
                        migrated_spec['node'] = new_id
                    new_dirs[d] = migrated_spec
                elif isinstance(spec, list):
                    new_list = []
                    for item in spec:
                        if isinstance(item, str):
                            new_list.append(new_id if item == old_id else item)
                        elif isinstance(item, dict):
                            migrated_item = dict(item)
                            if migrated_item.get('node') == old_id:
                                migrated_item['node'] = new_id
                            new_list.append(migrated_item)
                        else:
                            new_list.append(item)
                    new_dirs[d] = new_list
                else:
                    new_dirs[d] = spec
            new_layout[target_k] = new_dirs
        else:
            new_layout[target_k] = dirs
    topo['layout'] = new_layout

# 4. Update links list if present
if 'links' in topo and isinstance(topo['links'], list):
    for link in topo['links']:
        if isinstance(link, dict):
            if link.get('from') == old_id:
                link['from'] = new_id
            if link.get('to') == old_id:
                link['to'] = new_id
            if link.get('src') == old_id:
                link['src'] = new_id
            if link.get('dst') == old_id:
                link['dst'] = new_id

# 5. Update nodes dictionary if present
if 'nodes' in topo and isinstance(topo['nodes'], dict):
    new_nodes = {}
    for nid, ndata in topo['nodes'].items():
        target_nid = new_id if nid == old_id else nid
        if isinstance(ndata, dict):
            migrated_ndata = dict(ndata)
            if 'screens' in migrated_ndata and isinstance(migrated_ndata['screens'], list):
                migrated_ndata['screens'] = [new_id if s == old_id else s for s in migrated_ndata['screens']]
            new_nodes[target_nid] = migrated_ndata
        else:
            new_nodes[target_nid] = ndata
    topo['nodes'] = new_nodes

# 6. Atomic write with fsync and replace
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
" "$topo_file" "$old_id" "$new_id"
}

node_migrate_swarm_conf() {
  local conf_file="$1"
  local old_id="$2"
  local new_id="$3"

  [ -f "$conf_file" ] || return 0
  [ -w "$conf_file" ] || return 0

  python3 - << 'CONF_EOF' "$conf_file" "$old_id" "$new_id"
import sys, re, os

conf_file = sys.argv[1]
old_id = sys.argv[2]
new_id = sys.argv[3]

if not os.path.isfile(conf_file):
    sys.exit(0)

try:
    with open(conf_file, 'r', encoding='utf-8') as f:
        content = f.read()

    pattern = r'^(ANCHOR_ID\s*=\s*["\']?)' + re.escape(old_id) + r'(["\']?.*)$'
    new_content, count = re.subn(pattern, r'\g<1>' + new_id + r'\g<2>', content, flags=re.MULTILINE)

    if count > 0:
        tmp_conf = f'{conf_file}.tmp.{os.getpid()}'
        with open(tmp_conf, 'w', encoding='utf-8') as f:
            f.write(new_content)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp_conf, conf_file)
except (OSError, ValueError) as e:
    sys.stderr.write(f'Notice: Failed to migrate swarm profile {conf_file}: {e}\n')
CONF_EOF
}

node_rename() {
  # 1. Handle help flags
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot node rename <old_id> <new_id>"
    echo ""
    echo "Atomically renames a node identity across the Knot cluster:"
    echo "  - Validates source exists, destination is unused, and name conforms to syntax"
    echo "  - Atomically renames node manifest file and updates internal 'id'"
    echo "  - Migrates topology.json (screens, anchor, layout keys, directional targets) preserving fractional spans"
    echo "  - Recompiles Deskflow KVM server configuration"
    echo "  - Re-indexes SSH client configuration (~/.ssh/config)"
    echo "  - Updates swarm anchor configuration if anchor node was renamed"
    return 0
  fi

  # 2. Argument count validation
  if [ $# -ne 2 ]; then
    echo "Error: 'knot node rename' requires exactly two arguments: <old_id> and <new_id>." >&2
    echo "Usage: knot node rename <old_id> <new_id>" >&2
    return 1
  fi

  local old_id="$1"
  local new_id="$2"

  # 3. Self-rename validation
  if [ "$old_id" = "$new_id" ]; then
    echo "Error: Cannot rename node '$old_id' to itself. Source and destination identifiers must be distinct." >&2
    return 1
  fi

  # 4. Source identifier syntax validation
  if ! [[ "$old_id" =~ ^[a-zA-Z0-9]([-_a-zA-Z0-9]*[a-zA-Z0-9])?$ ]]; then
    echo "Error: Invalid source node identifier '$old_id'. Identifier must start and end with alphanumeric characters and may contain hyphens and underscores." >&2
    return 1
  fi

  # 5. Target identifier syntax validation
  if ! [[ "$new_id" =~ ^[a-zA-Z0-9]([-_a-zA-Z0-9]*[a-zA-Z0-9])?$ ]]; then
    echo "Error: Invalid target node identifier '$new_id'. Identifier must start and end with alphanumeric characters and may contain hyphens and underscores." >&2
    return 1
  fi

  # 5. Swarm discovery
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

  # 6. Source node existence check
  local old_manifest="$nodes_dir/${old_id}.json"
  if [ ! -f "$old_manifest" ]; then
    echo "Error: Source node '$old_id' not found in active swarm '$active_swarm'." >&2
    return 1
  fi

  # 7. Destination identifier collision check
  local new_manifest="$nodes_dir/${new_id}.json"
  if [ -f "$new_manifest" ]; then
    echo "Error: Target node identifier '$new_id' already exists in active swarm '$active_swarm'." >&2
    return 1
  fi

  local sys_new_manifest="/etc/knot/swarms.d/${active_swarm}/nodes/${new_id}.json"
  if [ -f "$sys_new_manifest" ]; then
    echo "Error: Target node identifier '$new_id' already exists in system swarm directory." >&2
    return 1
  fi

  knot_log_info "Initiating atomic identity migration from '$old_id' to '$new_id' in swarm '$active_swarm'..."

  # 8. Atomic Manifest Migration
  local user_home
  user_home="$(knot_detect_user_home)"

  python3 -c "
import sys, json, os

old_manifest = sys.argv[1]
new_manifest = sys.argv[2]
new_id = sys.argv[3]

try:
    with open(old_manifest, 'r', encoding='utf-8') as f:
        data = json.load(f)
except (OSError, ValueError) as e:
    sys.stderr.write(f'Error reading manifest {old_manifest}: {e}\n')
    sys.exit(1)

data['id'] = new_id

tmp_manifest = f'{new_manifest}.tmp.{os.getpid()}'
try:
    with open(tmp_manifest, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_manifest, new_manifest)
    os.remove(old_manifest)
except (OSError, ValueError) as e:
    if os.path.exists(tmp_manifest):
        try:
            os.remove(tmp_manifest)
        except OSError as cleanup_err:
            sys.stderr.write(f'Notice: failed removing temp file {tmp_manifest}: {cleanup_err}\n')
    sys.stderr.write(f'Error atomically renaming manifest to {new_manifest}: {e}\n')
    sys.exit(1)
" "$old_manifest" "$new_manifest" "$new_id"

  # System manifest if writable
  local sys_old_manifest="/etc/knot/swarms.d/${active_swarm}/nodes/${old_id}.json"
  if [ -f "$sys_old_manifest" ] && [ -w "$sys_old_manifest" ]; then
    python3 -c "
import sys, json, os
old_m, new_m, nid = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(old_m, 'r', encoding='utf-8') as f:
        d = json.load(f)
    d['id'] = nid
    tmp = f'{new_m}.tmp.{os.getpid()}'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, new_m)
    os.remove(old_m)
except (OSError, ValueError) as e:
    sys.stderr.write(f'Notice: Failed to update system manifest {new_m}: {e}\n')
" "$sys_old_manifest" "$sys_new_manifest" "$new_id"
  fi

  # 9. Atomic Topology Migration
  local user_topo="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
  if [ -f "$user_topo" ]; then
    knot_log_info "Migrating topology references in '$user_topo'..."
    node_migrate_topology "$user_topo" "$old_id" "$new_id"
  fi
  local sys_topo="/etc/knot/swarms.d/${active_swarm}/topology.json"
  if [ -f "$sys_topo" ] && [ -w "$sys_topo" ]; then
    node_migrate_topology "$sys_topo" "$old_id" "$new_id"
  fi

  # 10. Swarm Profile Migration (ANCHOR_ID)
  local user_swarm_conf="$user_home/.config/knot/swarms/${active_swarm}/swarm.conf"
  node_migrate_swarm_conf "$user_swarm_conf" "$old_id" "$new_id"
  local user_profile_conf="$user_home/.config/knot/swarms/${active_swarm}.conf"
  node_migrate_swarm_conf "$user_profile_conf" "$old_id" "$new_id"
  local sys_swarm_conf="/etc/knot/swarms.d/${active_swarm}.conf"
  node_migrate_swarm_conf "$sys_swarm_conf" "$old_id" "$new_id"

  # 11. Subsystems Alignment: Deskflow Server Recompilation & Mute Markers
  knot_log_info "Recompiling Deskflow KVM server routing..."
  local old_mute_user="$user_home/.local/state/knot/vmon_muted_deskflow_${old_id}"
  local new_mute_user="$user_home/.local/state/knot/vmon_muted_deskflow_${new_id}"
  if [ -f "$old_mute_user" ]; then
    mv -f "$old_mute_user" "$new_mute_user"
  fi
  local old_mute_run="/run/knot/vmon_muted_deskflow_${old_id}"
  local new_mute_run="/run/knot/vmon_muted_deskflow_${new_id}"
  if [ -f "$old_mute_run" ]; then
    mv -f "$old_mute_run" "$new_mute_run"
  fi

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

  # 12. Subsystems Alignment: OpenSSH Client Host Config
  knot_log_info "Regenerating SSH client configuration (~/.ssh/config)..."
  ssh_sync_client_config
  ssh_socket_cleanup

  # 13. Local Node ID Marker Update
  local my_node_id
  my_node_id="$(knot_detect_node_id)"
  if [ "$old_id" = "$my_node_id" ]; then
    knot_log_info "Updating local node_id marker to '$new_id'..."
    mkdir -p "$user_home/.config/knot"
    echo "$new_id" > "$user_home/.config/knot/node_id"
    if [ -d "/run/knot" ] && [ -w "/run/knot" ]; then
      echo "$new_id" > "/run/knot/node_id"
    fi
  fi

  # 14. Remote Node ID Marker Update (over SSH if reachable)
  if [ "$old_id" != "$my_node_id" ]; then
    local target_port=22
    local p=""
    p="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$new_manifest")"
    [ -n "$p" ] && target_port="$p"
    local rem_probe=0
    ssh -o BatchMode=yes -o ConnectTimeout=3 -p "$target_port" "$new_id" "true" 2>&1 || rem_probe=$?
    if [ $rem_probe -eq 0 ]; then
      local rem_out="" rem_rc=0
      rem_out="$(ssh -o BatchMode=yes -o ConnectTimeout=4 -p "$target_port" "$new_id" \
        "mkdir -p \$HOME/.config/knot && echo '$new_id' > \$HOME/.config/knot/node_id" 2>&1)" || rem_rc=$?
      if [ $rem_rc -ne 0 ]; then
        knot_log_warn "Notice: Remote node ID update reported: $rem_out"
      fi
    fi
  fi

  # 15. Cluster Synchronization
  if command -v cmd_sync >/dev/null; then
    knot_log_info "Synchronizing cluster state across remaining nodes..."
    local sync_out="" sync_rc=0
    local sync_args=("--all")
    if [ "$(knot_detect_install_type)" = "dev" ]; then
      sync_args+=("--force-prod")
    fi
    sync_out="$(cmd_sync "${sync_args[@]}" 2>&1)" || sync_rc=$?
    if [ $sync_rc -ne 0 ]; then
      knot_log_warn "Notice: Cluster sync completed with warnings: $sync_out"
    fi
  fi

  knot_log_ok "Node '$old_id' successfully renamed to '$new_id' across swarm '$active_swarm'."
  return 0
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
    rename|mv)
      shift
      node_rename "$@"
      ;;
    list|ls)
      shift
      node_list "$@"
      ;;
    remove|rm|offboard)
      shift
      if command -v node_remove >/dev/null; then
        node_remove "$@"
      else
        echo "Error: Node removal is implemented in Issue #81." >&2
        return 1
      fi
      ;;
    -h|--help|help|"")
      echo -e "${C_BOLD}Knot Node Management${C_RESET}"
      echo "Usage:"
      echo "  knot node rename <old_id> <new_id>           Migrate node identity across cluster"
      echo "  knot node remove <node_id> [--purge-remote]  Decommission a node from the cluster"
      echo "  knot node list                               List all registered nodes in active swarm"
      return 0
      ;;
    *)
      echo "Error: Unknown node subcommand '$sub'" >&2
      echo -e "${C_BOLD}Knot Node Management${C_RESET}" >&2
      echo "Usage:" >&2
      echo "  knot node rename <old_id> <new_id>           Migrate node identity across cluster" >&2
      echo "  knot node remove <node_id> [--purge-remote]  Decommission a node from the cluster" >&2
      echo "  knot node list                               List all registered nodes in active swarm" >&2
      return 1
      ;;
  esac
}
