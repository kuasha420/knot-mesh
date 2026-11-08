#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Mesh Bootstrap Installer & PKGBUILD (ISSUE-13)
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Syntax & Zero Error Swallowing Verification ==="
bash -n "$KNOT_ROOT/install.sh"
bash -n "$KNOT_ROOT/PKGBUILD"
echo "  -> Scripts syntax: OK"

if grep -n "2>/dev/null\||| true\||| :" "$KNOT_ROOT/install.sh" "$KNOT_ROOT/PKGBUILD"; then
  echo "Error: Detected forbidden error swallowing in install.sh or PKGBUILD!" >&2
  exit 1
fi
echo "  -> Zero error swallowing: OK"

echo "=== [Test 2] PKGBUILD Metadata Validation ==="
cd "$KNOT_ROOT"
if command -v makepkg >/dev/null; then
  SRCINFO="$(makepkg --printsrcinfo)"
  echo "$SRCINFO" | grep -q "pkgname = knot-mesh"
  echo "$SRCINFO" | grep -q "pkgver = 1.0.0.rc6"
  echo "$SRCINFO" | grep -q "depends = git"
  echo "$SRCINFO" | grep -q "depends = python"
  echo "$SRCINFO" | grep -q "depends = deskflow"
  echo "$SRCINFO" | grep -q "depends = jq>=1.6"
  echo "$SRCINFO" | grep -q "optdepends = kscreen-doctor"
  echo "$SRCINFO" | grep -q "optdepends = kitty>=0.26"
  if echo "$SRCINFO" | grep -E "webkit2gtk-4.1|cargo|pnpm"; then
    echo "Error: Forbidden GUI build/runtime dependency found in PKGBUILD!" >&2
    exit 1
  fi
  echo "  -> makepkg --printsrcinfo generation: OK"
else
  echo "  -> Notice: makepkg not installed on this host (non-Arch platform); validating PKGBUILD directly"
  (
    # shellcheck source=PKGBUILD
    source "$KNOT_ROOT/PKGBUILD"
    [ "$pkgname" = "knot-mesh" ]
    [ "$pkgver" = "1.0.0.rc6" ]
    printf '%s\n' "${depends[@]}" | grep -q "^git$"
    printf '%s\n' "${depends[@]}" | grep -q "^python$"
    printf '%s\n' "${depends[@]}" | grep -q "^deskflow$"
    printf '%s\n' "${depends[@]}" | grep -q "^jq>=1.6$"
    printf '%s\n' "${optdepends[@]}" | grep -q "^kscreen-doctor:"
    printf '%s\n' "${optdepends[@]}" | grep -q "^kitty>=0.26:"
    if printf '%s\n' "${depends[@]}" "${optdepends[@]}" | grep -E "webkit2gtk-4.1|cargo|pnpm"; then
      echo "Error: Forbidden GUI build/runtime dependency found in PKGBUILD!" >&2
      exit 1
    fi
  )
  echo "  -> PKGBUILD direct evaluation: OK"
fi
grep -q '"jq"' "$KNOT_ROOT/install.sh"
echo "  -> install.sh required_cmds contains jq: OK"

echo "=== [Test 2b] PKGBUILD Packaging Verification ==="
PKG_TEST_DIR="$(mktemp -d)"
(
  export pkgdir="$PKG_TEST_DIR"
  export srcdir="$KNOT_ROOT"
  # shellcheck source=PKGBUILD
  source "$KNOT_ROOT/PKGBUILD"
  package
)
if [ ! -d "$PKG_TEST_DIR/usr/lib/knot-mesh/runtime/skills/swarm-council" ]; then
  echo "Error: runtime/skills/swarm-council missing from package build output!" >&2
  exit 1
fi
if [ -d "$PKG_TEST_DIR/usr/lib/knot-mesh/web" ] || [ -d "$PKG_TEST_DIR/usr/lib/knot-mesh/src-tauri" ]; then
  echo "Error: web or src-tauri should not be installed by PKGBUILD!" >&2
  exit 1
