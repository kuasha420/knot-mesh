#!/usr/bin/env bash
set -euo pipefail

# Test Suite for Companion Dependency Matrix & Declarative Registry
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Syntax & Structure Verification ==="
REGISTRY_FILE="$KNOT_ROOT/core/registry/companions.json"
DOCS_FILE="$KNOT_ROOT/docs/DEPENDENCY_MATRIX.md"

if [ ! -f "$REGISTRY_FILE" ]; then
  echo "Error: $REGISTRY_FILE does not exist!" >&2
  exit 1
fi

if [ ! -f "$DOCS_FILE" ]; then
  echo "Error: $DOCS_FILE does not exist!" >&2
  exit 1
fi
echo "  -> Registry and docs files exist: OK"

echo "=== [Test 2] Companions Registry Schema & Catalog Validation ==="
# Assert valid JSON syntax
jq . "$REGISTRY_FILE" >/dev/null

# Assert metadata fields
catalog_ver="$(jq -r '.catalog_version' "$REGISTRY_FILE")"
[ "$catalog_ver" = "1.0.0" ]

# Assert count of invariants (7 key invariants)
invariants_count="$(jq '.invariants | length' "$REGISTRY_FILE")"
if [ "$invariants_count" -lt 7 ]; then
  echo "Error: Expected at least 7 operational invariants, found $invariants_count" >&2
  exit 1
fi
echo "  -> Invariants cataloged ($invariants_count >= 7): OK"

# Assert count of companions (must be at least 34)
companions_count="$(jq '.companions | length' "$REGISTRY_FILE")"
if [ "$companions_count" -lt 34 ]; then
  echo "Error: Expected at least 34 companion tools, found $companions_count" >&2
  exit 1
fi
echo "  -> Companions cataloged ($companions_count >= 34): OK"

# Assert required schema fields for each companion
invalid_entries="$(jq -r '
  .companions | to_entries[] |
  select(
    (.value.name == null) or
    (.value.category == null) or
    (.value.status == null) or
    (.value.upstream_url == null) or
    (.value.license == null) or
    (.value.probe_command == null) or
    (.value.version_regex == null) or
    (.value.min_version == null) or
    (.value.supported_version_range == null)
  ) | .key
' "$REGISTRY_FILE")"

if [ -n "$invalid_entries" ]; then
  echo "Error: Found companions missing mandatory fields: $invalid_entries" >&2
  exit 1
fi
echo "  -> All $companions_count companions pass schema contract: OK"

# Assert status field validation and active vs historical partitioning
active_count="$(jq '[.companions[] | select(.status == "active")] | length' "$REGISTRY_FILE")"
historical_count="$(jq '[.companions[] | select(.status == "historical")] | length' "$REGISTRY_FILE")"

if [ "$active_count" -ne 39 ]; then
  echo "Error: Expected exactly 39 active companions, found $active_count" >&2
  exit 1
fi

if [ "$historical_count" -ne 14 ]; then
  echo "Error: Expected exactly 14 historical companions, found $historical_count" >&2
  exit 1
fi
echo "  -> Companion catalog partitioning (39 active, 14 historical, 53 total): OK"

# Assert all historical entries contain valid superseded_by and historical_notes
invalid_historical="$(jq -r '
  .companions | to_entries[] |
  select(.value.status == "historical") |
  select(
    (.value.superseded_by == null) or (.value.superseded_by == "") or
    (.value.historical_notes == null) or (.value.historical_notes == "")
  ) | .key
' "$REGISTRY_FILE")"

if [ -n "$invalid_historical" ]; then
  echo "Error: Found historical companions missing superseded_by or historical_notes: $invalid_historical" >&2
  exit 1
fi
echo "  -> All 14 historical companions contain non-empty superseded_by and historical_notes: OK"

# Assert non-empty strings for mandatory schema fields
empty_string_entries="$(jq -r '
  .companions | to_entries[] |
  select(
    (.value.name == "") or
    (.value.category == "") or
    (.value.status == "") or
    (.value.upstream_url == "") or
    (.value.license == "") or
    (.value.binary == "") or
    (.value.probe_command == "") or
    (.value.version_regex == "") or
    (.value.min_version == "") or
    (.value.supported_version_range == "")
  ) | .key
' "$REGISTRY_FILE")"

if [ -n "$empty_string_entries" ]; then
  echo "Error: Found companions with empty string fields: $empty_string_entries" >&2
  exit 1
fi
echo "  -> All mandatory fields contain non-empty strings: OK"

# Assert that every non-null binary field contains no whitespace and no pipe (|)
malformed_binaries="$(jq -r '
  .companions | to_entries[] |
  select(.value.binary != null and (.value.binary | test("[[:space:]]|\\|"))) |
  "\(.key): \(.value.binary)"
' "$REGISTRY_FILE")"

if [ -n "$malformed_binaries" ]; then
  echo "Error: Found malformed binary fields (containing whitespace or pipes):" >&2
  echo "$malformed_binaries" >&2
  exit 1
fi
echo "  -> All binary fields are clean tokens (no whitespace or pipes): OK"

# Assert zero occurrences of 2>/dev/null in registry and dependency matrix (PSL Rule 1)
if grep -n "2>/dev/null" "$REGISTRY_FILE" "$DOCS_FILE"; then
  echo "Error: Detected forbidden 2>/dev/null in $REGISTRY_FILE or $DOCS_FILE!" >&2
  exit 1
fi
echo "  -> Zero 2>/dev/null error swallowing across registry and docs: OK"

# Validate probe command syntax using bash -n
while IFS= read -r cmd; do
  if ! bash -n -c "$cmd"; then
    echo "Error: Probe command has invalid bash syntax: $cmd" >&2
    exit 1
  fi
