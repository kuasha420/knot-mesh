#!/usr/bin/env bash
set -euo pipefail

# Knot Deskflow (KVM) Layout & Dynamic Client Service Module

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/autounlock.sh"

deskflow_compile_server_config() {
  local mode="${1:-unlocked}"
  local home
  home="$(knot_detect_user_home)"
  local cfg_dir="$home/.config/Deskflow"
  mkdir -p "$cfg_dir"

  local active_swarm
  active_swarm="$(knot_get_active_swarm)"

  local topo_file=""
  if [ -r "$home/.config/knot/swarms/${active_swarm}/topology.json" ]; then
    topo_file="$home/.config/knot/swarms/${active_swarm}/topology.json"
  elif [ -r "/etc/knot/swarms.d/${active_swarm}/topology.json" ]; then
    topo_file="/etc/knot/swarms.d/${active_swarm}/topology.json"
  elif [ -r "$KNOT_ROOT/templates/topology.example.json" ]; then
    topo_file="$KNOT_ROOT/templates/topology.example.json"
  elif [ -r "$KNOT_ROOT/registry/topology.json" ]; then
    topo_file="$KNOT_ROOT/registry/topology.json"
  fi

  local nodes_dir=""
  if [ -d "$home/.config/knot/swarms/${active_swarm}/nodes" ]; then
    nodes_dir="$home/.config/knot/swarms/${active_swarm}/nodes"
  elif [ -d "/etc/knot/swarms.d/${active_swarm}/nodes" ]; then
    nodes_dir="/etc/knot/swarms.d/${active_swarm}/nodes"
  elif [ -d "$KNOT_ROOT/templates/nodes" ]; then
    nodes_dir="$KNOT_ROOT/templates/nodes"
  fi

  if [ -n "$topo_file" ] && [ -n "$nodes_dir" ] && [ -x "$KNOT_ROOT/core/modules/compile_deskflow.py" ]; then
    python3 "$KNOT_ROOT/core/modules/compile_deskflow.py" \
      --topology "$topo_file" \
      --nodes-dir "$nodes_dir" \
      --mode "$mode" \
      --output "$cfg_dir/deskflow-server.conf"
    return 0
  fi

  knot_log_err "Could not find topology.json or nodes directory to compile Deskflow layout"
  return 1
}

deskflow_write_server_conf() {
  local mode="${1:-$(deskflow_get_lock)}"
  deskflow_compile_server_config "$mode"

  local home
  home="$(knot_detect_user_home)"
  local cfg_dir="$home/.config/Deskflow"
  mkdir -p "$cfg_dir"
  local my_host
  my_host="$(knot_detect_hostname)"

  cat << CONF_EOF > "$cfg_dir/Deskflow.conf"
[core]
computerName=${my_host:-localhost}

[server]
externalConfig=true
externalConfigFile=$cfg_dir/deskflow-server.conf
CONF_EOF

  return 0
}

