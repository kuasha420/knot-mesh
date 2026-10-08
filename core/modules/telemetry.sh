#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Deterministic Telemetry & Machine-Readable Cluster Health Ledger
# Authoritative implementation for Issue #67

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/hub.sh"

telemetry_get_local_power() {
  python3 -c '
import os, glob, json

ac_online = True
has_ac_record = False

for p in glob.glob("/sys/class/power_supply/*"):
    t_file = os.path.join(p, "type")
    if os.path.isfile(t_file):
        try:
            with open(t_file) as f:
                t = f.read().strip()
            if t in ("Mains", "USB"):
                on_file = os.path.join(p, "online")
                if os.path.isfile(on_file):
                    has_ac_record = True
                    with open(on_file) as f:
                        ac_online = (f.read().strip() == "1")
        except Exception:
            pass

bat_pct = None
bat_status = "AC"

for p in glob.glob("/sys/class/power_supply/BAT*"):
    cap_file = os.path.join(p, "capacity")
    st_file = os.path.join(p, "status")
    if os.path.isfile(cap_file):
        try:
            with open(cap_file) as f:
                bat_pct = int(f.read().strip())
            with open(st_file) as f:
                bat_status = f.read().strip()
        except Exception:
            pass

if bat_pct is None:
    bat_status = "Full" if ac_online else "Discharging"

print(json.dumps({
    "ac_online": ac_online,
    "battery_pct": bat_pct,
    "status": bat_status
}))
'
}

telemetry_ledger_generate() {
  local target_swarm=""
  local json_mode=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --swarm)
        target_swarm="${2:-}"
        shift 2
        ;;
      --json)
        json_mode=1
        shift
        ;;
      generate)
        shift
        ;;
      -h|--help)
        echo "Usage: knot ledger generate [--json] [--swarm <swarm_id>]"
        return 0
        ;;
      *)
        shift
        ;;
    esac
  done

  local active_swarm
  if [ -n "$target_swarm" ]; then
    active_swarm="$target_swarm"
  else
    active_swarm="$(knot_get_active_swarm)"
  fi
  if [ -z "$active_swarm" ] || [ "$active_swarm" = "none" ]; then
    active_swarm="standalone"
  fi

  local user_home
  user_home="$(knot_detect_user_home)"
  local nodes_dir=""
  if [ -n "$active_swarm" ] && [ -d "$user_home/.config/knot/swarms/${active_swarm}/nodes" ]; then
    nodes_dir="$user_home/.config/knot/swarms/${active_swarm}/nodes"
  elif [ -n "$active_swarm" ] && [ -d "/etc/knot/swarms.d/${active_swarm}/nodes" ]; then
    nodes_dir="/etc/knot/swarms.d/${active_swarm}/nodes"
  elif ! nodes_dir="$(knot_get_nodes_dir 2>&1)"; then
    nodes_dir=""
  fi

  local my_host my_node_id
  my_host="$(knot_detect_hostname)"
  my_node_id="$(knot_detect_node_id)"

  local anchor_id="desktop"
  local anchor_host="desktop"
  if knot_load_swarm_profile "$active_swarm"; then
    anchor_id="${ANCHOR_ID:-desktop}"
    anchor_host="${ANCHOR_HOST:-desktop}"
  elif [ -n "$nodes_dir" ] && [ -d "$nodes_dir" ]; then
    for manifest in "$nodes_dir/"*.json; do
      [ -e "$manifest" ] || continue
      if grep -q '"role":[[:space:]]*"anchor"' "$manifest"; then
        anchor_id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        anchor_host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        break
      fi
    done
  fi

  # KVM Deskflow connection states
  local established_kvm_ips=""
  if knot_is_anchor || [ "$my_node_id" = "$anchor_id" ] || [ "$my_host" = "$anchor_host" ]; then
    local ss_out=""
    if ss_out="$(ss -H -tn state established sport = :24800 2>&1)"; then
      established_kvm_ips="$(echo "$ss_out" | awk '{print $4}' | cut -d: -f1)"
    fi
  else
    local ssh_ss_out=""
    if ssh_ss_out="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$anchor_id" "ss -H -tn state established sport = :24800" 2>&1)"; then
      established_kvm_ips="$(echo "$ssh_ss_out" | awk '{print $4}' | cut -d: -f1)"
    fi
  fi

  # Model Quotas from central Knot Hub
  local hub_url=""
  if [ -n "${KNOT_HUB_URL:-}" ]; then
    hub_url="$KNOT_HUB_URL"
  else
    local raw_hub=""
    if raw_hub="$(hub_resolve_url 2>&1)"; then
      hub_url="$(echo "$raw_hub" | grep -E '^https?://' | tail -n1)"
    fi
  fi

  local hub_nodes_json="{}"
  if [ -n "$hub_url" ]; then
    local curl_out=""
    if curl_out="$(python3 -c '