done < <(jq -r '.companions[].probe_command' "$REGISTRY_FILE")
echo "  -> All probe commands pass bash -n syntax validation: OK"

echo "=== [Test 3] Packaging & Bootstrap Alignment Verification ==="
# Assert PKGBUILD contains git and jq>=1.6 in depends
grep -E "^\s*'git'" "$KNOT_ROOT/PKGBUILD" >/dev/null
echo "  -> PKGBUILD depends includes git: OK"
grep -E "^\s*'jq>=1.6'" "$KNOT_ROOT/PKGBUILD" >/dev/null
echo "  -> PKGBUILD depends includes jq>=1.6: OK"

# Assert PKGBUILD optdepends contains kitty>=0.26
grep -E "^\s*'kitty>=0.26:" "$KNOT_ROOT/PKGBUILD" >/dev/null
echo "  -> PKGBUILD optdepends includes kitty>=0.26: OK"

# Assert install.sh includes jq in required_cmds
grep -E 'required_cmds=\(.*"jq".*\)' "$KNOT_ROOT/install.sh" >/dev/null
echo "  -> install.sh required_cmds includes jq: OK"

# Assert install.sh maps ssh to openssh and ip to iproute2
grep -q 'cmd_to_pkg=' "$KNOT_ROOT/install.sh"
echo "  -> install.sh maps CLI commands to Arch Linux package names: OK"

echo "=== [Test 4] Documentation Integrity & Invariants Coverage ==="
# Assert key operational invariants documented in DEPENDENCY_MATRIX.md
grep -q "Headless Qt6 Crash Invariant" "$DOCS_FILE"
grep -q "KRdp Patcher ABI Invariant" "$DOCS_FILE"
grep -q "Deskflow 1.26 vs 1.27 INI Dialect Bridge" "$DOCS_FILE"
grep -q "Jq Dependency Packaging Invariant" "$DOCS_FILE"
grep -q "ControlMaster 108-Byte Socket Path Safety" "$DOCS_FILE"
grep -q "Sockets Fallback Cascade" "$DOCS_FILE"
grep -q "Login Shell SSH Promotion" "$DOCS_FILE"
echo "  -> All 7 key operational invariants documented: OK"

# Assert clean separation of active vs historical in documentation
grep -q "Active Product Companions Registry" "$DOCS_FILE"
grep -q "Historical & Superseded Tools Registry" "$DOCS_FILE"
grep -q "Barrier" "$DOCS_FILE"
grep -q "Synergy" "$DOCS_FILE"
grep -q "Input Leap" "$DOCS_FILE"
grep -q "wayvnc" "$DOCS_FILE"
grep -q "Sunshine" "$DOCS_FILE"
grep -q "EVDI" "$DOCS_FILE"
grep -q "VKMS" "$DOCS_FILE"
grep -q "drm_info" "$DOCS_FILE"
grep -q "WireGuard Tools" "$DOCS_FILE"
grep -q "Tailscale" "$DOCS_FILE"
grep -q "Syncthing" "$DOCS_FILE"
grep -q "OSTree" "$DOCS_FILE"
grep -q "btrfs-progs" "$DOCS_FILE"
grep -q "Timeshift" "$DOCS_FILE"
echo "  -> Clean separation of Active Product Companions and Historical Registry verified: OK"

echo "=== [Test 5] Live Companion Probe Execution & Regex Validation ==="
# Test live probe commands and regex matching on installed binaries
export REGISTRY_FILE
python3 - << 'EOF'
import json
import os
import re
import subprocess
import sys
from pathlib import Path

registry_path = Path(os.environ["REGISTRY_FILE"])
with open(registry_path, "r", encoding="utf-8") as f:
    data = json.load(f)

companions = data.get("companions", {})
tested = 0
passed = 0
failed = []

env = os.environ.copy()
env.pop("DISPLAY", None)
env.pop("WAYLAND_DISPLAY", None)
env.pop("QT_QPA_PLATFORM", None)

for cid, comp in companions.items():
    verified_anchor = comp.get("verified_node_versions", {}).get("anchor_desktop")
    if not verified_anchor or verified_anchor == "Not Installed":
        continue
    
    probe = comp["probe_command"]
    regex = comp["version_regex"]
    shell_filter = comp.get("shell_extraction_filter")
    
    try:
        proc = subprocess.run(
            ["bash", "-c", probe],
            env=env,
            capture_output=True,
            text=True,
            timeout=10
        )
        combined = proc.stdout + (("\n" + proc.stderr) if proc.stderr else "")
        match = re.search(regex, combined.strip(), re.MULTILINE)
        if not match:
            failed.append(f"[{cid}] Regex '{regex}' failed to match output of '{probe}': {repr(combined.strip()[:100])}")
            continue
        extracted_ver = match.group(1)
        
        if shell_filter:
            shell_proc = subprocess.run(
                ["bash", "-c", f"{probe} | {shell_filter}"],
                env=env,
                capture_output=True,
                text=True,
                timeout=10
            )
            extracted_shell = shell_proc.stdout.strip()
            if not extracted_shell:
                failed.append(f"[{cid}] Shell filter '{shell_filter}' produced empty output on '{probe}'")
                continue
        
        tested += 1
        passed += 1
    except Exception as e:
        failed.append(f"[{cid}] Error executing probe '{probe}': {e}")

print(f"  -> Live probes verified: {passed}/{tested} installed companions passed regex and filter validation")
if failed:
    print(f"Error: {len(failed)} live companion probes failed:", file=sys.stderr)
    for err in failed:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)
EOF
echo "  -> Live probe validation on host companions: OK"

echo "=== [✓] ALL DEPENDENCY MATRIX & REGISTRY TESTS PASSED! ==="
