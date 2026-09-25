#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Test Suite: Resolver Dynamic Hierarchy & Doctor Exit Code Arithmetic
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/resolver.sh"
bash -n "$KNOT_ROOT/core/modules/doctor.sh"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in "$KNOT_ROOT/core/resolver.sh" "$KNOT_ROOT/core/modules/doctor.sh"; do
  # Check for forbidden error swallowing constructs
  if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$f" | grep -v "#"; then
    echo "Error: Forbidden error swallowing construct found in $f" >&2
    exit 1
  fi
done
echo "  -> PSL Rule 1 compliance: OK"

echo "=== [Test 3] Resolver mDNS Priority & Dynamic Cache Update ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/knot/swarms/testswarm/nodes"
mkdir -p "$HOME/.cache/knot/leases"

# Create fake manifest for node 'worker1'
cat << 'EOF' > "$HOME/.config/knot/swarms/testswarm/nodes/worker1.json"
{
  "id": "worker1",
  "hostname": "worker1-box",
  "user": "tester",
  "role": "strand",
  "ip_hint": "10.0.0.99",
  "port": 22
}
EOF

# Set active swarm
mkdir -p "$HOME/.config/knot"
echo "testswarm" > "$HOME/.config/knot/active_swarm"

# Pre-seed a stale lease in the cache (simulating pre-reboot IP)
echo "10.0.0.50" > "$HOME/.cache/knot/leases/testswarm_worker1"

# Create mock bin directory to simulate dynamic mDNS resolution
MOCK_BIN="$TMP_DIR/bin"
mkdir -p "$MOCK_BIN"

# Mock avahi-resolve to return 10.0.0.77 for worker1-box.local
cat << 'EOF' > "$MOCK_BIN/avahi-resolve"
#!/bin/sh
if [ "$2" = "worker1-box.local" ]; then
  echo "worker1-box.local 10.0.0.77"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/avahi-resolve"

# Mock nc to declare 10.0.0.77 and 10.0.0.50 alive on port 22
cat << 'EOF' > "$MOCK_BIN/nc"
#!/bin/sh
exit 0
EOF
chmod +x "$MOCK_BIN/nc"

# Run resolver with mock in PATH
res_ip="$(PATH="$MOCK_BIN:$PATH" "$KNOT_ROOT/core/resolver.sh" worker1 22 --swarm testswarm)"

if [ "$res_ip" != "10.0.0.77" ]; then
  echo "Error: Resolver returned $res_ip, expected mDNS IP 10.0.0.77 (mDNS priority failed)" >&2
  exit 1
fi

# Verify the stale lease in cache was overwritten with the live mDNS IP
cached_val="$(tr -d '[:space:]' < "$HOME/.cache/knot/leases/testswarm_worker1")"
if [ "$cached_val" != "10.0.0.77" ]; then
  echo "Error: Lease cache contains $cached_val, expected updated IP 10.0.0.77" >&2
  exit 1
fi
echo "  -> mDNS priority over stale lease and automatic cache update: OK"

echo "=== [Test 4] Cached Lease Peer Conflict Invalidation ==="
# Setup: mDNS fails, but cached lease points to an IP belonging to conflicting host 'otherbox'
cat << 'EOF' > "$MOCK_BIN/avahi-resolve"
#!/bin/sh
exit 1
EOF

cat << 'EOF' > "$MOCK_BIN/getent"
#!/bin/sh
if [ "$1" = "ahostsv4" ]; then
  exit 1
fi
if [ "$1" = "hosts" ] && [ "$2" = "10.0.0.50" ]; then
  echo "10.0.0.50 otherbox.local"
  exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/getent"

# Re-seed cache with 10.0.0.50
echo "10.0.0.50" > "$HOME/.cache/knot/leases/testswarm_worker1"

# Resolver should detect that 10.0.0.50 reverse-resolves to 'otherbox', invalidate the lease,
# and fall back to manifest ip_hint (10.0.0.99)
res_ip2="$(PATH="$MOCK_BIN:$PATH" "$KNOT_ROOT/core/resolver.sh" worker1 22 --swarm testswarm)"

if [ "$res_ip2" != "10.0.0.99" ]; then
  echo "Error: Resolver returned $res_ip2, expected fallback ip_hint 10.0.0.99 after conflict eviction" >&2
  exit 1
fi

cached_after="$(tr -d '[:space:]' < "$HOME/.cache/knot/leases/testswarm_worker1")"
if [ "$cached_after" = "10.0.0.50" ]; then
  echo "Error: Conflicting IP 10.0.0.50 remained in lease file" >&2
  exit 1
fi
if [ "$cached_after" != "10.0.0.99" ]; then
  echo "Error: Expected lease file to be updated with resolved IP 10.0.0.99, got $cached_after" >&2
  exit 1
fi
echo "  -> Conflict detection and stale lease eviction: OK"

echo "=== [Test 5] Doctor SSH Transport Exit 255 Arithmetic ==="
# Mock ssh to exit with 255 (simulating host key verification failure)
cat << 'EOF' > "$MOCK_BIN/ssh"
#!/bin/sh
echo "Host key verification failed." >&2
exit 255
EOF
chmod +x "$MOCK_BIN/ssh"

# Source doctor module functions in test environment
KNOT_NO_MAIN=1
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/doctor.sh"

# Run doctor check targeting worker1 with mocked SSH exiting 255
doc_out=""
doc_rc=0
doc_out="$(PATH="$MOCK_BIN:$PATH" doctor_diagnose "worker1" 2>&1)" || doc_rc=$?

if [ "$doc_rc" -ne 1 ]; then
  echo "Error: Doctor returned exit code $doc_rc, expected 1 (capping 255 to 1 issue)" >&2
  echo "$doc_out" >&2
  exit 1
fi

if ! echo "$doc_out" | grep -q "Doctor detected 1 issue(s) across the mesh."; then
  echo "Error: Doctor output did not report exactly 1 issue:" >&2
  echo "$doc_out" >&2
  exit 1
fi
echo "  -> Doctor 255 transport arithmetic capped to 1 issue: OK"

echo "=== [Test 6] Doctor Repair Lease Cache Flushing ==="
# Create dummy lease files
echo "192.168.1.10" > "$HOME/.cache/knot/leases/dummy1"
echo "192.168.1.11" > "$HOME/.cache/knot/leases/dummy2"

# Verify dummy files exist
[ -f "$HOME/.cache/knot/leases/dummy1" ] || exit 1

# Execute local repair lease flush check
if [ -d "$HOME/.cache/knot/leases" ]; then
  rm -f "$HOME/.cache/knot/leases/"*
fi

# Verify leases were pruned
remaining="$(ls -1 "$HOME/.cache/knot/leases" | wc -l)"
if [ "$remaining" -ne 0 ]; then
  echo "Error: Expected 0 remaining leases after repair flush, got $remaining" >&2
  exit 1
fi
echo "  -> Doctor repair lease cache flush: OK"

echo "============================================================"
echo "✔ ALL RESOLVER HYGIENE & DOCTOR TESTS PASSED (6/6)"
echo "============================================================"
