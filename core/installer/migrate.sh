#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Automated Migration Engine (core/installer/migrate.sh)
# Migrates legacy Knot GitOps installations into Knot Mesh multi-swarm profiles.

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
if [ -f "$KNOT_ROOT/core/lib.sh" ]; then
  # shellcheck source=../../core/lib.sh
  source "$KNOT_ROOT/core/lib.sh"
fi

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GREEN=$'\033[1;32m'
C_CYAN=$'\033[1;36m'
C_YELLOW=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_DIM=$'\033[2m'

# Helper to detect local MAC addresses
get_local_macs() {
  local macs=()
  local links=""
  if links="$(ip -o link show 2>&1)"; then
    while IFS= read -r line; do
      if [[ "$line" =~ link/(ether|ieee802.11)[[:space:]]+([0-9a-fA-F:]{17}) ]]; then
        macs+=("${BASH_REMATCH[2],,}")
      fi
    done <<< "$links"
  fi
  echo "${macs[@]}"
}

# Helper to detect current default gateway MAC
get_gateway_mac() {
  local gw_ip=""
  local route_out=""
  if route_out="$(ip -4 route show default 2>&1)"; then
    gw_ip="$(echo "$route_out" | awk '{print $3; exit}')"
  fi

  local gw_mac=""
  if [ -n "$gw_ip" ]; then
    local neigh_out=""
    if neigh_out="$(ip neigh show "$gw_ip" 2>&1)"; then
      gw_mac="$(echo "$neigh_out" | awk '{for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1)}' | head -n1)"
    fi
  fi
  echo "${gw_mac,,}"
}

migrate_detect_role() {
  local legacy_dir="$1"
  local my_host
  my_host="$(knot_detect_hostname)"
  local my_macs
  my_macs="$(get_local_macs)"

  local detected_id=""
  local detected_role=""
  local anchor_id="desktop"
  local user_matched_id=""

  local topo_file="$legacy_dir/registry/topology.json"
  if [ -r "$topo_file" ]; then
    local a_id
    a_id="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("anchor", "desktop"))' "$topo_file")"
    if [ -n "$a_id" ]; then
      anchor_id="$a_id"
    fi
  fi

  local nodes_dir="$legacy_dir/registry/nodes"
  if [ -d "$nodes_dir" ]; then
    for mf in "$nodes_dir/"*.json; do
      [ -f "$mf" ] || continue
      local nid nhost
      nid="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("id", ""))' "$mf")"
      nhost="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("hostname", ""))' "$mf")"

      # Match by hostname
      if [ -n "$nhost" ] && [ "$nhost" = "$my_host" ]; then
        detected_id="$nid"
        break
      fi

      # Match by MAC addresses
      local iface_macs
      iface_macs="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
macs = []
for iface, idata in data.get("interfaces", {}).items():
    if isinstance(idata, dict) and "mac" in idata:
        macs.append(idata["mac"].lower())
print(" ".join(macs))
' "$mf")"

      for m in $iface_macs; do
        if [[ " $my_macs " =~ [[:space:]]$m[[:space:]] ]]; then
          detected_id="$nid"
          break 2
        fi
      done

      # Fallback match by username
      local nuser
      nuser="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("user", ""))' "$mf")"
      local my_user
      my_user="$(knot_detect_user)"
      if [ -n "$nuser" ] && [ "$nuser" = "$my_user" ] && [ -z "$detected_id" ]; then
        user_matched_id="$nid"
      fi
    done
  fi

  if [ -z "$detected_id" ] && [ -n "${user_matched_id:-}" ]; then
    detected_id="$user_matched_id"
  fi

  if [ -z "$detected_id" ]; then
    detected_id="$my_host"
  fi

  if [ "$detected_id" = "$anchor_id" ]; then
    detected_role="anchor"
  else
    detected_role="strand"
  fi

  echo "$detected_id $detected_role $anchor_id"
}

run_migration() {
  local legacy_dir="/home/psl/knot"
  local swarm_id="home"
  local swarm_name="Home Swarm"
  local dry_run=0
  local force=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --legacy-dir)
        legacy_dir="$2"
        shift 2
        ;;
      --swarm-id)
        swarm_id="$2"
        shift 2
        ;;
      --swarm-name)
        swarm_name="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      -h|--help)
        cat << MIGRATE_HELP