deskflow_write_client_conf() {
  local home
  home="$(knot_detect_user_home)"
  local cfg_dir="$home/.config/Deskflow"
  mkdir -p "$cfg_dir"

  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local my_host
  my_host="$(knot_detect_hostname)"

  local anchor_target="desktop"
  local anchor_host="desktop.local"
  local swarm_cfg=""
  if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
    swarm_cfg="/etc/knot/swarms.d/${active_swarm}.conf"
  elif [ -r "$home/.config/knot/swarms/${active_swarm}.conf" ]; then
    swarm_cfg="$home/.config/knot/swarms/${active_swarm}.conf"
  elif [ -r "$home/.config/knot/swarms/${active_swarm}/swarm.conf" ]; then
    swarm_cfg="$home/.config/knot/swarms/${active_swarm}/swarm.conf"
  fi

  if [ -n "$swarm_cfg" ] && [ -r "$swarm_cfg" ]; then
    local a_id_cfg a_host_cfg
    a_id_cfg="$(awk -F= '/^ANCHOR_ID=/ {print $2}' "$swarm_cfg" | tr -d '"'\'' ')"
    a_host_cfg="$(awk -F= '/^ANCHOR_HOST=/ {print $2}' "$swarm_cfg" | tr -d '"'\'' ')"
    [ -n "$a_id_cfg" ] && anchor_target="$a_id_cfg"
    [ -n "$a_host_cfg" ] && anchor_host="$a_host_cfg"
  fi

  local resolved_ip=""
  local knot_cli=""
  if command -v knot >/dev/null; then
    knot_cli="$(command -v knot)"
  elif [ -x "$home/.local/bin/knot" ]; then
    knot_cli="$home/.local/bin/knot"
  fi

  if [ -n "$knot_cli" ]; then
    local r_cand=""
    if r_cand="$("$knot_cli" resolve "$anchor_target" 24800 2>&1)"; then
      resolved_ip="$r_cand"
    elif [ "$anchor_host" != "$anchor_target" ]; then
      if r_cand="$("$knot_cli" resolve "$anchor_host" 24800 2>&1)"; then
        resolved_ip="$r_cand"
      fi
    fi
  fi

  if [ -z "$resolved_ip" ] && [ -n "$anchor_host" ]; then
    resolved_ip="$anchor_host"
  fi

  local client_name="$my_host"
  local nodes_dir=""
  if [ -d "$home/.config/knot/swarms/${active_swarm}/nodes" ]; then
    nodes_dir="$home/.config/knot/swarms/${active_swarm}/nodes"
  elif [ -d "/etc/knot/swarms.d/${active_swarm}/nodes" ]; then
    nodes_dir="/etc/knot/swarms.d/${active_swarm}/nodes"
  fi

  if [ -n "$nodes_dir" ]; then
    for mf in "$nodes_dir/"*.json; do
      [ -r "$mf" ] || continue
      local m_host m_id m_user
      m_host="$(awk -F'"' '/"hostname":/ {print $4}' "$mf")"
      m_id="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
      m_user="$(awk -F'"' '/"user":/ {print $4}' "$mf")"
      if [ "$m_host" = "$my_host" ] || [ "$m_id" = "$my_host" ]; then
        client_name="${m_host:-$my_host}"
        break
      fi
      if [ "$m_user" = "${USER:-}" ] && [ "$m_id" != "$anchor_target" ]; then
        client_name="${m_host:-$m_id}"
      fi
    done
  fi

  cat << CONF_EOF > "$cfg_dir/Deskflow.conf"
[core]
computerName=${client_name:-localhost}

[client]
remoteHost=${resolved_ip:-$anchor_host}
CONF_EOF

  return 0
}

deskflow_sync_display_layout() {
  local home
  home="$(knot_detect_user_home)"
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  local my_host
  my_host="$(knot_detect_hostname)"
  local anchor_manifest="$home/.config/knot/swarms/${active_swarm}/nodes/${my_host}.json"

  if [ -f "$anchor_manifest" ] && command -v kscreen-doctor >/dev/null; then
    local display_sh="$KNOT_ROOT/core/installer/display.sh"
    if [ -x "$display_sh" ]; then
      local fresh_display
      if fresh_display="$("$display_sh" --json 2>&1)"; then
        if [ -n "$fresh_display" ]; then
          python3 -c '
import json, sys
m_path = sys.argv[1]
try:
    fresh = json.loads(sys.argv[2])
    with open(m_path, "r") as f:
        data = json.load(f)
    if data.get("display") != fresh:
        data["display"] = fresh
        with open(m_path, "w") as f:
            json.dump(data, f, indent=2)
except Exception as e:
    sys.stderr.write(f"Notice: manifest display sync skipped: {e}\n")
' "$anchor_manifest" "$fresh_display"
        fi
      fi
    fi
  fi
  deskflow_compile_server_config "$(deskflow_get_lock)"
}

deskflow_get_lock() {
  local home
  home="$(knot_detect_user_home)"
  local state_file="$home/.local/state/knot/kvm_lock"
  if [ -f "$state_file" ] && [ "$(cat "$state_file")" = "locked" ]; then
    echo "locked"
  else
    echo "unlocked"
  fi
}

