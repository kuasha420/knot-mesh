#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Wayland Virtual Monitor Fabric (krdp / krdc / Wayland display decoupling)
# Extracted from core/modules/kdeconnect.sh for modular architecture

if [ -n "${_KNOT_VMON_LOADED:-}" ]; then
  return 0
fi
_KNOT_VMON_LOADED=1

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck source=../../core/lib.sh
source "$KNOT_ROOT/core/lib.sh"
if [ -f "$KNOT_ROOT/core/modules/kdeconnect.sh" ]; then
  # shellcheck source=../../core/modules/kdeconnect.sh
  source "$KNOT_ROOT/core/modules/kdeconnect.sh"
fi

vmon_is_active() {
  # 1. Check local state flags (sender node)
  local home
  home="$(knot_detect_user_home)"
  local f=""
  for f in /run/knot/vmon_muted_deskflow_* "$home/.local/state/knot/vmon_muted_deskflow_"*; do
    if [ -f "$f" ]; then
      return 0
    fi
  done

  # 2. Check keepalive pid file or process (receiver node)
  local uid
  uid="$(id -u)"
  local keepalive_pid="/run/user/$uid/knot-vmon-keepalive.pid"
  if [ -f "$keepalive_pid" ]; then
    local kpid=""
    if [ -r "$keepalive_pid" ]; then
      kpid="$(cat "$keepalive_pid")"
    fi
    if [ -n "$kpid" ]; then
      local k_chk="" k_rc=0
      k_chk="$(kill -0 "$kpid" 2>&1)" || k_rc=$?
      if [ $k_rc -eq 0 ]; then
        return 0
      fi
    fi
  fi

  # 3. Check for active streaming processes (krdpserver on sender, krdc/keepalive on receiver)
  local p_out="" p_rc=0
  p_out="$(pgrep -f "krdpserver" 2>&1)" || p_rc=$?
  if [ $p_rc -eq 0 ]; then
    return 0
  fi
  p_out="$(pgrep -f "krdc.*rdp://" 2>&1)" || p_rc=$?
  if [ $p_rc -eq 0 ]; then
    return 0
  fi
  p_out="$(pgrep -f "knot-vmon-keepalive" 2>&1)" || p_rc=$?
  if [ $p_rc -eq 0 ]; then
    return 0
  fi

  # 4. Check DBus virtualmonitor active property
  local qdbus_cmd=""
  if qdbus_cmd="$(kdeconnect_get_qdbus_cmd)"; then
    local dev_list="" dev_rc=0
    dev_list="$("$qdbus_cmd" org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon.devices false true 2>&1)" || dev_rc=$?
    if [ $dev_rc -eq 0 ] && [ -n "$dev_list" ]; then
      local dev=""
      for dev in $dev_list; do
        local act="" act_rc=0
        act="$("$qdbus_cmd" org.kde.kdeconnect "/modules/kdeconnect/devices/$dev/virtualmonitor" org.kde.kdeconnect.device.virtualmonitor.active 2>&1)" || act_rc=$?
        if [ $act_rc -eq 0 ] && [ "$act" = "true" ]; then
          return 0
        fi
      done
    fi
  fi

  return 1
}

vmon_status() {
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

vmon_ensure_host_certs() {
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

  # Ensure krdpserver embedded cursor patch is present for Wayland virtual display
  if [ -x "$KNOT_ROOT/bin/knot-vmon-patch-krdp" ]; then
    local p_out="" p_rc=0
    p_out="$("$KNOT_ROOT/bin/knot-vmon-patch-krdp" 2>&1)" || p_rc=$?
    if [ $p_rc -ne 0 ]; then
      knot_log_warn "Notice: Checking krdp embedded cursor patch returned non-zero ($p_rc): $p_out"
    fi
  fi
  return 0
}

vmon_seed_client_trust() {
  local target_node="${1:-}"
  local target_port="${2:-22}"
  local target_user="${3:-}"
  local home
  home="$(knot_detect_user_home)"
  local cert_file="$home/.local/share/krdpserver/krdp.crt"

  if [ ! -f "$cert_file" ]; then
    vmon_ensure_host_certs
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

vmon_reconcile_topology_and_scale() {
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
except Exception as _err:
    sys.stderr.write(f"Notice: [vmon] Topology calculation exception: {_err}\n")
    print("left")
' "$topo_file" "$target_node")" || d_rc=$?
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

vmon_reset_primary_display() {
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

vmon_reconcile_plasma_panel() {
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

vmon_start() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    knot_log_err "Usage: knot display vmon start <node_id|device_id>"
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
  vmon_ensure_host_certs

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
    vmon_seed_client_trust "$target_node" "$target_port" "$target_user"
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
        "if pgrep -x krdc >/dev/null; then pkill -x krdc; fi; mkdir -p ~/.local/state/knot && nohup python3 ~/.local/bin/knot-vmon-keepalive </dev/null > ~/.local/state/knot/vmon-keepalive.log 2>&1 &" || k_rc=$?
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
    vmon_reconcile_topology_and_scale "$target_node"

    # 10. Reconcile persistent Plasma panel
    vmon_reconcile_plasma_panel

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

vmon_stop() {
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
  vmon_reset_primary_display

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
        "pid_file=\"/run/user/\$(id -u)/knot-vmon-keepalive.pid\"; if [ -f \"\$pid_file\" ]; then k_pid=\$(cat \"\$pid_file\"); if [ -n \"\$k_pid\" ] && [ -d \"/proc/\$k_pid\" ]; then kill \"\$k_pid\"; fi; rm -f \"\$pid_file\"; fi; if pgrep -x krdc >/dev/null; then pkill -x krdc; fi" || k_rc=$?
    fi
  fi

  if [ $stopped_any -eq 0 ]; then
    knot_log_info "No active Virtual Monitor streams were found running."
  fi
  return 0
}

# Backwards compatibility aliases
kdeconnect_vmon_is_active() { vmon_is_active "$@"; }
kdeconnect_vmon_status() { vmon_status "$@"; }
kdeconnect_vmon_ensure_host_certs() { vmon_ensure_host_certs "$@"; }
kdeconnect_vmon_seed_client_trust() { vmon_seed_client_trust "$@"; }
kdeconnect_vmon_reconcile_topology_and_scale() { vmon_reconcile_topology_and_scale "$@"; }
kdeconnect_vmon_reset_primary_display() { vmon_reset_primary_display "$@"; }
kdeconnect_vmon_reconcile_plasma_panel() { vmon_reconcile_plasma_panel "$@"; }
kdeconnect_vmon_start() { vmon_start "$@"; }
kdeconnect_vmon_stop() { vmon_stop "$@"; }
