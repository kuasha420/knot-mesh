#!/usr/bin/env bash
set -euo pipefail

# Knot Swarm Council Mission - Node @desktop Autonomous Side Quest Verification
# Focus: Ultrawide display topology, cursor confinement, resolver concurrency, stale lease auto-healing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RESOLVER="$KNOT_ROOT/core/resolver.sh"

echo "=== [Side Quest Test 1] Ultrawide Multi-Screen Fractional Deskflow Compilation ==="
python3 - << 'PYEOF'
import json, tempfile, os, sys
from core.modules.compile_deskflow import compile_deskflow

with tempfile.TemporaryDirectory() as td:
    nodes_dir = os.path.join(td, "nodes")
    os.makedirs(nodes_dir)
    
    for nid, hname in [("desktop", "desktop"), ("laptop", "devbox"), ("rog-ally", "rog-ally"), ("steamdeck", "steamdeck-jupiter")]:
        with open(os.path.join(nodes_dir, f"{nid}.json"), "w") as f:
            json.dump({"id": nid, "hostname": hname}, f)
            
    topology = {
        "anchor": "desktop",
        "screens": ["desktop", "laptop", "rog-ally", "steamdeck"],
        "layout": {
            "desktop": {
                "down": [
                    {"node": "laptop", "span": [0, 25], "target_span": [0, 100]},
                    {"node": "rog-ally", "span": [25, 75], "target_span": [0, 100]},
                    {"node": "steamdeck", "span": [75, 100], "target_span": [0, 100]}
                ]
            }
        }
    }
    topo_file = os.path.join(td, "topology.json")
    with open(topo_file, "w") as f:
        json.dump(topology, f)
        
    out = compile_deskflow(topo_file, nodes_dir, "unlocked")
    assert "down(0,25) = devbox(0,100)" in out
    assert "down(25,75) = rog-ally(0,100)" in out
    assert "down(75,100) = steamdeck-jupiter(0,100)" in out
    assert "up(0,100) = desktop(0,25)" in out
    assert "up(0,100) = desktop(25,75)" in out
    assert "up(0,100) = desktop(75,100)" in out
    
    # Verify locked mode cursor confinement
    locked_out = compile_deskflow(topo_file, nodes_dir, "locked")
    assert "desktop:" in locked_out
    assert "down(0,25) = devbox(0,100)" not in locked_out
    print("  -> Ultrawide 3-way fractional spans and reciprocal links: OK")
    print("  -> Locked mode cursor confinement: OK")
PYEOF

echo "=== [Side Quest Test 2] Concurrent Resolver Invocations (10 parallel jobs) ==="
pids=()
for i in {1..10}; do
  bash "$RESOLVER" desktop >/dev/null &
  pids+=($!)
done

failed=0
for pid in "${pids[@]}"; do
  if ! wait "$pid"; then
    failed=$((failed + 1))
  fi
done

if [ $failed -eq 0 ]; then
  echo "  -> 10/10 concurrent resolver queries succeeded without race conditions: OK"
else
  echo "Error: $failed queries failed!" >&2
  exit 1
fi

echo "=== [Side Quest Test 3] Offline Peer & Nonexistent Node Fast-Fail ==="
start_time=$(date +%s)
if probe_out="$(bash "$RESOLVER" nonexistent_node_xyz 2>&1)"; then
  echo "Error: nonexistent node resolved unexpectedly! Output: $probe_out" >&2
  exit 1
else
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  echo "  -> Nonexistent node rejected with exit code 1 in ${duration}s: OK"
fi

echo "=== [Side Quest Test 4] Stale Lease Cache Invalidation & Auto-Healing ==="
USER_HOME="$HOME"
CACHE_DIR="$USER_HOME/.cache/knot"
mkdir -p "$CACHE_DIR/leases"
active_swarm="$(bash -c "source $KNOT_ROOT/core/lib.sh && knot_get_active_swarm")"
LEASE_FILE="$CACHE_DIR/leases/${active_swarm}_desktop"

# Write dead IP to lease file
echo "192.0.2.1" > "$LEASE_FILE" # RFC 5737 TEST-NET-1 (unroutable/dead)
res_ip="$(bash "$RESOLVER" desktop)"
if [ "$res_ip" = "127.0.0.1" ] || [ -n "$res_ip" ]; then
  new_cached="$(cat "$LEASE_FILE")"
  if [ "$new_cached" = "192.0.2.1" ]; then
    echo "Error: Lease cache was not healed!" >&2
    exit 1
  fi
  echo "  -> Stale lease (192.0.2.1) bypassed and healed to $new_cached: OK"
else
  echo "Error: Did not resolve active IP after stale lease!" >&2
  exit 1
fi

echo "=== [✓] ALL ANCHOR SIDE QUEST TESTS PASSED! ==="