deskflow_set_lock() {
  local target_state="${1:-toggle}"
  local home
  home="$(knot_detect_user_home)"
  local state_dir="$home/.local/state/knot"
  mkdir -p "$state_dir"
  local state_file="$state_dir/kvm_lock"

  if [ "$target_state" = "toggle" ]; then
    local current
    current="$(deskflow_get_lock)"
    if [ "$current" = "locked" ]; then
      target_state="unlocked"
    else
      target_state="locked"
    fi
  fi

  if [ "$target_state" = "locked" ]; then
    deskflow_write_server_conf "locked"
    echo "locked" > "$state_file"
    systemctl --user restart knot-deskflow
    if command -v notify-send >/dev/null; then
      if ! notify-send -a "Knot KVM" -i input-mouse "KVM Cursor Locked" "Host cursor confined to desktop screen"; then
        knot_log_warn "Failed to deliver desktop notification"
      fi
    fi
    knot_log_ok "KVM cursor locked to host desktop."
  else
    deskflow_write_server_conf "unlocked"
    echo "unlocked" > "$state_file"
    systemctl --user restart knot-deskflow
    if command -v notify-send >/dev/null; then
      if ! notify-send -a "Knot KVM" -i input-mouse "KVM Crossover Active" "Cursor can move to Laptop & Steam Deck"; then
        knot_log_warn "Failed to deliver desktop notification"
      fi
    fi
    knot_log_ok "KVM cursor unlocked (multi-screen crossover enabled)."
  fi
}

