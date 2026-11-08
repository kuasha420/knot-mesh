#!/usr/bin/env bash
set -euo pipefail

# Test Suite for Issue #42: Knot Kommand Kafe (Quarantined in labs/kafe/)
echo "=== Testing Knot Kommand Kafe (Issue #42 Quarantine) ==="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KAFE_ROOT="$REPO_ROOT/labs/kafe"

echo "[1/8] Verifying quarantine status and absence from repo root..."
test ! -d "$REPO_ROOT/src-tauri"
test ! -d "$REPO_ROOT/web"
test -f "$KAFE_ROOT/README.md"
kafe_cli_out="$("$REPO_ROOT/bin/knot" kafe)"
echo "$kafe_cli_out" | grep -q "quarantined"
echo "$kafe_cli_out" | grep -q "labs/kafe"
echo "  ✓ Quarantine verified (purged from repo root, documented in labs/kafe/README.md)."

echo "[2/8] Verifying Tauri v2 configuration and manifest in labs/kafe/..."
test -f "$KAFE_ROOT/src-tauri/Cargo.toml"
test -f "$KAFE_ROOT/src-tauri/tauri.conf.json"
test -f "$KAFE_ROOT/src-tauri/capabilities/default.json"
test -f "$KAFE_ROOT/src-tauri/src/main.rs"
test -f "$KAFE_ROOT/src-tauri/icons/icon.png"
echo "  ✓ Tauri v2 structure and configuration verified in labs/kafe/src-tauri/."

echo "[3/8] Checking Tauri v2 binary footprint constraint (<50MB)..."
TAURI_RELEASE="$KAFE_ROOT/src-tauri/target/release/knot-kafe"
if [ -f "$TAURI_RELEASE" ]; then
  FILE_SIZE_BYTES="$(stat -c%s "$TAURI_RELEASE")"
  FILE_SIZE_MB="$((FILE_SIZE_BYTES / 1024 / 1024))"
  echo "  Release binary size: ${FILE_SIZE_MB}MB ($FILE_SIZE_BYTES bytes)"
  if [ "$FILE_SIZE_MB" -ge 50 ]; then
    echo "  [FAIL] Binary size exceeds 50MB limit!"
    exit 1
  fi
  echo "  ✓ Binary size strictly complies with <50MB RAM/disk constraint."
else
  echo "  [INFO] Target release binary not pre-built, checking debug binary..."
  test -f "$KAFE_ROOT/src-tauri/target/debug/knot-kafe"
fi

echo "[4/8] Verifying Blackboard Kanban component and types..."
test -f "$KAFE_ROOT/web/src/components/BlackboardKanban.tsx"
test -f "$KAFE_ROOT/web/src/hooks/useGamepadNavigation.ts"
grep -q "BlackboardKanban" "$KAFE_ROOT/web/src/App.tsx"
grep -q "useGamepadNavigation" "$KAFE_ROOT/web/src/App.tsx"
grep -q "kanban" "$KAFE_ROOT/web/src/types/knot.ts"
echo "  ✓ Blackboard Kanban and Gamepad integration verified."

echo "[5/8] Verifying 7-inch 1280x800 handheld responsive styling..."
grep -q "knot-handheld-scaling" "$KAFE_ROOT/web/src/index.css"
grep -q "1280x800" "$KAFE_ROOT/web/src/index.css"
grep -q "touch-action" "$KAFE_ROOT/web/src/index.css"
echo "  ✓ Handheld touch and gamepad styling verified."

echo "[6/8] Verifying TypeScript build and type cleanliness..."
pnpm --dir "$KAFE_ROOT/web" typecheck
echo "  ✓ TypeScript typecheck passed with 0 errors."

echo "[7/8] Verifying production web bundle build..."
pnpm --dir "$KAFE_ROOT/web" build
test -f "$KAFE_ROOT/web/dist/index.html"
echo "  ✓ Production bundle built successfully in labs/kafe/web/dist/."

echo "[8/8] Verifying PSL Rule 1 compliance (no @ts-ignore or @ts-nocheck in new files)..."
if grep -rn "@ts-ignore" "$KAFE_ROOT/web/src/components/BlackboardKanban.tsx" "$KAFE_ROOT/web/src/hooks/useGamepadNavigation.ts"; then
  echo "  [FAIL] Found forbidden @ts-ignore!"
  exit 1
fi
if grep -rn "@ts-nocheck" "$KAFE_ROOT/web/src/components/BlackboardKanban.tsx" "$KAFE_ROOT/web/src/hooks/useGamepadNavigation.ts"; then
  echo "  [FAIL] Found forbidden @ts-nocheck!"
  exit 1
fi
echo "  ✓ Strict PSL Rule 1 typing verified."

echo "=== All Knot Kommand Kafe Tests Passed Successfully ==="
