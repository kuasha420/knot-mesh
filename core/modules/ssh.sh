#!/usr/bin/env bash
set -euo pipefail

# Knot OpenSSH Configuration & Key Sync Module

KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

ssh_ensure_local_key() {
  local home
  home="$(knot_detect_user_home)"
  local user
  user="$(knot_detect_user)"
  local key_path="$home/.ssh/id_ed25519"

  if [ ! -f "$key_path" ]; then
    knot_log_info "Generating dedicated ed25519 keypair at $key_path..."
    mkdir -p "$home/.ssh"
    chmod 700 "$home/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$key_path" -C "$user@$(knot_detect_hostname)"
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"
    chown -R "$user:" "$home/.ssh"
    knot_log_ok "Keypair generated successfully."
  else
    knot_log_ok "Keypair already present at $key_path."
  fi
}

ssh_harden_server() {
  knot_log_info "Applying OpenSSH hardening drop-in..."
  sudo mkdir -p /etc/ssh/sshd_config.d

  cat << 'CONF_EOF' | sudo tee /etc/ssh/sshd_config.d/10-knot-keyonly.conf >/dev/null
# Knot Mesh Hardening Configuration
# Enforces passwordless publickey-only authentication
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
AuthenticationMethods publickey
PermitRootLogin no
CONF_EOF

  # Test syntax
  if sudo /usr/bin/sshd -t; then
    knot_log_ok "sshd_config syntax valid."
    sudo systemctl restart sshd
    knot_log_ok "sshd service restarted with hardening active."
  else
    knot_log_err "sshd_config syntax check failed! Reverting..."
    sudo rm -f /etc/ssh/sshd_config.d/10-knot-keyonly.conf
    return 1
  fi
}

