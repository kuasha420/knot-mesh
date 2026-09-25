#!/usr/bin/env bash
set -euo pipefail

# Knot 3-Tier Dynamic Peer Resolver
# Usage:
#   resolver.sh <node_id> [port] [--proxy]

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

NODE="${1:-}"
PORT_ARG="${2:-}"
MODE="print"
EXPLICIT_SWARM=""
if [ $# -ge 1 ]; then
  shift
fi
if [ $# -ge 1 ]; then
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --proxy)
      MODE="proxy"
      shift
      ;;
    --swarm)
      EXPLICIT_SWARM="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$NODE" ] || [ "$NODE" = "-h" ] || [ "$NODE" = "--help" ]; then
  echo "Usage: knot resolve <node_id[.swarm_id]> [port] [--proxy] [--swarm <id>]"
  echo "Resolves mesh node addresses across 3 tiers (lease cache, mDNS, manifest IP hint, MAC ARP scan)."
  if [ -z "$NODE" ]; then
    exit 1
  else
    exit 0
  fi
fi

TARGET_NODE="$NODE"
TARGET_SWARM="$EXPLICIT_SWARM"
if [ -z "$TARGET_SWARM" ] && [[ "$NODE" =~ ^([^.]+)\.([^.]+)$ ]]; then
  TARGET_NODE="${BASH_REMATCH[1]}"
  TARGET_SWARM="${BASH_REMATCH[2]}"
fi
if [ -z "$TARGET_SWARM" ]; then
  TARGET_SWARM="$(knot_get_active_swarm)"
fi

USER_HOME="$(knot_detect_user_home)"
CACHE_DIR="$USER_HOME/.cache/knot"
mkdir -p "$CACHE_DIR/leases"
LEASE_FILE="$CACHE_DIR/leases/${TARGET_SWARM}_${TARGET_NODE}"

# Search directories for node manifest:
# 1. Swarm-specific profile directory (~/.config/knot/swarms/<swarm_id>/nodes/ and /etc/knot/swarms.d/<swarm_id>/nodes/)
# 2. All other swarm profile directories
SEARCH_DIRS=()
if [ -n "$TARGET_SWARM" ]; then
  if [ -d "$USER_HOME/.config/knot/swarms/${TARGET_SWARM}/nodes" ]; then
    SEARCH_DIRS+=("$USER_HOME/.config/knot/swarms/${TARGET_SWARM}/nodes")
  fi
  if [ -d "/etc/knot/swarms.d/${TARGET_SWARM}/nodes" ]; then
    SEARCH_DIRS+=("/etc/knot/swarms.d/${TARGET_SWARM}/nodes")
  fi
fi
for d in "$USER_HOME/.config/knot/swarms"/*/nodes /etc/knot/swarms.d/*/nodes; do
  [ -d "$d" ] || continue
  if [[ ! " ${SEARCH_DIRS[*]} " =~ " ${d} " ]]; then
    SEARCH_DIRS+=("$d")
  fi
done

MANIFEST=""
for sdir in "${SEARCH_DIRS[@]}"; do
  if [ -f "$sdir/${TARGET_NODE}.json" ]; then
    MANIFEST="$sdir/${TARGET_NODE}.json"
    break
  fi
  for f in "$sdir/"*.json; do
    [ -e "$f" ] || continue
    if grep -q "\"hostname\":[[:space:]]*\"${TARGET_NODE}\"" "$f" || \
       grep -q "\"id\":[[:space:]]*\"${TARGET_NODE}\"" "$f" || \
       grep -q "\"${TARGET_NODE}\"" "$f"; then
      MANIFEST="$f"
      break 2
    fi
  done
done

PORT="22"
if [ -n "$MANIFEST" ] && [ -r "$MANIFEST" ]; then
  MANIFEST_PORT="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$MANIFEST")"
  if [ -n "$MANIFEST_PORT" ]; then
    PORT="$MANIFEST_PORT"
  fi