deskflow_configure() {
  local home
  home="$(knot_detect_user_home)"
  local user
  user="$(knot_detect_user)"
  local my_host
  my_host="$(knot_detect_hostname)"
  local cfg_dir="$home/.config/Deskflow"

  local anchor_host=""
  local active_swarm
  active_swarm="$(knot_get_active_swarm)"
  if [ -n "$active_swarm" ] && [ "$active_swarm" != "none" ]; then
    local SWARM_ID="" ANCHOR_ID="" ANCHOR_HOST=""
    if [ -r "/etc/knot/swarms.d/${active_swarm}.conf" ]; then
      # shellcheck disable=SC1090
      source "/etc/knot/swarms.d/${active_swarm}.conf"
      anchor_host="${ANCHOR_HOST:-$ANCHOR_ID}"
    fi
  fi

  # 0. Ensure Deskflow package is installed
  if ! command -v deskflow-core >/dev/null; then
    knot_log_info "Installing deskflow package..."
    sudo pacman -S --needed --noconfirm deskflow
  fi

  # 1. Compile server configuration layout (Screens, Links, Aliases, Options)
  deskflow_write_server_conf "unlocked"
  mkdir -p "$home/.local/state/knot"
  echo "unlocked" > "$home/.local/state/knot/kvm_lock"

  # 3. Configure notifyrc and portal pre-authorization across all nodes
  cat << 'NOTIFY_EOF' > "$home/.config/xdg-desktop-portal-kde.notifyrc"
[Event/inputcapturestarted]
Action=None
Execute=
Logfile=
Sound=

[Event/inputcapturesessionrestored]
Action=None
Execute=
Logfile=
Sound=

[Event/inputcapturesrestored]
Action=None
Execute=
Logfile=
Sound=

[Event/remotedesktopstarted]
Action=None
Execute=
Logfile=
Sound=
NOTIFY_EOF

  if command -v flatpak >/dev/null; then
    flatpak permission-set kde-authorized remote-desktop "" yes
    flatpak permission-set kde-authorized remote-desktop org.deskflow.deskflow yes
    flatpak permission-set kde-authorized remote-desktop deskflow yes
    flatpak permission-set kde-authorized remote-desktop deskflow-core yes
  fi

  # 4. Stop and clean up legacy input-leap units and processes
  if systemctl --user is-active --quiet knot-input-leap.service; then
    systemctl --user stop knot-input-leap.service
  fi
  if systemctl --user is-enabled --quiet knot-input-leap.service; then
    systemctl --user disable knot-input-leap.service
  fi

  for proc in input-leap input-leaps input-leapc; do
    if pgrep -x "$proc" >/dev/null; then
      killall -9 "$proc"
    fi
  done

  # 5. Configure TLS certificates & mutual fingerprint trust across mesh
  local tls_dir="$cfg_dir/tls"
  mkdir -p "$tls_dir"
  chmod 700 "$tls_dir"

  if [ ! -f "$tls_dir/deskflow.pem" ]; then
    if [ "$my_host" = "$anchor_host" ]; then
      openssl req -x509 -nodes -days 3650 -subj "/CN=Deskflow" -newkey rsa:2048 \
        -keyout "$tls_dir/deskflow.pem" -out "$tls_dir/deskflow.pem"
      chmod 600 "$tls_dir/deskflow.pem"
    else
      knot_log_info "Fetching Deskflow mesh TLS certificate from Anchor..."
      local hub_addr="${ANCHOR_HOST}:${HUB_PORT:-4242}"
      local fetched=0
      if curl -kfsSL "https://${hub_addr}/dist/deskflow.pem" -o "$tls_dir/deskflow.pem" 2>/dev/null; then
        fetched=1
        knot_log_ok "Synchronized Deskflow TLS certificate from Anchor Hub."
      elif [ -n "$KNOT_CLI" ]; then
        local resolved_ip
        if resolved_ip="$("$KNOT_CLI" resolve "$ANCHOR_TARGET" 4242 2>&1)"; then
          if curl -kfsSL "https://${resolved_ip}:4242/dist/deskflow.pem" -o "$tls_dir/deskflow.pem" 2>/dev/null; then
            fetched=1
            knot_log_ok "Synchronized Deskflow TLS certificate from Anchor IP ($resolved_ip)."
          fi
        fi
      fi

      if [ $fetched -eq 0 ] && [ ! -f "$tls_dir/deskflow.pem" ]; then
        knot_log_warn "Anchor Hub deskflow.pem not reachable, generating initial local TLS certificate..."
        openssl req -x509 -nodes -days 3650 -subj "/CN=Deskflow" -newkey rsa:2048 \
          -keyout "$tls_dir/deskflow.pem" -out "$tls_dir/deskflow.pem"
      fi
      chmod 600 "$tls_dir/deskflow.pem"
    fi
  fi

  local fp
  fp="$(openssl x509 -in "$tls_dir/deskflow.pem" -noout -fingerprint -sha256 | cut -d= -f2 | tr -d ':' | tr '[:upper:]' '[:lower:]')"
  echo "v2:sha256:$fp" > "$tls_dir/trusted-servers"
  echo "v2:sha256:$fp" > "$tls_dir/trusted-clients"
  chmod 600 "$tls_dir/trusted-servers" "$tls_dir/trusted-clients"

  # 6. Configure systemd user service & runner
  local systemd_dir="$home/.config/systemd/user"
  mkdir -p "$systemd_dir"

  # Ensure persistent KDE portal startup under graphical-session
  local kde_portal_unit="/usr/lib/systemd/user/plasma-xdg-desktop-portal-kde.service"
  if [ -f "$kde_portal_unit" ]; then
    local wants_dir="$home/.config/systemd/user/graphical-session.target.wants"
    mkdir -p "$wants_dir"
    ln -sf "$kde_portal_unit" "$wants_dir/plasma-xdg-desktop-portal-kde.service"
    if ! systemctl --user is-active --quiet plasma-xdg-desktop-portal-kde.service; then
      systemctl --user start plasma-xdg-desktop-portal-kde.service
    fi
  fi

  if [ -f "$KNOT_ROOT/core/shim/input_capture_shim.c" ] && { [ ! -f /usr/local/lib/knot/libinputcapture-persist.so ] || [ "$KNOT_ROOT/core/shim/input_capture_shim.c" -nt /usr/local/lib/knot/libinputcapture-persist.so ]; }; then
    sudo mkdir -p /usr/local/lib/knot
    if ! sudo gcc -Wall -Wextra -O2 -shared -fPIC \
      "$KNOT_ROOT/core/shim/input_capture_shim.c" \
      $(pkg-config --cflags --libs libportal) -ldl \
      -o /usr/local/lib/knot/libinputcapture-persist.so; then
      knot_log_warn "Failed to compile libinputcapture-persist.so"
    fi
  fi

  # 7. Configure KDE Plasma Global Shortcut for Host Cursor Lock
  local app_dir="$home/.local/share/applications"
  mkdir -p "$app_dir"
  cat << DESKTOP_EOF > "$app_dir/knot-kvm-lock.desktop"
[Desktop Entry]
Type=Application
Name=Knot KVM Lock Toggle
Comment=Toggle KVM cursor confinement to the desktop host
Exec=$KNOT_ROOT/bin/knot kvm lock-toggle
Icon=input-mouse
Terminal=false
Categories=Utility;
X-KDE-GlobalAccel-CommandShortcut=true
DESKTOP_EOF

  if command -v kwriteconfig6 >/dev/null; then
    kwriteconfig6 --file kglobalshortcutsrc --group "services" --group "knot-kvm-lock.desktop" --key "_launch" "ScrollLock,none,Knot KVM Lock Toggle"
  fi

  # 8. Deploy Unified Dual-Role Deskflow Runner (Anchor Server / Strand Client)
  knot_log_info "Deploying Unified Dual-Role Deskflow runner..."
  local user_bin="$home/.local/bin"
  mkdir -p "$user_bin"
  cat << 'RUNNER_EOF' > "$user_bin/knot-deskflow"
#!/usr/bin/env bash
set -euo pipefail

# Unified Knot Deskflow KVM Runner (Dual-Role: Anchor Server / Strand Client)
# Automatically adapts between Server and Client mode based on the active swarm.

ACTION="${1:-run}"

if [ "$ACTION" = "stop" ]; then
  if pgrep -f "deskflow-core" >/dev/null; then
    pkill -f "deskflow-core"
  fi
  if command -v systemctl >/dev/null && systemctl --user is-active --quiet knot-deskflow.service; then
    systemctl --user stop knot-deskflow.service
  fi
  exit 0
fi

if [ "$ACTION" = "reload" ] || [ "$ACTION" = "restart" ]; then
  if command -v systemctl >/dev/null; then
    systemctl --user restart knot-deskflow.service
  fi
  exit 0
fi

KNOT_CLI=""
if command -v knot >/dev/null; then
  KNOT_CLI="$(command -v knot)"
elif [ -x "/usr/local/bin/knot" ]; then
  KNOT_CLI="/usr/local/bin/knot"
elif [ -x "$HOME/.local/bin/knot" ]; then
  KNOT_CLI="$HOME/.local/bin/knot"
elif [ -x "$HOME/knot/bin/knot" ]; then
  KNOT_CLI="$HOME/knot/bin/knot"
fi

ACTIVE_SWARM="none"
RUN_DIR="${KNOT_RUNTIME_DIR:-/run/knot}"
if [ -r "$RUN_DIR/active_swarm" ]; then
  ACTIVE_SWARM="$(tr -d '[:space:]' < "$RUN_DIR/active_swarm")"
elif [ -r "$HOME/.local/state/knot/active_swarm" ]; then
  ACTIVE_SWARM="$(tr -d '[:space:]' < "$HOME/.local/state/knot/active_swarm")"
fi

if [ "$ACTIVE_SWARM" = "none" ] || [ -z "$ACTIVE_SWARM" ]; then
  echo "Active swarm is none (graceful standalone mode). Knot deskflow stopping."
  exit 0
fi

# Self-healing preflight: Ensure RemoteDesktop portal interface is available
has_rd() {
  if command -v gdbus >/dev/null; then
    local out=""
    if out="$(gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>&1)"; then
      if echo "$out" | grep -q 'interface org.freedesktop.portal.RemoteDesktop'; then
        return 0
      fi
    fi
    return 1
  else
    return 0
  fi
}

if ! has_rd; then
  if systemctl --user list-unit-files plasma-xdg-desktop-portal-kde.service 2>&1 | grep -q plasma-xdg-desktop-portal-kde; then
    mkdir -p "$HOME/.config/systemd/user/graphical-session.target.wants"
    ln -sf /usr/lib/systemd/user/plasma-xdg-desktop-portal-kde.service "$HOME/.config/systemd/user/graphical-session.target.wants/"
    systemctl --user daemon-reload
    systemctl --user start plasma-xdg-desktop-portal-kde.service
    systemctl --user restart xdg-desktop-portal.service
    for _ in {1..15}; do
      if has_rd; then break; fi
      sleep 0.2
    done
  fi
fi

MY_HOST=""
if command -v uname >/dev/null; then
  MY_HOST="$(uname -n)"
fi
if [ -z "$MY_HOST" ] && command -v hostname >/dev/null; then
  MY_HOST="$(hostname)"
fi

CONF_DIR="$HOME/.config/Deskflow"
mkdir -p "$CONF_DIR"

DESKFLOW_BIN="/usr/bin/deskflow-core"
if command -v deskflow-core >/dev/null; then
  DESKFLOW_BIN="$(command -v deskflow-core)"
fi

if [ ! -x "$DESKFLOW_BIN" ]; then
  echo "deskflow-core executable not found at $DESKFLOW_BIN" >&2
  exit 1
fi

ANCHOR_TARGET="desktop"
ANCHOR_HOST="desktop.local"
SWARM_CFG=""
if [ -r "/etc/knot/swarms.d/${ACTIVE_SWARM}.conf" ]; then
  SWARM_CFG="/etc/knot/swarms.d/${ACTIVE_SWARM}.conf"
elif [ -r "$HOME/.config/knot/swarms/${ACTIVE_SWARM}.conf" ]; then
  SWARM_CFG="$HOME/.config/knot/swarms/${ACTIVE_SWARM}.conf"
elif [ -r "$HOME/.config/knot/swarms/${ACTIVE_SWARM}/swarm.conf" ]; then
  SWARM_CFG="$HOME/.config/knot/swarms/${ACTIVE_SWARM}/swarm.conf"
fi

if [ -n "$SWARM_CFG" ] && [ -r "$SWARM_CFG" ]; then
  ANCHOR_ID_CFG="$(awk -F= '/^ANCHOR_ID=/ {print $2}' "$SWARM_CFG" | tr -d '"'\'' ')"
  ANCHOR_HOST_CFG="$(awk -F= '/^ANCHOR_HOST=/ {print $2}' "$SWARM_CFG" | tr -d '"'\'' ')"
  [ -n "$ANCHOR_ID_CFG" ] && ANCHOR_TARGET="$ANCHOR_ID_CFG"
  [ -n "$ANCHOR_HOST_CFG" ] && ANCHOR_HOST="$ANCHOR_HOST_CFG"
fi

IS_ANCHOR=0
if [ "$MY_HOST" = "$ANCHOR_HOST" ] || [ "$MY_HOST" = "$ANCHOR_TARGET" ]; then
  IS_ANCHOR=1
fi

NODES_DIR=""
if [ -d "$HOME/.config/knot/swarms/${ACTIVE_SWARM}/nodes" ]; then
  NODES_DIR="$HOME/.config/knot/swarms/${ACTIVE_SWARM}/nodes"
elif [ -d "/etc/knot/swarms.d/${ACTIVE_SWARM}/nodes" ]; then
  NODES_DIR="/etc/knot/swarms.d/${ACTIVE_SWARM}/nodes"
fi

if [ "$IS_ANCHOR" -eq 1 ]; then
  # ==========================================
  # ANCHOR WORKSTATION (SERVER MODE)
  # ==========================================
  echo "Node $MY_HOST is ANCHOR in active swarm ($ACTIVE_SWARM). Launching Deskflow Server..."

  cat << CONF_EOF > "$CONF_DIR/Deskflow.conf"
[core]
computerName=${MY_HOST:-localhost}

[server]
externalConfig=true
externalConfigFile=$CONF_DIR/deskflow-server.conf
CONF_EOF

  SHIM_SO="/usr/local/lib/knot/libinputcapture-persist.so"
  if [ -f "$SHIM_SO" ]; then
    export LD_PRELOAD="$SHIM_SO"
  fi

  exec "$DESKFLOW_BIN" server --new-instance -s "$CONF_DIR/Deskflow.conf"
else
  # ==========================================
  # STRAND WORKSTATION (CLIENT MODE)
  # ==========================================
  echo "Node $MY_HOST is STRAND in active swarm ($ACTIVE_SWARM). Launching Deskflow Client targeting $ANCHOR_TARGET ($ANCHOR_HOST)..."

  RESOLVED_IP=""
  if [ -n "$KNOT_CLI" ]; then
    if resolved_candidate="$("$KNOT_CLI" resolve "$ANCHOR_TARGET" 24800)"; then
      RESOLVED_IP="$resolved_candidate"
    elif [ "$ANCHOR_HOST" != "$ANCHOR_TARGET" ]; then
      if host_candidate="$("$KNOT_CLI" resolve "$ANCHOR_HOST" 24800)"; then
        RESOLVED_IP="$host_candidate"
      fi
    fi
  fi

  if [ -z "$RESOLVED_IP" ] && [ -n "$ANCHOR_HOST" ]; then
    RESOLVED_IP="$ANCHOR_HOST"
  fi

  if [ -z "$RESOLVED_IP" ]; then
    echo "Could not resolve active Anchor ($ANCHOR_TARGET / $ANCHOR_HOST) IP on port 24800" >&2
    exit 1
  fi

  CLIENT_NAME="$MY_HOST"
  if [ -n "$NODES_DIR" ]; then
    for mf in "$NODES_DIR/"*.json; do
      [ -r "$mf" ] || continue
      m_host="$(awk -F'"' '/"hostname":/ {print $4}' "$mf")"
      m_id="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
      m_user="$(awk -F'"' '/"user":/ {print $4}' "$mf")"
      if [ "$m_host" = "$MY_HOST" ] || [ "$m_id" = "$MY_HOST" ]; then
        CLIENT_NAME="${m_host:-$MY_HOST}"
        break
      fi
      if [ "$m_user" = "${USER:-}" ] && [ "$m_id" != "$ANCHOR_TARGET" ]; then
        CLIENT_NAME="${m_host:-$m_id}"
      fi
    done
  fi

  cat << CONF_EOF > "$CONF_DIR/Deskflow.conf"
[core]
computerName=${CLIENT_NAME:-localhost}

[client]
remoteHost=$RESOLVED_IP
CONF_EOF

  exec "$DESKFLOW_BIN" client --new-instance -s "$CONF_DIR/Deskflow.conf"
fi
RUNNER_EOF
  chmod 755 "$user_bin/knot-deskflow"
  ln -sf "$user_bin/knot-deskflow" "$user_bin/knot-deskflow-client"
  if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
    sudo cp -f "$user_bin/knot-deskflow" /usr/local/bin/knot-deskflow 2>/dev/null || true
    sudo ln -sf /usr/local/bin/knot-deskflow /usr/local/bin/knot-deskflow-client 2>/dev/null || true
  fi

  knot_log_info "Deploying Unified Knot Deskflow systemd service..."
  cat << SERVICE_EOF > "$systemd_dir/knot-deskflow.service"
[Unit]
Description=Knot Dynamic Deskflow KVM Service (Anchor Server / Strand Client)
PartOf=graphical-session.target
After=graphical-session.target xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service
Wants=xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service
Requisite=graphical-session.target

[Service]
Type=simple
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_CURRENT_DESKTOP=KDE
Environment=XDG_DESKTOP_PORTAL_APP_ID=org.deskflow.deskflow
ExecStart=%h/.local/bin/knot-deskflow
Restart=on-failure
RestartSec=10

[Install]
WantedBy=graphical-session.target
SERVICE_EOF

  systemctl --user daemon-reload
  systemctl --user enable knot-deskflow.service
  systemctl --user restart knot-deskflow.service
  knot_log_ok "Knot Deskflow service deployed and active on $my_host."

  autounlock_configure
}