fi
for bin_name in knot knot-installer knot-agent knot-hub knot-autounlock knot-stripd knot-vmon-keepalive; do
  if [ ! -L "$PKG_TEST_DIR/usr/bin/$bin_name" ]; then
    echo "Error: /usr/bin/$bin_name symlink missing from package build output!" >&2
    exit 1
  fi
done
rm -rf "$PKG_TEST_DIR"
echo "  -> PKGBUILD package step installs skills and all binary symlinks (without GUI): OK"

echo "=== [Test 2c] CLI Ergonomics & Aliases Verification ==="
# Verify knot display help contains extend, stop, and vmon
display_help="$("$KNOT_ROOT/bin/knot" display -h)"
echo "$display_help" | grep -q "extend <node>"
echo "$display_help" | grep -q "stop \[<node>\]"
echo "$display_help" | grep -q "vmon <status|start|stop>"
echo "  -> knot display help contains extend/stop/vmon: OK"

# Verify knot clip help and router
clip_help="$("$KNOT_ROOT/bin/knot" clip -h)"
echo "$clip_help" | grep -q "Usage: knot clip <sync"
echo "$clip_help" | grep -q "get|set"
# Verify clip set argument validation
clip_err_out="" clip_err_rc=0
clip_err_out="$("$KNOT_ROOT/bin/knot" clip set </dev/null 2>&1)" || clip_err_rc=$?
[ $clip_err_rc -eq 1 ]
echo "  -> knot clip help and set validation: OK"

# Verify display extend and vmon start routing
disp_extend_out="" disp_extend_rc=0
disp_extend_out="$("$KNOT_ROOT/bin/knot" display extend 2>&1)" || disp_extend_rc=$?
disp_vmon_out="" disp_vmon_rc=0
disp_vmon_out="$("$KNOT_ROOT/bin/knot" display vmon start 2>&1)" || disp_vmon_rc=$?
[ $disp_extend_rc -eq 1 ]
[ $disp_vmon_rc -eq 1 ]
echo "  -> knot display extend and vmon start validation: OK"

# Verify knot kafe outputs quarantine notice
kafe_out="$("$KNOT_ROOT/bin/knot" kafe)"
echo "$kafe_out" | grep -q "quarantined"
echo "$kafe_out" | grep -q "labs/kafe"
echo "  -> knot kafe quarantine notice: OK"

echo "=== [Test 3] Bootstrap Installer Isolation Run ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TEST_INSTALL_DIR="$TMP_DIR/share/knot-mesh"
TEST_BIN_DIR="$TMP_DIR/bin"

# Setup existing repo copy in TEST_INSTALL_DIR to test update and symlinking
mkdir -p "$TEST_INSTALL_DIR/bin"
cp "$KNOT_ROOT/bin/knot" "$TEST_INSTALL_DIR/bin/"
cp "$KNOT_ROOT/bin/knot-installer" "$TEST_INSTALL_DIR/bin/"
chmod +x "$TEST_INSTALL_DIR/bin/"*

export KNOT_INSTALL_DIR="$TEST_INSTALL_DIR"
export KNOT_BIN_DIR="$TEST_BIN_DIR"
export PATH="$TEST_BIN_DIR:$PATH"

# Run install.sh non-interactively (piping true to stdin)
echo "3" | bash "$KNOT_ROOT/install.sh"

# Verify symlinks
if [ ! -L "$TEST_BIN_DIR/knot" ] || [ ! -L "$TEST_BIN_DIR/knot-installer" ]; then
  echo "Error: Expected symlinks in $TEST_BIN_DIR not created!" >&2
  exit 1
fi

if [ ! -x "$TEST_BIN_DIR/knot" ] || [ ! -x "$TEST_BIN_DIR/knot-installer" ]; then
  echo "Error: Symlinked binaries not executable!" >&2
  exit 1
fi

# Verify execution through symlink
"$TEST_BIN_DIR/knot-installer" --version | grep -q "knot-mesh version 1.0.0-rc6"
echo "  -> Symlink execution through knot-installer --version: OK"

echo "=== [✓] ALL BOOTSTRAP INSTALLER & PKGBUILD TESTS PASSED! ==="