fi
if [ -n "$PORT_ARG" ] && [[ "$PORT_ARG" =~ ^[0-9]+$ ]]; then
  PORT="$PORT_ARG"
fi

RESOLVED_IP=""

is_port_open() {
  local ip="$1"
  local port="$2"
  if command -v nc >/dev/null; then
    local nc_out=""
    if nc_out="$(nc -z -n -w 1 "$ip" "$port" </dev/null 2>&1)"; then
      return 0
    else
      return 1
    fi
  elif command -v socat >/dev/null; then
    local err=""
    if err="$(socat -u /dev/null "TCP:$ip:$port,connect-timeout=1" 2>&1)"; then
      return 0
    else
      return 1
    fi
  else
    local probe_err=""
    if probe_err="$(timeout 1 bash -c "echo > /dev/tcp/$ip/$port" </dev/null 2>&1)"; then
      return 0
    else
      return 1
    fi
  fi
}

is_host_alive() {
  local ip="$1"
  if [ -z "$ip" ]; then return 1; fi

  # 1. Primary check: requested port
  if is_port_open "$ip" "$PORT"; then
    return 0
  fi

  # 2. In proxy mode, we must strictly have $PORT open for SSH/TCP forwarding
  if [ "$MODE" = "proxy" ]; then
    return 1
  fi

  # 3. Address resolution fallback: probe mesh ports (24800 Deskflow, 4242 Hub)
  if is_port_open "$ip" 24800 || is_port_open "$ip" 4242; then
    return 0
  fi

  # 4. Address resolution fallback: ICMP ping
  local p_out=""
  if p_out="$(ping -c 1 -W 1 "$ip" 2>&1)"; then
    return 0
  fi

  return 1
}

# --- TIER 0: Local Host Check ---
MY_NODE_ID="$(knot_detect_node_id)"
MY_HOST="$(knot_detect_hostname)"
MY_HOST_SHORT="${MY_HOST%%.*}"
IS_LOCAL=0
if [ "$TARGET_NODE" = "$MY_NODE_ID" ] || [ "$TARGET_NODE" = "$MY_HOST" ] || [ "$TARGET_NODE" = "$MY_HOST_SHORT" ] || [ "$TARGET_NODE" = "localhost" ] || [ "$TARGET_NODE" = "127.0.0.1" ]; then
  IS_LOCAL=1
elif [ -n "$MANIFEST" ] && [ -r "$MANIFEST" ]; then
  M_HOST="$(awk -F'"' '/"hostname":/ {print $4}' "$MANIFEST")"
  M_ID="$(awk -F'"' '/"id":/ {print $4}' "$MANIFEST")"
  if [ "$M_ID" = "$MY_NODE_ID" ] || [ "$M_HOST" = "$MY_HOST" ] || [ "$M_HOST" = "$MY_HOST_SHORT" ] || [ "$M_ID" = "$MY_HOST" ] || [ "$M_ID" = "$MY_HOST_SHORT" ]; then
    IS_LOCAL=1
  fi
fi
if [ "$IS_LOCAL" -eq 1 ] && is_host_alive "127.0.0.1"; then
  RESOLVED_IP="127.0.0.1"
fi

HOSTNAME_VAL=""
MDNS_HOST=""
if [ -n "$MANIFEST" ] && [ -r "$MANIFEST" ]; then
  HOSTNAME_VAL="$(awk -F'"' '/"hostname":/ {print $4}' "$MANIFEST")"
  MDNS_HOST="$(awk -F'"' '/"mdns":/ {print $4}' "$MANIFEST")"
  if [ -z "$MDNS_HOST" ] && [ -n "$HOSTNAME_VAL" ]; then
    MDNS_HOST="${HOSTNAME_VAL}.local"
  fi
fi