ssh_sync_authorized_keys() {
  local home
  home="$(knot_detect_user_home)"
  local user
  user="$(knot_detect_user)"
  local auth_file="$home/.ssh/authorized_keys"

  knot_log_info "Reconciling authorized_keys with all registered mesh nodes across swarms..."
  mkdir -p "$home/.ssh"
  touch "$auth_file"

  local existing_keys=""
  if [ -f "$auth_file" ]; then
    existing_keys="$(sed '/# >>> KNOT MESH MANAGED.*>>>/,/# <<< KNOT MESH MANAGED.*<<</d' "$auth_file")"
  fi

  local knot_keys=""
  local search_dirs=()
  if [ -d "$home/.config/knot/swarms" ]; then
    for sdir in "$home/.config/knot/swarms/"*/nodes; do
      [ -d "$sdir" ] || continue
      search_dirs+=("$sdir")
    done
  fi
  if [ -d "/etc/knot/swarms.d" ]; then
    for sdir in /etc/knot/swarms.d/*/nodes; do
      [ -d "$sdir" ] || continue
      search_dirs+=("$sdir")
    done
  fi

  local seen_keys=()
  for sdir in "${search_dirs[@]}"; do
    for manifest in "$sdir/"*.json; do
      [ -e "$manifest" ] || continue
      local pubkey
      pubkey="$(awk -F'"' '/"pubkey":/ {print $4}' "$manifest")"
      if [ -n "$pubkey" ]; then
        if [[ ! " ${seen_keys[*]:-} " =~ " ${pubkey} " ]]; then
          seen_keys+=("$pubkey")
          knot_keys+="$pubkey"$'\n'
        fi
      fi
    done
  done

  {
    if [ -n "$existing_keys" ]; then
      echo "$existing_keys"
    fi
    echo "# >>> KNOT MESH MANAGED (DO NOT EDIT MANUALLY) >>>"
    echo -n "$knot_keys"
    echo "# <<< KNOT MESH MANAGED <<<"
  } > "$auth_file.tmp"

  mv "$auth_file.tmp" "$auth_file"
  chmod 600 "$auth_file"
  chown "$user:" "$auth_file"
  knot_log_ok "authorized_keys synchronized cleanly without altering personal keys."
}

ssh_sync_client_config() {
  local home
  home="$(knot_detect_user_home)"
  local user
  user="$(knot_detect_user)"
  local config_file="$home/.ssh/config"

  knot_log_info "Compiling ~/.ssh/config with knot-resolve host aliases across swarms..."
  mkdir -p "$home/.ssh"
  touch "$config_file"

  local existing_config=""
  if [ -f "$config_file" ]; then
    existing_config="$(sed '/# >>> KNOT MESH MANAGED.*>>>/,/# <<< KNOT MESH MANAGED.*<<</d' "$config_file")"
  fi

  local knot_cli="$KNOT_ROOT/core/resolver.sh"
  if command -v knot >/dev/null; then
    knot_cli="$(command -v knot) resolve"
  elif [ -x "$KNOT_ROOT/bin/knot" ]; then
    knot_cli="$KNOT_ROOT/bin/knot resolve"
  fi

  local knot_config=""

  # 1. Scoped aliases for multi-swarm profiles (~/.config/knot/swarms/<swarm_id>/nodes/)
  if [ -d "$home/.config/knot/swarms" ]; then
    for sdir in "$home/.config/knot/swarms/"*/nodes; do
      [ -d "$sdir" ] || continue
      local parent
      parent="$(dirname "$sdir")"
      local swarm_id
      swarm_id="$(basename "$parent")"

      for manifest in "$sdir/"*.json; do
        [ -e "$manifest" ] || continue
        local node_id remote_user hostname_val port
        node_id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        remote_user="$(awk -F'"' '/"user":/ {print $4}' "$manifest")"
        hostname_val="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
        port="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest")"
        if [ -z "$port" ]; then port="22"; fi

        if [ -n "$node_id" ] && [ -n "$remote_user" ]; then
          # Scoped Host: e.g. desktop.home
          local scoped_host="Host ${node_id}.${swarm_id}"
          if [ -n "$hostname_val" ] && [ "$hostname_val" != "$node_id" ]; then
            scoped_host+=" ${hostname_val}.${swarm_id}"
          fi
          knot_config+="$scoped_host"$'\n'
          if [ -n "$hostname_val" ]; then
            knot_config+="    HostName $hostname_val"$'\n'
          fi
          knot_config+="    User $remote_user"$'\n'
          knot_config+="    Port $port"$'\n'
          knot_config+="    ProxyCommand $knot_cli ${node_id}.${swarm_id} $port --proxy"$'\n'
          knot_config+="    IdentityFile ~/.ssh/id_ed25519"$'\n'
          knot_config+="    IdentitiesOnly yes"$'\n'
          knot_config+="    StrictHostKeyChecking accept-new"$'\n'
          knot_config+="    ServerAliveInterval 15"$'\n'
          knot_config+="    ServerAliveCountMax 3"$'\n'$'\n'
        fi
      done
    done
  fi

  # 2. Contextual aliases dynamically generated for the active swarm
  local active_swarm=""
  active_swarm="$(knot_get_active_swarm)"
  local active_nodes_dir=""
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    if [ -d "$home/.config/knot/swarms/${active_swarm}/nodes" ]; then
      active_nodes_dir="$home/.config/knot/swarms/${active_swarm}/nodes"
    elif [ -d "/etc/knot/swarms.d/${active_swarm}/nodes" ]; then
      active_nodes_dir="/etc/knot/swarms.d/${active_swarm}/nodes"
    fi
  fi

  if [ -n "$active_nodes_dir" ] && [ -d "$active_nodes_dir" ]; then
    for manifest in "$active_nodes_dir/"*.json; do
      [ -e "$manifest" ] || continue
      local node_id remote_user hostname_val port
      node_id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
      remote_user="$(awk -F'"' '/"user":/ {print $4}' "$manifest")"
      hostname_val="$(awk -F'"' '/"hostname":/ {print $4}' "$manifest")"
      port="$(awk -F: '/"port":/ {gsub(/[^0-9]/, "", $2); print $2}' "$manifest")"
      if [ -z "$port" ]; then port="22"; fi

      if [ -n "$node_id" ] && [ -n "$remote_user" ]; then
        local host_line="Host $node_id"
        if [ -n "$hostname_val" ] && [ "$hostname_val" != "$node_id" ]; then
          host_line+=" $hostname_val"
        fi
        knot_config+="$host_line"$'\n'
        if [ -n "$hostname_val" ] && [ "$hostname_val" != "$node_id" ]; then
          knot_config+="    HostName $hostname_val"$'\n'
        fi
        knot_config+="    User $remote_user"$'\n'
        knot_config+="    Port $port"$'\n'
        if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
          knot_config+="    ProxyCommand $knot_cli ${node_id}.${active_swarm} $port --proxy"$'\n'
        else
          knot_config+="    ProxyCommand $knot_cli $node_id $port --proxy"$'\n'
        fi
        knot_config+="    IdentityFile ~/.ssh/id_ed25519"$'\n'
        knot_config+="    IdentitiesOnly yes"$'\n'
        knot_config+="    StrictHostKeyChecking accept-new"$'\n'
        knot_config+="    ServerAliveInterval 15"$'\n'
        knot_config+="    ServerAliveCountMax 3"$'\n'$'\n'
      fi
    done
  fi

  {
    if [ -n "$existing_config" ]; then
      echo "$existing_config"
    fi
    echo "# >>> KNOT MESH MANAGED (DO NOT EDIT MANUALLY) >>>"
    echo -n "$knot_config"
    echo "# <<< KNOT MESH MANAGED <<<"
  } > "$config_file.tmp"

  mv "$config_file.tmp" "$config_file"
  chmod 600 "$config_file"
  chown "$user:" "$config_file"
  knot_log_ok "~/.ssh/config compiled with dynamic resolver ProxyCommands."
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    sync-config|client-config)
      ssh_sync_client_config
      ;;
    sync-keys|authorized-keys)
      ssh_sync_authorized_keys
      ;;
    harden)
      ssh_harden_server
      ;;
    *)
      ssh_ensure_local_key
      ssh_sync_authorized_keys
      ssh_sync_client_config
      ;;
  esac
fi
