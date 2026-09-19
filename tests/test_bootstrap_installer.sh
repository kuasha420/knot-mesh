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
SRCINFO="$(makepkg --printsrcinfo)"
echo "$SRCINFO" | grep -q "pkgname = knot-mesh"
echo "$SRCINFO" | grep -q "pkgver = 1.0.0.rc4"
echo "$SRCINFO" | grep -q "depends = python"
echo "$SRCINFO" | grep -q "depends = deskflow"
echo "$SRCINFO" | grep -q "optdepends = kscreen-doctor"
echo "  -> makepkg --printsrcinfo generation: OK"

echo "=== [Test 2b] PKGBUILD Packaging Verification ==="
PKG_TEST_DIR="$(mktemp -d)"
(
  export pkgdir="$PKG_TEST_DIR"
  export srcdir="$KNOT_ROOT"
  # shellcheck source=PKGBUILD
  source "$KNOT_ROOT/PKGBUILD"
  package
)
if [ ! -d "$PKG_TEST_DIR/usr/lib/knot-mesh/skills/swarm-council" ]; then
  echo "Error: skills/swarm-council missing from package build output!" >&2
  exit 1
fi
for bin_name in knot knot-installer knot-agent knot-hub knot-autounlock knot-stripd; do
  if [ ! -L "$PKG_TEST_DIR/usr/bin/$bin_name" ]; then
    echo "Error: /usr/bin/$bin_name symlink missing from package build output!" >&2
    exit 1
  fi
done
rm -rf "$PKG_TEST_DIR"
echo "  -> PKGBUILD package step installs skills and all binary symlinks: OK"

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
"$TEST_BIN_DIR/knot-installer" --version | grep -q "knot-mesh version 1.0.0-rc4"
echo "  -> Symlink execution through knot-installer --version: OK"

echo "=== [✓] ALL BOOTSTRAP INSTALLER & PKGBUILD TESTS PASSED! ==="