# --- TIER 1: Dynamic mDNS / Zeroconf (Authoritative Dynamic Discovery) ---
if [ -z "$RESOLVED_IP" ] && [ -n "$MDNS_HOST" ]; then
  MDNS_IP=""
  if command -v timeout >/dev/null; then
    if command -v avahi-resolve >/dev/null; then
      a_out=""
      if a_out="$(timeout 1.5 avahi-resolve -n "$MDNS_HOST" 2>&1)"; then
        MDNS_IP="$(echo "$a_out" | awk '{print $2}' | head -n1)"
      fi
    fi
    if [ -z "$MDNS_IP" ]; then
      g_out=""
      if g_out="$(timeout 1.5 getent ahostsv4 "$MDNS_HOST" 2>&1)"; then
        MDNS_IP="$(echo "$g_out" | awk '{print $1}' | head -n1)"
      fi
    fi
  else
    if command -v avahi-resolve >/dev/null; then
      a_out=""
      if a_out="$(avahi-resolve -n "$MDNS_HOST" 2>&1)"; then
        MDNS_IP="$(echo "$a_out" | awk '{print $2}' | head -n1)"
      fi
    fi
    if [ -z "$MDNS_IP" ]; then
      g_out=""
      if g_out="$(getent ahostsv4 "$MDNS_HOST" 2>&1)"; then
        MDNS_IP="$(echo "$g_out" | awk '{print $1}' | head -n1)"
      fi
    fi
  fi

  if [ -n "$MDNS_IP" ] && is_host_alive "$MDNS_IP"; then
    RESOLVED_IP="$MDNS_IP"
    if [ -r "$LEASE_FILE" ]; then
      cached_check="$(tr -d '[:space:]' < "$LEASE_FILE")"
      if [ -n "$cached_check" ] && [ "$cached_check" != "$MDNS_IP" ]; then
        knot_log_info "Dynamic mDNS update: $TARGET_NODE shifted from cached $cached_check to $MDNS_IP." >&2
      fi
    fi
  fi
fi

# --- TIER 2: Lease Cache with Peer Identity Cross-Validation ---
if [ -z "$RESOLVED_IP" ] && [ -r "$LEASE_FILE" ]; then
  CACHED_IP="$(tr -d '[:space:]' < "$LEASE_FILE")"
  if [ -n "$CACHED_IP" ] && is_host_alive "$CACHED_IP"; then
    is_conflict=0
    rev_name=""
    if command -v timeout >/dev/null; then
      rev_out=""
      if rev_out="$(timeout 1 getent hosts "$CACHED_IP" 2>&1)"; then
        rev_name="$(echo "$rev_out" | awk '{print $2}' | head -n1)"
      fi
    else
      rev_out=""
      if rev_out="$(getent hosts "$CACHED_IP" 2>&1)"; then
        rev_name="$(echo "$rev_out" | awk '{print $2}' | head -n1)"
      fi
    fi

    if [ -n "$rev_name" ] && [ -n "$HOSTNAME_VAL" ]; then
      rev_short="${rev_name%%.*}"
      exp_short="${HOSTNAME_VAL%%.*}"
      if [ "$rev_short" != "$exp_short" ] && [ "$rev_name" != "$exp_short.local" ] && [ "$rev_name" != "$HOSTNAME_VAL" ]; then
        is_conflict=1
        knot_log_warn "Cached lease for $TARGET_NODE ($CACHED_IP) points to conflicting host '$rev_name'. Invalidating stale lease."
        rm -f "$LEASE_FILE"
      fi
    fi

    if [ "$is_conflict" -eq 0 ]; then
      RESOLVED_IP="$CACHED_IP"
    fi
  fi
fi

