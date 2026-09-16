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
  elif [ -d "$KNOT_ROOT/registry/nodes" ]; then
    nodes_dir="$KNOT_ROOT/registry/nodes"
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
  deskflow_compile_server_config "$@"
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
  if [ -z "$anchor_host" ] && [ -d "$KNOT_ROOT/registry/nodes" ]; then
    for manifest in "$KNOT_ROOT/registry/nodes/"*.json; do
      [ -e "$manifest" ] || continue
      if grep -q '"id":[[:space:]]*"desktop"' "$manifest"; then
        anchor_host="$(grep -o '"hostname":[[:space:]]*"[^"]*"' "$manifest" | cut -d'"' -f4)"
      fi
    done
  fi

  # 0. Ensure Deskflow package is installed
  if ! command -v deskflow-core >/dev/null; then
    knot_log_info "Installing deskflow package..."
    sudo pacman -S --needed --noconfirm deskflow
  fi

  # 1. Compile server configuration layout (Screens, Links, Aliases, Options)
  deskflow_write_server_conf "unlocked"

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
      scp -o BatchMode=yes -o ConnectTimeout=5 "desktop:.config/Deskflow/tls/deskflow.pem" "$tls_dir/deskflow.pem"
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

  if [ "$my_host" = "$anchor_host" ]; then
    # Compile and install the InputCapture persistence shim if not already present
    if [ -f "$KNOT_ROOT/core/shim/input_capture_shim.c" ] && [ ! -f /usr/local/lib/knot/libinputcapture-persist.so ]; then
      sudo mkdir -p /usr/local/lib/knot
      if ! sudo gcc -Wall -Wextra -O2 -shared -fPIC \
        "$KNOT_ROOT/core/shim/input_capture_shim.c" \
        $(pkg-config --cflags --libs libportal) -ldl \
        -o /usr/local/lib/knot/libinputcapture-persist.so; then
        knot_log_err "Failed to compile libinputcapture-persist.so"
        return 1
      fi
    fi

    # Server INI settings
    cat << INI_EOF > "$cfg_dir/Deskflow.conf"
[core]
computerName=$my_host
INI_EOF

    knot_log_info "Deploying Deskflow SERVER service on Anchor ($my_host)..."
    cat << SERVICE_EOF > "$systemd_dir/knot-deskflow.service"
[Unit]
Description=Knot Deskflow Server (Anchor KVM)
PartOf=graphical-session.target
After=graphical-session.target
Requisite=graphical-session.target

[Service]
Type=simple
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_CURRENT_DESKTOP=KDE
Environment=LD_PRELOAD=/usr/local/lib/knot/libinputcapture-persist.so
ExecStart=/usr/bin/deskflow-core server --new-instance -s %h/.config/Deskflow/Deskflow.conf
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
SERVICE_EOF

    # Configure KDE Plasma Global Shortcut for Host Cursor Lock
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
  else
    knot_log_info "Deploying Dynamic Deskflow CLIENT runner on Strand ($my_host)..."
    cat << 'RUNNER_EOF' | sudo tee /usr/local/bin/knot-deskflow-client >/dev/null
#!/usr/bin/env bash
set -euo pipefail

# Dynamic Knot Deskflow Client Runner
# Connects to the Anchor workstation of the currently active swarm.

ACTION="${1:-run}"

if [ "$ACTION" = "stop" ]; then
  if pgrep -f "deskflow-core client" >/dev/null; then
    pkill -f "deskflow-core client"
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

if [ -z "$KNOT_CLI" ]; then
  echo "Error: knot CLI executable not found in PATH or standard locations" >&2
  exit 1
fi

ACTIVE_SWARM="none"
if [ -r "/run/knot/active_swarm" ]; then
  ACTIVE_SWARM="$(tr -d '[:space:]' < /run/knot/active_swarm)"
elif [ -r "$HOME/.local/state/knot/active_swarm" ]; then
  ACTIVE_SWARM="$(tr -d '[:space:]' < "$HOME/.local/state/knot/active_swarm")"
fi

if [ "$ACTIVE_SWARM" = "none" ] || [ -z "$ACTIVE_SWARM" ]; then
  echo "Active swarm is none (graceful standalone mode). Knot deskflow client stopping."
  exit 0
fi

ANCHOR_TARGET="desktop"
if [ -r "/etc/knot/swarms.d/${ACTIVE_SWARM}.conf" ]; then
  ANCHOR_CFG="$(awk -F= '/^ANCHOR_ID=/ {print $2}' "/etc/knot/swarms.d/${ACTIVE_SWARM}.conf" | tr -d '"')"
  if [ -n "$ANCHOR_CFG" ]; then
    ANCHOR_TARGET="$ANCHOR_CFG"
  fi
elif [ -r "$HOME/.config/knot/swarms/${ACTIVE_SWARM}/swarm.conf" ]; then
  ANCHOR_CFG="$(awk -F= '/^ANCHOR_ID=/ {print $2}' "$HOME/.config/knot/swarms/${ACTIVE_SWARM}/swarm.conf" | tr -d '"')"
  if [ -n "$ANCHOR_CFG" ]; then
    ANCHOR_TARGET="$ANCHOR_CFG"
  fi
fi

RESOLVED_IP="$("$KNOT_CLI" resolve "$ANCHOR_TARGET" 24800)"
if [ -z "$RESOLVED_IP" ]; then
  echo "Could not resolve active Anchor ($ANCHOR_TARGET) IP on port 24800" >&2
  exit 1
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

cat << CONF_EOF > "$CONF_DIR/Deskflow.conf"
[core]
computerName=${MY_HOST:-localhost}

[client]
remoteHost=$RESOLVED_IP
CONF_EOF

DESKFLOW_BIN="/usr/bin/deskflow-core"
if command -v deskflow-core >/dev/null; then
  DESKFLOW_BIN="$(command -v deskflow-core)"
fi

if [ ! -x "$DESKFLOW_BIN" ]; then
  echo "deskflow-core executable not found at $DESKFLOW_BIN" >&2
  exit 1
fi

exec "$DESKFLOW_BIN" client --new-instance -s "$CONF_DIR/Deskflow.conf"
RUNNER_EOF
    sudo chmod 755 /usr/local/bin/knot-deskflow-client

    knot_log_info "Deploying Dynamic Deskflow CLIENT service on Strand ($my_host)..."
    cat << SERVICE_EOF > "$systemd_dir/knot-deskflow.service"
[Unit]
Description=Knot Dynamic Deskflow Client (Strand KVM)
PartOf=graphical-session.target
After=graphical-session.target xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service
Wants=xdg-desktop-portal.service plasma-xdg-desktop-portal-kde.service
Requisite=graphical-session.target

[Service]
Type=simple
Environment=WAYLAND_DISPLAY=wayland-0
Environment=XDG_CURRENT_DESKTOP=KDE
Environment=XDG_DESKTOP_PORTAL_APP_ID=org.deskflow.deskflow
ExecStart=/usr/local/bin/knot-deskflow-client
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical-session.target
SERVICE_EOF
  fi

  systemctl --user daemon-reload
  systemctl --user enable knot-deskflow.service
  systemctl --user restart knot-deskflow.service
  knot_log_ok "Knot Deskflow service deployed and active on $my_host."

  autounlock_configure
}
