#!/usr/bin/env bash
set -euo pipefail

# Knot Firewall Manager - Multi-Engine (UFW / firewalld / raw)

KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

firewall_configure() {
  local subnet
  subnet="$(knot_detect_subnet)"
  local engines
  engines="$(knot_detect_firewalls)"
  local ssh_port
  ssh_port="$(knot_detect_sshd_port)"

  knot_log_info "Configuring firewall for subnet $subnet and SSH port $ssh_port (Detected engines: $engines)..."

  # Engine 1: UFW
  if [[ "$engines" =~ "ufw" ]]; then
    knot_log_info "Applying UFW scoped rules at top priority..."
    if ! sudo ufw status | grep -q "knot-ssh"; then
      sudo ufw insert 1 allow from "$subnet" to any port "$ssh_port" proto tcp comment 'knot-ssh'
      if [ "$ssh_port" != "22" ]; then
        sudo ufw insert 2 allow from "$subnet" to any port 22 proto tcp comment 'knot-ssh-std'
      fi
      sudo ufw insert 3 allow from "$subnet" to any port 5353 proto udp comment 'knot-mdns'
      sudo ufw insert 4 allow from "$subnet" to any port 1714:1764 proto udp comment 'knot-kde-udp'
      sudo ufw insert 5 allow from "$subnet" to any port 1714:1764 proto tcp comment 'knot-kde-tcp'
      sudo ufw insert 6 allow from "$subnet" to any port 24800 proto tcp comment 'knot-kvm'
      sudo ufw insert 7 allow from "$subnet" to any port 4242 proto tcp comment 'knot-hub'
      sudo ufw reload >/dev/null
      knot_log_ok "UFW rules successfully inserted ahead of deny rules."
    else
      # Ensure current port is allowed
      sudo ufw insert 1 allow from "$subnet" to any port "$ssh_port" proto tcp comment 'knot-ssh-active' >/dev/null
      knot_log_ok "UFW knot rules verified."
    fi
  fi

  # Engine 2: firewalld
  if [[ "$engines" =~ "firewalld" ]]; then
    knot_log_info "Applying firewalld scoped rules..."
    sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$subnet\" port port=\"$ssh_port\" protocol=\"tcp\" accept" >/dev/null
    sudo firewall-cmd --permanent --zone=public --add-rich-rule="rule family=\"ipv4\" source address=\"$subnet\" service name=\"ssh\" accept" >/dev/null
    sudo firewall-cmd --permanent --zone=public --add-service=kdeconnect >/dev/null
    sudo firewall-cmd --permanent --zone=public --add-service=mdns >/dev/null
    sudo firewall-cmd --permanent --zone=public --add-port=4242/tcp >/dev/null
    sudo firewall-cmd --permanent --zone=public --add-port=24800/tcp >/dev/null
    sudo firewall-cmd --reload >/dev/null
    knot_log_ok "firewalld rules successfully applied."
  fi

  if [[ "$engines" == "none" ]]; then
    knot_log_warn "No active high-level firewall daemon (UFW/firewalld) detected. Ensure local ports are unblocked."
  fi
}