# --- TIER 3: IP Hint from Manifest (with Peer Identity Cross-Validation) ---
if [ -z "$RESOLVED_IP" ] && [ -n "$MANIFEST" ]; then
  IP_HINT="$(awk -F'"' '/"ip_hint":/ {print $4}' "$MANIFEST")"
  if [ -n "$IP_HINT" ] && is_host_alive "$IP_HINT"; then
    is_hint_conflict=0
    rev_hint_name=""
    if command -v timeout >/dev/null; then
      rev_hint_out=""
      if rev_hint_out="$(timeout 1 getent hosts "$IP_HINT" 2>&1)"; then
        rev_hint_name="$(echo "$rev_hint_out" | awk '{print $2}' | head -n1)"
      fi
    else
      rev_hint_out=""
      if rev_hint_out="$(getent hosts "$IP_HINT" 2>&1)"; then
        rev_hint_name="$(echo "$rev_hint_out" | awk '{print $2}' | head -n1)"
      fi
    fi

    if [ -n "$rev_hint_name" ] && [ -n "$HOSTNAME_VAL" ]; then
      rev_hint_short="${rev_hint_name%%.*}"
      exp_short="${HOSTNAME_VAL%%.*}"
      if [ "$rev_hint_short" != "$exp_short" ] && [ "$rev_hint_name" != "$exp_short.local" ] && [ "$rev_hint_name" != "$HOSTNAME_VAL" ]; then
        is_hint_conflict=1
        knot_log_warn "Manifest ip_hint for $TARGET_NODE ($IP_HINT) points to conflicting host '$rev_hint_name'. Skipping."
      fi
    fi

    if [ "$is_hint_conflict" -eq 0 ]; then
      RESOLVED_IP="$IP_HINT"
    fi
  fi
fi

# --- TIER 3: Hardware MAC Fingerprint Scan ---
if [ -z "$RESOLVED_IP" ] && [ -n "$MANIFEST" ]; then
  MACS="$(awk 'match($0, /([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/) {print substr($0, RSTART, RLENGTH)}' "$MANIFEST")"
  for mac in $MACS; do
    LOWER_MAC="$(echo "$mac" | tr '[:upper:]' '[:lower:]')"
    FOUND_IP="$(ip neigh | awk -v mac="$LOWER_MAC" 'tolower($0) ~ mac {print $1; exit}')"
    if [ -n "$FOUND_IP" ] && is_host_alive "$FOUND_IP"; then
      RESOLVED_IP="$FOUND_IP"
      break
    fi
  done

  if [ -z "$RESOLVED_IP" ]; then
    SUBNET="$(knot_detect_subnet)"
    if command -v nmap >/dev/null; then
      nmap -sn -n "$SUBNET" >/dev/null
    else
      PREFIX="${SUBNET%.*}"
      for i in {1..254}; do
        ping -c 1 -W 1 "${PREFIX}.${i}" >/dev/null &
      done
      for job in $(jobs -p); do
        if ! wait "$job"; then
          : # IP probe returned non-zero (unreachable/packet loss)
        fi
      done
    fi

    for mac in $MACS; do
      LOWER_MAC="$(echo "$mac" | tr '[:upper:]' '[:lower:]')"
      FOUND_IP="$(ip neigh | awk -v mac="$LOWER_MAC" 'tolower($0) ~ mac {print $1; exit}')"
      if [ -n "$FOUND_IP" ] && is_host_alive "$FOUND_IP"; then
        RESOLVED_IP="$FOUND_IP"
        break
      fi
    done
  fi
fi

if [ -z "$RESOLVED_IP" ]; then
  knot_log_err "Failed to resolve node '$NODE' on port $PORT across all tiers"
  exit 1
fi

lease_tmp="${LEASE_FILE}.${BASHPID:-$$}.tmp"
echo "$RESOLVED_IP" > "$lease_tmp"
if ! mv -f "$lease_tmp" "$LEASE_FILE"; then
  cat "$lease_tmp" > "$LEASE_FILE"
  rm -f "$lease_tmp"
fi

if [ "$MODE" = "proxy" ]; then
  if command -v nc >/dev/null; then
    exec nc "$RESOLVED_IP" "$PORT"
  elif command -v socat >/dev/null; then
    exec socat STDIO "TCP:$RESOLVED_IP:$PORT"
  else
    knot_log_err "Neither nc nor socat is installed for SSH proxy forwarding"
    exit 1
  fi
else
  echo "$RESOLVED_IP"
fi
