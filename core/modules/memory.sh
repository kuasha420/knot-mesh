#!/usr/bin/env bash
# Knot Swarm Decentralized Memory Palace & Vault module

cmd_memory() {
  exec python3 "$KNOT_ROOT/core/memory/palace.py" "$@"
}
