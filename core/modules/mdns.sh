#!/usr/bin/env bash
set -euo pipefail

# Knot mDNS / Avahi Configuration Module

KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

mdns_configure() {
  knot_log_info "Configuring mDNS / Avahi for zero-config mesh discovery..."

  # 1. Enable publish-workstation in /etc/avahi/avahi-daemon.conf
  if [ -f /etc/avahi/avahi-daemon.conf ]; then
    if ! grep -q "^publish-workstation=yes" /etc/avahi/avahi-daemon.conf; then
      sudo sed -i 's/^#*publish-workstation=.*/publish-workstation=yes/' /etc/avahi/avahi-daemon.conf
      if ! grep -q "^publish-workstation=yes" /etc/avahi/avahi-daemon.conf; then
        # If line wasn't present to replace, add under [publish]
        sudo sed -i '/\[publish\]/a publish-workstation=yes' /etc/avahi/avahi-daemon.conf
      fi
      knot_log_ok "Enabled publish-workstation in avahi-daemon.conf"
    fi
  fi

  # 2. Register Knot mDNS service
  sudo mkdir -p /etc/avahi/services
  cat << 'XML_EOF' | sudo tee /etc/avahi/services/knot.service >/dev/null
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_knot._tcp</type>
    <port>22</port>
  </service>
</service-group>
XML_EOF

  # 3. Ensure nsswitch.conf has mdns_minimal
  if [ -f /etc/nsswitch.conf ]; then
    if ! grep '^hosts:' /etc/nsswitch.conf | grep -q 'mdns_minimal'; then
      knot_log_info "Adding mdns_minimal to /etc/nsswitch.conf..."
      sudo sed -i 's/^hosts:[[:space:]]*/hosts: mymachines mdns_minimal [NOTFOUND=return] /' /etc/nsswitch.conf
      knot_log_ok "Updated /etc/nsswitch.conf for .local resolution"
    fi
  fi

  # 4. Restart avahi-daemon if running
  if systemctl is-active --quiet avahi-daemon; then
    sudo systemctl restart avahi-daemon
    knot_log_ok "avahi-daemon restarted."
  fi
}