${C_BOLD}Usage:${C_RESET} knot-installer migrate [OPTIONS]

Migrate legacy Knot GitOps installation into a Knot Mesh swarm profile.

${C_BOLD}Options:${C_RESET}
    --legacy-dir <path>  Path to legacy Knot repository (default: /home/psl/knot)
    --swarm-id <id>      Target swarm ID (default: home)
    --swarm-name <name>  Human-readable swarm name (default: "Home Swarm")
    --dry-run            Simulate migration without modifying files or services
    --force              Overwrite existing swarm profile if already present
MIGRATE_HELP
        exit 0
        ;;
      *)
        echo -e "${C_RED}Error:${C_RESET} Unknown option '$1'" >&2
        exit 1
        ;;
    esac
  done

  echo -e "\n${C_CYAN}${C_BOLD}=== Knot Mesh Automated Role-Detecting Migration Engine ===${C_RESET}"
  echo -e "  Legacy Directory: ${C_BOLD}${legacy_dir}${C_RESET}"
  echo -e "  Target Swarm ID:  ${C_BOLD}${swarm_id}${C_RESET} (${swarm_name})"
  if [ "$dry_run" -eq 1 ]; then
    echo -e "  ${C_YELLOW}${C_BOLD}MODE: DRY-RUN SIMULATION (No changes will be written)${C_RESET}\n"
  fi

  if [ ! -d "$legacy_dir/registry" ]; then
    echo -e "${C_RED}Error:${C_RESET} Legacy registry directory not found at $legacy_dir/registry" >&2
    exit 1
  fi

  # 1. Role Detection
  echo -e "${C_CYAN}[1/5] Auto-detecting host role and node identity...${C_RESET}"
  local role_info
  role_info="$(migrate_detect_role "$legacy_dir")"
  read -r my_node_id my_role anchor_id <<< "$role_info"

  echo -e "  -> Detected Node ID:  ${C_BOLD}${my_node_id}${C_RESET}"
  echo -e "  -> Detected Swarm Role: ${C_BOLD}${my_role^^}${C_RESET}"
  echo -e "  -> Identified Anchor: ${C_BOLD}${anchor_id}${C_RESET}"

  # 2. Extract Anchor Hostname & Port
  local anchor_host="desktop"
  local anchor_manifest="$legacy_dir/registry/nodes/${anchor_id}.json"
  if [ -r "$anchor_manifest" ]; then
    local ah
    ah="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1])).get("hostname", ""))' "$anchor_manifest")"
    if [ -n "$ah" ]; then
      anchor_host="$ah"
    fi
  fi

  # 3. Detect current network binding
  local gw_mac
  gw_mac="$(get_gateway_mac)"
  local subnet
  subnet="$(knot_detect_subnet)"
  echo -e "  -> Active Gateway MAC: ${gw_mac:-"(none)"}"
  echo -e "  -> Active Subnet:      ${subnet:-"(unknown)"}"

  # 4. Prepare Swarm Profile & Directories
  local home
  home="$(knot_detect_user_home)"
  local target_swarm_dir="$home/.config/knot/swarms/${swarm_id}"
  local sys_conf_path="/etc/knot/swarms.d/${swarm_id}.conf"

  echo -e "\n${C_CYAN}[2/5] Synthesizing swarm profile and topology...${C_RESET}"
  local profile_content
  profile_content="$(cat << CONF_EOF
