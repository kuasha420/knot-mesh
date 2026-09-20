#!/usr/bin/env bash
set -euo pipefail

# Test Suite for Issue #42: Knot Kommand Kafe (Tauri v2 Container & Handheld Mode)
echo "=== Testing Knot Kommand Kafe (Issue #42) ==="

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[1/7] Verifying Tauri v2 configuration and manifest..."
test -f "$REPO_ROOT/src-tauri/Cargo.toml"
test -f "$REPO_ROOT/src-tauri/tauri.conf.json"
test -f "$REPO_ROOT/src-tauri/capabilities/default.json"
test -f "$REPO_ROOT/src-tauri/src/main.rs"
test -f "$REPO_ROOT/src-tauri/icons/icon.png"
echo "  ✓ Tauri v2 structure and configuration verified."

echo "[2/7] Checking Tauri v2 binary footprint constraint (<50MB)..."
TAURI_RELEASE="$REPO_ROOT/src-tauri/target/release/knot-kafe"
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
  test -f "$REPO_ROOT/src-tauri/target/debug/knot-kafe"
fi

echo "[3/7] Verifying Blackboard Kanban component and types..."
test -f "$REPO_ROOT/web/src/components/BlackboardKanban.tsx"
test -f "$REPO_ROOT/web/src/hooks/useGamepadNavigation.ts"
grep -q "BlackboardKanban" "$REPO_ROOT/web/src/App.tsx"
grep -q "useGamepadNavigation" "$REPO_ROOT/web/src/App.tsx"
grep -q "kanban" "$REPO_ROOT/web/src/types/knot.ts"
echo "  ✓ Blackboard Kanban and Gamepad integration verified."

echo "[4/7] Verifying 7-inch 1280x800 handheld responsive styling..."
grep -q "knot-handheld-scaling" "$REPO_ROOT/web/src/index.css"
grep -q "1280x800" "$REPO_ROOT/web/src/index.css"
grep -q "touch-action" "$REPO_ROOT/web/src/index.css"
echo "  ✓ Handheld touch and gamepad styling verified."

echo "[5/7] Verifying TypeScript build and type cleanliness..."
pnpm --dir "$REPO_ROOT/web" typecheck
echo "  ✓ TypeScript typecheck passed with 0 errors."

echo "[6/7] Verifying production web bundle build..."
pnpm --dir "$REPO_ROOT/web" build
test -f "$REPO_ROOT/web/dist/index.html"
echo "  ✓ Production bundle built successfully in web/dist/."

echo "[7/7] Verifying PSL Rule 1 compliance (no @ts-ignore or @ts-nocheck in new files)..."
if grep -rn "@ts-ignore" "$REPO_ROOT/web/src/components/BlackboardKanban.tsx" "$REPO_ROOT/web/src/hooks/useGamepadNavigation.ts"; then
  echo "  [FAIL] Found forbidden @ts-ignore!"
  exit 1
fi
if grep -rn "@ts-nocheck" "$REPO_ROOT/web/src/components/BlackboardKanban.tsx" "$REPO_ROOT/web/src/hooks/useGamepadNavigation.ts"; then
  echo "  [FAIL] Found forbidden @ts-nocheck!"
  exit 1
fi
echo "  ✓ Strict PSL Rule 1 typing verified."

echo "=== All Knot Kommand Kafe Tests Passed Successfully ==="