import urllib.request, ssl, sys, json
try:
    ctx = ssl._create_unverified_context()
    req = urllib.request.Request("'"$hub_url"'/nodes", headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=2.0, context=ctx) as r:
        raw = json.loads(r.read().decode("utf-8"))
        res = {n.get("id"): n for n in raw if isinstance(n, dict) and "id" in n}
        print(json.dumps(res))
except Exception:
    print("{}")
' 2>&1)"; then
      hub_nodes_json="$curl_out"
    fi
  fi

  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  # Collect node data
  local node_records=()

  if [ -n "$nodes_dir" ] && [ -d "$nodes_dir" ]; then
    for manifest in "$nodes_dir/"*.json; do
      [ -e "$manifest" ] || continue
      local id user host port
      id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      user="$(awk -F'"' '/"user":/ {print $4}' "$manifest")"
      host="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      port="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest")"
      if [ -z "$port" ]; then port="22"; fi

      local is_local=0
      if [ "$id" = "$my_node_id" ] || [ "$host" = "$my_host" ] || [ "$id" = "local" ] || [ "$id" = "localhost" ] || [ "$host" = "127.0.0.1" ]; then
        is_local=1
      fi

      local resolved_ip=""
      if [ "$is_local" -eq 1 ]; then
        resolved_ip="127.0.0.1"
      elif ! resolved_ip="$("$KNOT_ROOT/core/resolver.sh" "$id" "$port" 2>&1)"; then
        resolved_ip=""
      fi

      local node_reachable=0
      local ping_ms=0.0
      if [ -n "$resolved_ip" ]; then
        if [ "$is_local" -eq 1 ]; then
          node_reachable=1
          ping_ms=0.1
          local ping_out=""
          if ping_out="$(ping -c 1 -W 1 "$resolved_ip" 2>&1)"; then
            local rtt
            rtt="$(echo "$ping_out" | awk -F'/' '/(rtt|round-trip)/ {print $5}')"
            if [ -n "$rtt" ]; then
              ping_ms="$(python3 -c "import sys; print(float('$rtt'))" 2>&1 || echo "$ping_ms")"
            fi
          fi
        else
          local ping_out=""
          if ping_out="$(ping -c 1 -W 1 "$resolved_ip" 2>&1)"; then
            local rtt
            rtt="$(echo "$ping_out" | awk -F'/' '/(rtt|round-trip)/ {print $5}')"
            if [ -n "$rtt" ]; then
              ping_ms="$(python3 -c "import sys; print(float('$rtt'))" 2>&1 || echo 0.5)"
              node_reachable=1
            fi
          fi
          if [ "$node_reachable" -eq 0 ]; then
            # Secondary TCP check in case ICMP ping is blocked by network firewall
            local tcp_probe=""
            if tcp_probe="$(timeout 1 bash -c "echo > /dev/tcp/$resolved_ip/$port" 2>&1)"; then
              node_reachable=1
              ping_ms=1.0
            fi
          fi
        fi
      fi

      if [ "$node_reachable" -eq 1 ]; then
        # Power status
        local power_json='{"ac_online": true, "battery_pct": null, "status": "Full"}'
        if [ "$is_local" -eq 1 ]; then
          power_json="$(telemetry_get_local_power)"
        else
          # Remote query with 2s timeout
          local r_p_out=""
          local p_script='python3 -c '\''import glob, os, json; ac = any(open(f).read().strip()=="1" for f in glob.glob("/sys/class/power_supply/*/online")); bats = glob.glob("/sys/class/power_supply/BAT*"); bp = int(open(os.path.join(bats[0], "capacity")).read().strip()) if bats else None; bs = open(os.path.join(bats[0], "status")).read().strip() if bats else ("Full" if ac else "AC"); print(json.dumps({"ac_online": ac, "battery_pct": bp, "status": bs}))'\'
          if r_p_out="$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$id" "$p_script" 2>&1)"; then
            if echo "$r_p_out" | grep -q 'ac_online'; then
              power_json="$r_p_out"
            fi
          fi
        fi

        # KVM status
        local kvm_status="DISCONNECTED"
        if [ "$id" = "$anchor_id" ] || [ "$host" = "$anchor_host" ]; then
          local count=0
          if [ -n "$established_kvm_ips" ]; then
            count="$(echo "$established_kvm_ips" | grep -v '^$' | wc -l)"
          fi
          kvm_status="SERVER"
        elif [ -n "$established_kvm_ips" ] && echo "$established_kvm_ips" | grep -q "$resolved_ip"; then
          kvm_status="CONNECTED"
        fi

        # Quotas
        local n_record
        n_record=$(python3 -c '
import sys, json

nid = sys.argv[1]
ping_val = float(sys.argv[2])
power_d = json.loads(sys.argv[3])
kvm_stat = sys.argv[4]
hub_nodes = json.loads(sys.argv[5])

h_node = hub_nodes.get(nid, {})
g_5h = h_node.get("quota_5h_gemini", 1.0)
g_wk = h_node.get("quota_weekly_gemini", 1.0)
c_5h = h_node.get("quota_5h_3p", 1.0)
c_wk = h_node.get("quota_weekly_3p", 1.0)

print(json.dumps({
    "id": nid,
    "data": {
        "status": "ONLINE",
        "ping_ms": ping_val,
        "power": power_d,
        "quota": {
            "gemini_5h": g_5h,
            "gemini_weekly": g_wk,
            "claude_gpt_5h": c_5h,
            "claude_gpt_weekly": c_wk
        },
        "kvm": {
            "status": kvm_stat
        }
    }
}))
' "$id" "$ping_ms" "$power_json" "$kvm_status" "$hub_nodes_json")
        node_records+=("$n_record")
      else
        local offline_record
        offline_record=$(python3 -c '
import sys, json
print(json.dumps({
    "id": sys.argv[1],
    "data": {
        "status": "OFFLINE",
        "error": sys.argv[2]
    }
}))
' "$id" "Node unreachable at ${resolved_ip:-(unresolved IP)} (ping/TCP probe failed)")
        node_records+=("$offline_record")
      fi
    done
  fi

  # Output full deterministic ledger JSON
  python3 -c '
import sys, json

ts = sys.argv[1]
swarm = sys.argv[2]
raw_records = sys.argv[3:]

nodes_map = {}
for r in raw_records:
    if r.strip():
        parsed = json.loads(r)
        nodes_map[parsed["id"]] = parsed["data"]

out = {
    "timestamp": ts,
    "swarm": swarm,
    "nodes": nodes_map
}
print(json.dumps(out, indent=2))
' "$timestamp" "$active_swarm" "${node_records[@]}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    generate|ledger)
      shift
      telemetry_ledger_generate "$@"
      ;;
    power)
      telemetry_get_local_power
      ;;
    *)
      echo "Usage: telemetry.sh <generate|power> [args...]"
      exit 1
      ;;
  esac
fi