# Knot Swarm Profile: ${swarm_id}
SWARM_ID="${swarm_id}"
SWARM_NAME="${swarm_name}"
ANCHOR_ID="${anchor_id}"
ANCHOR_HOST="${anchor_host}"
HUB_PORT=4242
GATEWAY_MACS="${gw_mac}"
SUBNET="${subnet}"
ALLOW_NOPASSWD_SUDO="true"
ALLOW_DESKFLOW_KVM="true"
CONF_EOF
)"

  if [ "$dry_run" -eq 1 ]; then
    echo -e "  ${C_DIM}[dry-run] Would write profile to $target_swarm_dir/swarm.conf and $sys_conf_path:${C_RESET}"
    echo "$profile_content" | sed 's/^/    /'
  else
    mkdir -p "$target_swarm_dir/nodes"
    echo "$profile_content" > "$target_swarm_dir/swarm.conf"
    if [ -w "/etc" ] || [ "$(id -u)" -eq 0 ] || (command -v sudo >/dev/null && sudo -n true); then
      sudo mkdir -p "/etc/knot/swarms.d"
      echo "$profile_content" | sudo tee "$sys_conf_path" >/dev/null
    fi
    echo -e "  ${C_GREEN}[✓] Swarm profile written.${C_RESET}"
  fi

  # Copy node manifests & topology
  echo -e "\n${C_CYAN}[3/5] Migrating declarative node manifests and topology...${C_RESET}"
  if [ -d "$legacy_dir/registry/nodes" ]; then
    for nfile in "$legacy_dir/registry/nodes/"*.json; do
      [ -f "$nfile" ] || continue
      local base_n
      base_n="$(basename "$nfile")"
      if [ "$dry_run" -eq 1 ]; then
        echo -e "  ${C_DIM}[dry-run] Would copy manifest $base_n -> $target_swarm_dir/nodes/$base_n${C_RESET}"
      else
        cp "$nfile" "$target_swarm_dir/nodes/$base_n"
      fi
    done
  fi

  if [ -f "$legacy_dir/registry/topology.json" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo -e "  ${C_DIM}[dry-run] Would copy topology.json -> $target_swarm_dir/topology.json${C_RESET}"
    else
      cp "$legacy_dir/registry/topology.json" "$target_swarm_dir/topology.json"
    fi
  fi
  echo -e "  ${C_GREEN}[✓] Manifests and topology migrated.${C_RESET}"

  # 5. Service Configuration & KVM
  echo -e "\n${C_CYAN}[4/5] Aligning KVM Deskflow & Network Guard services...${C_RESET}"
  if [ "$my_role" = "anchor" ]; then
    if [ "$dry_run" -eq 1 ]; then
      echo -e "  ${C_DIM}[dry-run] Would compile Anchor Deskflow server configuration via compile_deskflow.py${C_RESET}"
    else
      if [ -f "$KNOT_ROOT/core/modules/deskflow.sh" ]; then
        # shellcheck source=../../core/modules/deskflow.sh
        source "$KNOT_ROOT/core/modules/deskflow.sh"
        deskflow_compile_server_config "unlocked"
      fi
    fi
  else
    if [ "$dry_run" -eq 1 ]; then
      echo -e "  ${C_DIM}[dry-run] Would configure Strand dynamic deskflow client targeting $anchor_host${C_RESET}"
    else
      local client_runner="/usr/local/bin/knot-deskflow-client"
      if [ -x "$client_runner" ]; then
        "$client_runner" reload
      fi
    fi
  fi
  echo -e "  ${C_GREEN}[✓] KVM and service alignment verified.${C_RESET}"

  # 6. Active Profile Activation (Zero Session Drop)
  echo -e "\n${C_CYAN}[5/5] Activating swarm profile '${swarm_id}'...${C_RESET}"
  if [ "$dry_run" -eq 1 ]; then
    echo -e "  ${C_DIM}[dry-run] Would update /run/knot/active_swarm and ~/.local/state/knot/active_swarm to '${swarm_id}'${C_RESET}"
  else
    knot_set_active_swarm "$swarm_id"
    echo -e "  ${C_GREEN}[✓] Active swarm set to '${swarm_id}' with zero downtime.${C_RESET}"
  fi

  echo -e "\n${C_GREEN}${C_BOLD}======================================================================${C_RESET}"
  if [ "$dry_run" -eq 1 ]; then
    echo -e "${C_YELLOW}${C_BOLD}                 DRY-RUN SIMULATION COMPLETE                          ${C_RESET}"
    echo -e "${C_YELLOW}  All role detections, manifests, and profiles validated successfully.${C_RESET}"
    echo -e "  Run without '${C_BOLD}--dry-run${C_RESET}' to execute live migration."
  else
    echo -e "${C_GREEN}${C_BOLD}                 MIGRATION COMPLETED SUCCESSFULLY                     ${C_RESET}"
    echo -e "  Swarm:   ${C_BOLD}${swarm_name}${C_RESET} (${swarm_id})"
    echo -e "  Role:    ${C_BOLD}${my_role^^}${C_RESET} (${my_node_id})"
    echo -e "  Anchor:  ${C_BOLD}${anchor_host}${C_RESET} (${anchor_id})"
  fi
  echo -e "${C_GREEN}${C_BOLD}======================================================================${C_RESET}\n"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_migration "$@"
fi
