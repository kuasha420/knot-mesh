#!/usr/bin/env bash
set -euo pipefail

# Knot Swarm Sync Module - Multi-Node Config, Manifest, and Topology Distribution
# Zero secret leakage: only synchronizes public metadata, topology, and swarm configs.

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/ssh.sh"
source "$KNOT_ROOT/core/modules/deskflow.sh"
source "$KNOT_ROOT/core/modules/kdeconnect.sh"

swarm_sync_anchor_push() {
  local target="$1"
  local active_swarm="$2"
  local nodes_dir="$3"
  local topo_file="$4"
  local swarm_conf="$5"
  local dev_mode="${6:-0}"
  local force_prod="${7:-0}"

  knot_log_info "Pushing swarm configuration to Strand '$target'..."

  # Check for remote install type if running in production mode
  if [ "$dev_mode" -eq 0 ]; then
    local is_remote_dev=0
    local probe_dev=""
    if probe_dev="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target" '
      if [ -f "$HOME/.config/knot/install_type" ]; then
        grep -q "^dev$" "$HOME/.config/knot/install_type"
      elif [ -d "$HOME/Dev/knot-mesh/.git" ] || [ -d "$HOME/knot-mesh/.git" ]; then
        exit 0
      else
        exit 1
      fi
    ' 2>&1)"; then
      is_remote_dev=1
    fi

    if [ "$is_remote_dev" -eq 1 ] && [ "$force_prod" -eq 0 ]; then
      knot_log_warn "Strand '$target' is running a DEVELOPMENT installation. Skipping production file push & sync."
      echo -e "  (Use 'knot sync --dev $target' or pass --force-prod to override)"
      return 0
    fi
  fi

  # 1. Connectivity probe
  local probe_out=""
  if ! probe_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "echo ok" 2>&1)"; then
    knot_log_err "Target Strand '$target' is unreachable over SSH: $probe_out"
    return 1
  fi

  # 2. Ensure remote directories exist
  local mkdir_out=""
  if ! mkdir_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "mkdir -p \$HOME/.config/knot/swarms/${active_swarm}/nodes \$HOME/.local/state/knot \$HOME/.config/Deskflow/tls" 2>&1)"; then
    knot_log_err "Failed to create remote swarm directories on '$target': $mkdir_out"
    return 1
  fi

  # 3. Check for remote rsync support
  local has_rsync=0
  if ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "command -v rsync >/dev/null" 2>&1; then
    has_rsync=1
  fi

  # 4. Transfer swarm profile, node manifests, topology.json, and Deskflow TLS cert
  local home
  home="$(knot_detect_user_home)"
  local tls_cert="$home/.config/Deskflow/tls/deskflow.pem"

  if [ "$has_rsync" -eq 1 ]; then
    local rsync_err=""
    if ! rsync_err="$(rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$nodes_dir/" "${target}:.config/knot/swarms/${active_swarm}/nodes/" 2>&1)"; then
      knot_log_err "Failed to rsync node manifests to '$target': $rsync_err"
      return 1
    fi

    if [ -n "$topo_file" ] && [ -r "$topo_file" ]; then
      if ! rsync_err="$(rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$topo_file" "${target}:.config/knot/swarms/${active_swarm}/topology.json" 2>&1)"; then
        knot_log_err "Failed to rsync topology.json to '$target': $rsync_err"
        return 1
      fi
    fi

    if [ -n "$swarm_conf" ] && [ -r "$swarm_conf" ]; then
      if ! rsync_err="$(rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$swarm_conf" "${target}:.config/knot/swarms/${active_swarm}/swarm.conf" 2>&1)"; then
        knot_log_err "Failed to rsync swarm.conf to '$target': $rsync_err"
        return 1
      fi
      if ! rsync_err="$(rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$swarm_conf" "${target}:.config/knot/swarms/${active_swarm}.conf" 2>&1)"; then
        knot_log_err "Failed to rsync ${active_swarm}.conf to '$target': $rsync_err"
        return 1
      fi
    fi

    if [ -f "$tls_cert" ] && [ -r "$tls_cert" ]; then
      if ! rsync_err="$(rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5" "$tls_cert" "${target}:.config/Deskflow/tls/deskflow.pem" 2>&1)"; then
        knot_log_warn "Notice: Failed to rsync deskflow.pem to '$target': $rsync_err"
      fi
    fi
  else
    # Streaming tar fallback for systems without rsync (e.g. rog-ally)
    local staging_dir
    staging_dir="$(mktemp -d)"
    mkdir -p "$staging_dir/nodes"
    cp -r "$nodes_dir"/* "$staging_dir/nodes/"
    if [ -n "$topo_file" ] && [ -r "$topo_file" ]; then
      cp "$topo_file" "$staging_dir/topology.json"
    fi
    if [ -n "$swarm_conf" ] && [ -r "$swarm_conf" ]; then
      cp "$swarm_conf" "$staging_dir/swarm.conf"
      cp "$swarm_conf" "$staging_dir/${active_swarm}.conf"
    fi

    local tar_err=""
    if ! tar_err="$(tar -czf - -C "$staging_dir" . | ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "tar -xzf - -C \$HOME/.config/knot/swarms/${active_swarm}/" 2>&1)"; then
      rm -rf "$staging_dir"
      knot_log_err "Failed to stream swarm archive to '$target': $tar_err"
      return 1
    fi
    rm -rf "$staging_dir"

    if [ -f "$tls_cert" ] && [ -r "$tls_cert" ]; then
      local scp_err=""
      if ! scp_err="$(scp -o BatchMode=yes -o ConnectTimeout=5 "$tls_cert" "${target}:.config/Deskflow/tls/deskflow.pem" 2>&1)"; then
        knot_log_warn "Notice: Failed to scp deskflow.pem to '$target': $scp_err"
      fi
    fi
  fi

  # 5. Remote system-wide profile and active swarm state configuration
  local state_err=""
  if ! state_err="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "
    if sudo -n true 2>&1; then
      sudo mkdir -p /etc/knot/swarms.d /run/knot
      sudo cp -f \$HOME/.config/knot/swarms/${active_swarm}/swarm.conf /etc/knot/swarms.d/${active_swarm}.conf
      echo '${active_swarm}' | sudo tee /run/knot/active_swarm >/dev/null
    fi
    echo '${active_swarm}' > \$HOME/.local/state/knot/active_swarm
  " 2>&1)"; then
    knot_log_warn "Notice: Remote system state update on $target: $state_err"
  fi

  # 6. Synchronize updated Knot CLI scripts to remote installation if found (production only)
  if [ "$dev_mode" -eq 0 ]; then
    local remote_bin=""
    if remote_bin="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "readlink -f \$(which knot 2>&1) 2>&1")"; then
      if [ -n "$remote_bin" ] && [[ "$remote_bin" =~ ^/ ]] && [[ "$remote_bin" =~ /knot$ ]]; then
        local remote_knot_root
        remote_knot_root="$(dirname "$(dirname "$remote_bin")")"
        if [ -d "$KNOT_ROOT/bin" ] && [ -d "$KNOT_ROOT/core" ]; then
          ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "mkdir -p \"\$HOME/.local/share/knot-mesh\" \"$remote_knot_root/bin\" \"$remote_knot_root/core\"" 2>&1
          if [ "$has_rsync" -eq 1 ]; then
            rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new" "$KNOT_ROOT/bin/" "${target}:${remote_knot_root}/bin/" 2>&1
            rsync -az -e "ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new" "$KNOT_ROOT/core/" "${target}:${remote_knot_root}/core/" 2>&1
          else
            tar -czf - -C "$KNOT_ROOT" bin core | ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "tar -xzf - -C \"$remote_knot_root\"" 2>&1
          fi
        fi
      fi
    fi
  fi

  # 7. Dispatch remote knot sync on the Strand to recompile client Deskflow config
  knot_log_info "Executing remote knot sync on '$target'..."
  local remote_sync_cmd="export PATH=\"\$HOME/.local/bin:/usr/local/bin:\$PATH\"; knot sync"
  if [ "$dev_mode" -eq 1 ]; then
    remote_sync_cmd="$remote_sync_cmd --dev"
  elif [ "$force_prod" -eq 1 ]; then
    remote_sync_cmd="$remote_sync_cmd --force-prod"
  fi

  local remote_sync_out=""
  if ! remote_sync_out="$(ssh -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new "$target" "$remote_sync_cmd" 2>&1)"; then
    knot_log_err "Remote knot sync failed on '$target': $remote_sync_out"
    return 1
  fi
  echo "$remote_sync_out"

  # 8. Reload auxiliary daemons if currently active
  local reload_err=""
  if ! reload_err="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$target" "
    if systemctl --user is-active knot-agent.service 2>&1 | grep -q '^active'; then
      systemctl --user try-restart knot-agent.service 2>&1
    fi
    if sudo -n systemctl is-active knot-guard.service 2>&1 | grep -q '^active'; then
      sudo -n systemctl try-restart knot-guard.service 2>&1
    fi
  " 2>&1)"; then
    knot_log_warn "Notice: Daemon reload on $target: $reload_err"
  fi

  knot_log_ok "Swarm synchronization complete for Strand '$target'."
  return 0
}

swarm_sync_strand_pull() {
  local user_home
  user_home="$(knot_detect_user_home)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"

  knot_log_info "Synchronizing Strand configuration from active Anchor ($active_swarm)..."

  local anchor_id="desktop"
  local anchor_host="desktop"
  local hub_port=4242
  if knot_load_swarm_profile "$active_swarm"; then
    anchor_id="${ANCHOR_ID:-desktop}"
    anchor_host="${ANCHOR_HOST:-desktop}"
    hub_port="${HUB_PORT:-4242}"
  fi

  local target_swarm_dir="$user_home/.config/knot/swarms/${active_swarm}"
  mkdir -p "$target_swarm_dir/nodes" "$user_home/.local/state/knot"

  local pulled=0

  # 1. Attempt to pull from Anchor via SSH / SCP / rsync
  for candidate in "$anchor_id" "$anchor_host"; do
    [ -n "$candidate" ] || continue
    local check_out=""
    if check_out="$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$candidate" "echo ok" 2>&1)" && [ "$check_out" = "ok" ]; then
      local remote_home
      if remote_home="$(ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "$candidate" 'echo $HOME' 2>&1)" && [ -n "$remote_home" ]; then
        local remote_swarm_dir="$remote_home/.config/knot/swarms/${active_swarm}"
        local stream_err=""
        if stream_err="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$candidate" "tar -czf - -C \"$remote_swarm_dir\" topology.json swarm.conf nodes 2>&1" | tar -xzf - -C "$target_swarm_dir" 2>&1)"; then
          pulled=1
          knot_log_ok "Successfully pulled latest swarm topology and manifests from Anchor ($candidate) via SSH."
          break
        else
          knot_log_warn "Notice: SSH archive pull from $candidate failed: $stream_err"
        fi
      fi
    fi
  done

  # 2. Fallback to Anchor Hub HTTP API if SSH pull didn't succeed
  if [ "$pulled" -eq 0 ]; then
    knot_log_info "Attempting to pull topology from Anchor Hub (https://${anchor_host}:${hub_port})..."
    local topo_out="$target_swarm_dir/topology.json"
    local hub_err=""
    if hub_err="$(curl -kfsSL "https://${anchor_host}:${hub_port}/topology" -o "$topo_out" 2>&1)"; then
      pulled=1
      knot_log_ok "Successfully pulled latest topology from Anchor Hub."

      local nodes_json=""
      if nodes_json="$(curl -kfsSL "https://${anchor_host}:${hub_port}/nodes" 2>&1)"; then
        python3 -c "
import json, sys, os
try:
    data = json.loads(sys.argv[1])
    nodes = data if isinstance(data, dict) else {}
    if 'nodes' in nodes and isinstance(nodes['nodes'], dict):
        nodes = nodes['nodes']
    nodes_dir = sys.argv[2]
    for nid, ndata in nodes.items():
        with open(os.path.join(nodes_dir, f'{nid}.json'), 'w') as f:
            json.dump(ndata, f, indent=2)
except Exception as e:
    sys.stderr.write(f'Notice: node extraction: {e}\n')
" "$nodes_json" "$target_swarm_dir/nodes"
      fi
    else
      knot_log_warn "Notice: Anchor Hub pull failed: $hub_err"
    fi
  fi

  # 3. If neither pull succeeded, check if cached local configuration exists
  if [ "$pulled" -eq 0 ]; then
    if [ -f "$target_swarm_dir/topology.json" ] && [ -d "$target_swarm_dir/nodes" ]; then
      knot_log_warn "Notice: Anchor unreachable; utilizing existing local swarm profile and topology."
    else
      knot_log_err "Failed to synchronize swarm profile from Anchor ($anchor_host) and no local profile found."
      return 1
    fi
  fi

  # 4. Reconcile swarm.conf and system drop-in if sudo is permitted
  if [ -f "$target_swarm_dir/swarm.conf" ]; then
    cp -f "$target_swarm_dir/swarm.conf" "$user_home/.config/knot/swarms/${active_swarm}.conf"
    if sudo -n true 2>&1; then
      sudo mkdir -p /etc/knot/swarms.d
      sudo cp -f "$target_swarm_dir/swarm.conf" "/etc/knot/swarms.d/${active_swarm}.conf"
    fi
  fi

  # 5. Set active swarm state
  knot_set_active_swarm "$active_swarm"

  # 6. Apply local mesh and Deskflow client configurations
  knot_log_info "Synchronizing local Strand mesh and Deskflow client..."
  ssh_sync_authorized_keys
  ssh_sync_client_config
  deskflow_configure
  kdeconnect_sync_mesh

  knot_log_ok "Strand mesh synchronization complete."
  return 0
}

# Heals development configuration drift on the local node
swarm_sync_dev_heal_local() {
  local knot_root="$KNOT_ROOT"
  local home
  home="$(knot_detect_user_home)"

  knot_log_info "Healing development environment drift locally..."

  # 1. Set explicit installation type marker to dev
  mkdir -p "$home/.config/knot"
  echo "dev" > "$home/.config/knot/install_type"

  # 2. Binary symlinks: ensure ~/.local/bin/knot and knot-installer point to active repo
  mkdir -p "$home/.local/bin"
  if [ -x "$knot_root/bin/knot" ]; then
    ln -sf "$knot_root/bin/knot" "$home/.local/bin/knot"
    chmod +x "$knot_root/bin/knot"
  fi
  if [ -x "$knot_root/bin/knot-installer" ]; then
    ln -sf "$knot_root/bin/knot-installer" "$home/.local/bin/knot-installer"
    chmod +x "$knot_root/bin/knot-installer"
  fi

  # 3. Global Antigravity skill symlink
  mkdir -p "$home/.gemini/config/skills"
  if [ -d "$knot_root/skills/swarm-council" ]; then
    ln -sfn "$knot_root/skills/swarm-council" "$home/.gemini/config/skills/swarm-council"
  fi

  # 4. Global Antigravity lifecycle hook: ~/.gemini/config/hooks.json
  cat << 'EOF_HOOKS' > "$home/.config/knot/hooks.json.tmp"
{
  "swarm-council-coordinator": {
    "PreInvocation": [
      {
        "type": "command",
        "command": "python3 ~/.gemini/config/skills/swarm-council/scripts/council_hook.py",
        "timeout": 5
      }
    ]
  }
}
EOF_HOOKS
  mv "$home/.config/knot/hooks.json.tmp" "$home/.gemini/config/hooks.json"
  chmod 644 "$home/.gemini/config/hooks.json"

  # 5. Antigravity settings auto-healing
  python3 - << 'PY_EOF'
import json, os

home = os.path.expanduser("~")
p1 = os.path.join(home, ".gemini/config/config.json")
p2 = os.path.join(home, ".gemini/antigravity-cli/settings.json")

if os.path.exists(p1):
    try:
        with open(p1, "r") as f:
            d = json.load(f)
        u = d.setdefault("userSettings", {})
        u["useAiCredits"] = False
        u["useG1Credits"] = False
        u["themeMode"] = "THEME_MODE_DARK"
        with open(p1, "w") as f:
            json.dump(d, f, indent=2)
    except Exception:
        pass

if os.path.exists(p2):
    try:
        with open(p2, "r") as f:
            d = json.load(f)
        d["useAiCredits"] = False
        d["useG1Credits"] = False
        d["accepted_latest_terms_of_service"] = True
        d["theme"] = "dark"
        d["theme_mode"] = "THEME_MODE_DARK"
        with open(p2, "w") as f:
            json.dump(d, f, indent=2)
    except Exception:
        pass
PY_EOF

  knot_log_ok "Local development environment and Antigravity customizations healed."
  return 0
}

# Heals development configuration drift remotely on a specific strand
swarm_sync_dev_heal_remote() {
  local target="$1"
  knot_log_info "Healing development environment drift on Strand '$target'..."

  if ! ssh -o BatchMode=yes -o ConnectTimeout=4 "$target" "true" 2>&1; then
    knot_log_warn "Strand '$target' is unreachable over SSH. Skipping dev healing."
    return 1
  fi

  local remote_cmd='
    set -euo pipefail
    DEV_DIR=""
    for cand in "$HOME/Dev/knot-mesh" "$HOME/knot-mesh" "$HOME/.local/share/knot-mesh"; do
      if [ -d "$cand/.git" ]; then
        DEV_DIR="$cand"
        break
      fi
    done

    if [ -z "$DEV_DIR" ]; then
      echo "ERROR: No knot-mesh git repository found on target node."
      exit 1
    fi

    mkdir -p "$HOME/.config/knot" "$HOME/.local/bin" "$HOME/.gemini/config/skills"
    echo "dev" > "$HOME/.config/knot/install_type"

    ln -sf "$DEV_DIR/bin/knot" "$HOME/.local/bin/knot"
    chmod +x "$DEV_DIR/bin/knot"
    if [ -x "$DEV_DIR/bin/knot-installer" ]; then
      ln -sf "$DEV_DIR/bin/knot-installer" "$HOME/.local/bin/knot-installer"
      chmod +x "$DEV_DIR/bin/knot-installer"
    fi

    if [ -d "$DEV_DIR/skills/swarm-council" ]; then
      ln -sfn "$DEV_DIR/skills/swarm-council" "$HOME/.gemini/config/skills/swarm-council"
    fi

    cat << "EOF_HOOK" > "$HOME/.gemini/config/hooks.json"
{
  "swarm-council-coordinator": {
    "PreInvocation": [
      {
        "type": "command",
        "command": "python3 ~/.gemini/config/skills/swarm-council/scripts/council_hook.py",
        "timeout": 5
      }
    ]
  }
}
EOF_HOOK
    chmod 644 "$HOME/.gemini/config/hooks.json"

    python3 - << "PY_INNER"
import json, os
home = os.path.expanduser("~")
p1 = os.path.join(home, ".gemini/config/config.json")
p2 = os.path.join(home, ".gemini/antigravity-cli/settings.json")
for p in [p1, p2]:
    if os.path.exists(p):
        try:
            with open(p, "r") as f: d = json.load(f)
            if "userSettings" in d:
                d["userSettings"].update({"useAiCredits": False, "useG1Credits": False, "themeMode": "THEME_MODE_DARK"})
            else:
                d.update({"useAiCredits": False, "useG1Credits": False, "accepted_latest_terms_of_service": True, "theme": "dark", "theme_mode": "THEME_MODE_DARK"})
            with open(p, "w") as f: json.dump(d, f, indent=2)
        except Exception: pass
PY_INNER
    echo "OK: $DEV_DIR"
  '

  local heal_out=""
  if heal_out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$target" "$remote_cmd" 2>&1)"; then
    knot_log_ok "Strand '$target' dev environment healed ($heal_out)."
    return 0
  else
    knot_log_err "Failed to heal dev environment on '$target': $heal_out"
    return 1
  fi
}

# Master development synchronization entrypoint
swarm_sync_dev() {
  local target="${1:-}"
  local force="${2:-0}"

  knot_enforce_lockout "dev" "knot sync" "$force" || return 1

  swarm_sync_dev_heal_local

  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local my_host
  my_host="$(knot_detect_hostname)"
  local is_anchor=0
  if knot_is_anchor; then
    is_anchor=1
  fi

  if [ "$is_anchor" -eq 1 ]; then
    if [ "$target" = "--all" ]; then
      knot_log_info "Synchronizing development mesh across all active Strands..."
      ssh_sync_authorized_keys
      ssh_sync_client_config
      deskflow_configure
      kdeconnect_sync_mesh

      local nodes_dir=""
      if ! nodes_dir="$(knot_get_nodes_dir)"; then
        knot_log_err "No nodes directory found for active swarm '$active_swarm'"
        return 1
      fi

      local topo_file=""
      local user_home
      user_home="$(knot_detect_user_home)"
      if [ -r "$user_home/.config/knot/swarms/${active_swarm}/topology.json" ]; then
        topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
      fi

      local swarm_conf=""
      if [ -r "$user_home/.config/knot/swarms/${active_swarm}/swarm.conf" ]; then
        swarm_conf="$user_home/.config/knot/swarms/${active_swarm}/swarm.conf"
      fi

      local sync_count=0
      for manifest in "$nodes_dir/"*.json; do
        [ -e "$manifest" ] || continue
        local id role
        id="$(awk -F'"' '/"id":/ {print $4}' "$manifest")"
        role="$(awk -F'"' '/"role":/ {print $4}' "$manifest")"
        if [ "$role" = "anchor" ] || [ "$id" = "$my_host" ]; then
          continue
        fi

        # Probe remote install type
        local r_type=""
        if ! r_type="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$id" '
          if [ -f "$HOME/.config/knot/install_type" ]; then
            tr -d "[:space:]" < "$HOME/.config/knot/install_type"
          elif [ -d "$HOME/Dev/knot-mesh/.git" ] || [ -d "$HOME/knot-mesh/.git" ]; then
            echo "dev"
          else
            echo "prod"
          fi
        ' 2>&1)"; then
          knot_log_warn "Notice: Unable to probe install type on '$id': $r_type"
          r_type="unknown"
        fi

        if [ "$r_type" = "prod" ] && [ "$force" -eq 0 ]; then
          knot_log_warn "Strand '$id' is a PRODUCTION installation. Skipping dev drift healing (use --force-dev to override)."
          swarm_sync_anchor_push "$id" "$active_swarm" "$nodes_dir" "$topo_file" "$swarm_conf" 0 1
          sync_count=$((sync_count + 1))
          continue
        fi

        swarm_sync_dev_heal_remote "$id"
        swarm_sync_anchor_push "$id" "$active_swarm" "$nodes_dir" "$topo_file" "$swarm_conf" 1
        sync_count=$((sync_count + 1))
      done
      knot_log_ok "Mesh-wide development synchronization complete ($sync_count Strands updated and healed)."
    elif [ -n "$target" ] && [ "$target" != "$my_host" ] && [ "$target" != "local" ] && [ "$target" != "localhost" ]; then
      local r_type=""
      if ! r_type="$(ssh -o BatchMode=yes -o ConnectTimeout=4 "$target" '
        if [ -f "$HOME/.config/knot/install_type" ]; then
          tr -d "[:space:]" < "$HOME/.config/knot/install_type"
        elif [ -d "$HOME/Dev/knot-mesh/.git" ] || [ -d "$HOME/knot-mesh/.git" ]; then
          echo "dev"
        else
          echo "prod"
        fi
      ' 2>&1)"; then
        knot_log_warn "Notice: Unable to probe install type on '$target': $r_type"
        r_type="unknown"
      fi

      if [ "$r_type" = "prod" ] && [ "$force" -eq 0 ]; then
        knot_log_err "Strand '$target' is a PRODUCTION installation. Skipping dev sync (use --force-dev to override)."
        return 1
      fi

      swarm_sync_dev_heal_remote "$target"
      local nodes_dir=""
      if nodes_dir="$(knot_get_nodes_dir)"; then
        local user_home
        user_home="$(knot_detect_user_home)"
        local topo_file="$user_home/.config/knot/swarms/${active_swarm}/topology.json"
        local swarm_conf="$user_home/.config/knot/swarms/${active_swarm}/swarm.conf"
        swarm_sync_anchor_push "$target" "$active_swarm" "$nodes_dir" "$topo_file" "$swarm_conf" 1
      fi
      knot_log_ok "Development synchronization to Strand '$target' complete."
    else
      ssh_sync_authorized_keys
      ssh_sync_client_config
      deskflow_configure
      kdeconnect_sync_mesh
      knot_log_ok "Local Anchor development configuration synchronized."
    fi
  else
    swarm_sync_strand_pull
  fi

  return 0
}
