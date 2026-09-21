#!/usr/bin/env bash
set -euo pipefail

# Test suite for Knot Dev Operations, Safety Lockouts & Drift Healing
KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/lib.sh"
bash -n "$KNOT_ROOT/core/modules/swarm_sync.sh"
bash -n "$KNOT_ROOT/bin/knot"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in "$KNOT_ROOT/core/modules/swarm_sync.sh"; do
  if grep -rn "2>/dev/null" "$f"; then
    echo "Error: Forbidden 2>/dev/null found in $f" >&2
    exit 1
  fi
  if grep -rn "|| true" "$f"; then
    echo "Error: Forbidden || true found in $f" >&2
    exit 1
  fi
  if grep -rn "|| :" "$f"; then
    echo "Error: Forbidden || : found in $f" >&2
    exit 1
  fi
done
# Audit install type and lockout functions in core/lib.sh
if tail -n 100 "$KNOT_ROOT/core/lib.sh" | grep -q "2>/dev/null"; then
  echo "Error: Forbidden 2>/dev/null found in core/lib.sh install type functions" >&2
  exit 1
fi
echo "  -> PSL Rule 1 compliance: OK"

echo "=== [Test 3] Install Type Detection Logic ==="
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/knot" "$HOME/.local/bin"

# Source core/lib.sh
# shellcheck source=/dev/null
source "$KNOT_ROOT/core/lib.sh"

# 3a. Marker test
echo "dev" > "$HOME/.config/knot/install_type"
itype="$(knot_detect_install_type "$TMP_DIR/dummy")"
[ "$itype" = "dev" ] || { echo "Expected dev, got $itype" >&2; exit 1; }

echo "prod" > "$HOME/.config/knot/install_type"
itype="$(knot_detect_install_type "$TMP_DIR/dummy")"
[ "$itype" = "prod" ] || { echo "Expected prod, got $itype" >&2; exit 1; }

rm -f "$HOME/.config/knot/install_type"

# 3b. Git worktree test
FAKE_GIT="$TMP_DIR/fake_repo"
mkdir -p "$FAKE_GIT/.git"
itype="$(knot_detect_install_type "$FAKE_GIT")"
[ "$itype" = "dev" ] || { echo "Expected dev for git repo, got $itype" >&2; exit 1; }

# 3c. Standalone release dir (no git) test
FAKE_PROD="$TMP_DIR/fake_release"
mkdir -p "$FAKE_PROD/bin" "$FAKE_PROD/core"
itype="$(knot_detect_install_type "$FAKE_PROD")"
[ "$itype" = "prod" ] || { echo "Expected prod for release dir, got $itype" >&2; exit 1; }
echo "  -> knot_detect_install_type: OK"

echo "=== [Test 4] Bidirectional Safety Lockout Logic ==="
# 4a. On a Dev node:
echo "dev" > "$HOME/.config/knot/install_type"
# Prod command should fail without force
if knot_enforce_lockout "prod" "knot sync" 0; then
  echo "Error: Expected lockout failure running prod on dev installation" >&2
  exit 1
fi
# Prod command should succeed with force
if ! knot_enforce_lockout "prod" "knot sync" 1; then
  echo "Error: Expected bypass with force_prod=1 on dev installation" >&2
  exit 1
fi
# Dev command should succeed without force
if ! knot_enforce_lockout "dev" "knot sync" 0; then
  echo "Error: Expected dev command to succeed on dev installation" >&2
  exit 1
fi

# 4b. On a Prod node:
echo "prod" > "$HOME/.config/knot/install_type"
# Dev command should fail without force
if knot_enforce_lockout "dev" "knot sync" 0; then
  echo "Error: Expected lockout failure running dev on prod installation" >&2
  exit 1
fi
# Dev command should succeed with force
if ! knot_enforce_lockout "dev" "knot sync" 1; then
  echo "Error: Expected bypass with force_dev=1 on prod installation" >&2
  exit 1
fi
# Prod command should succeed without force
if ! knot_enforce_lockout "prod" "knot sync" 0; then
  echo "Error: Expected prod command to succeed on prod installation" >&2
  exit 1
fi
echo "  -> knot_enforce_lockout: OK"

echo "=== [Test 5] Local Development Drift Auto-Healing ==="
# Source swarm_sync.sh
# shellcheck source=/dev/null
source "$KNOT_ROOT/core/modules/swarm_sync.sh"

# Mock KNOT_ROOT with simulated binaries and skill
MOCK_ROOT="$TMP_DIR/mock_root"
mkdir -p "$MOCK_ROOT/bin" "$MOCK_ROOT/runtime/skills/swarm-council/scripts"
touch "$MOCK_ROOT/bin/knot" "$MOCK_ROOT/bin/knot-installer"
chmod +x "$MOCK_ROOT/bin/knot" "$MOCK_ROOT/bin/knot-installer"
echo "print('council_hook')" > "$MOCK_ROOT/runtime/skills/swarm-council/scripts/council_hook.py"

# Pre-populate dummy config.json with useAiCredits=true
mkdir -p "$HOME/.gemini/config" "$HOME/.gemini/antigravity-cli"
cat << 'CFG_EOF' > "$HOME/.gemini/config/config.json"
{
  "userSettings": {
    "useAiCredits": true,
    "themeMode": "THEME_MODE_LIGHT"
  }
}
CFG_EOF

# Run swarm_sync_dev_heal_local using MOCK_ROOT
KNOT_ROOT="$MOCK_ROOT" swarm_sync_dev_heal_local

# Verify marker
marker="$(tr -d '[:space:]' < "$HOME/.config/knot/install_type")"
[ "$marker" = "dev" ] || { echo "Expected dev marker, got $marker" >&2; exit 1; }

# Verify binary symlinks
[ -L "$HOME/.local/bin/knot" ] || { echo "Expected symlink ~/.local/bin/knot" >&2; exit 1; }
[ -L "$HOME/.local/bin/knot-installer" ] || { echo "Expected symlink ~/.local/bin/knot-installer" >&2; exit 1; }

# Verify skill symlink
[ -L "$HOME/.gemini/config/skills/swarm-council" ] || { echo "Expected symlink ~/.gemini/config/skills/swarm-council" >&2; exit 1; }

# Verify hooks.json
[ -f "$HOME/.gemini/config/hooks.json" ] || { echo "Expected ~/.gemini/config/hooks.json" >&2; exit 1; }
grep -q "swarm-council-coordinator" "$HOME/.gemini/config/hooks.json" || { echo "Missing swarm-council-coordinator in hooks.json" >&2; exit 1; }

# Verify config.json healed
grep -q '"useAiCredits": false' "$HOME/.gemini/config/config.json" || { echo "config.json not healed" >&2; exit 1; }
grep -q '"themeMode": "THEME_MODE_DARK"' "$HOME/.gemini/config/config.json" || { echo "themeMode not healed" >&2; exit 1; }

echo "  -> swarm_sync_dev_heal_local: OK"

echo "=== [Test 6] CLI Help Options Verification ==="
# Test bin/knot sync help
sync_help="$("$KNOT_ROOT/bin/knot" sync --help)"
echo "$sync_help" | grep -q -- "--dev" || { echo "knot sync --help missing --dev" >&2; exit 1; }
echo "$sync_help" | grep -q -- "--force-prod" || { echo "knot sync --help missing --force-prod" >&2; exit 1; }
echo "$sync_help" | grep -q -- "--force-dev" || { echo "knot sync --help missing --force-dev" >&2; exit 1; }

# Test bin/knot update help
update_help="$("$KNOT_ROOT/bin/knot" update --help)"
echo "$update_help" | grep -q -- "--dev" || { echo "knot update --help missing --dev" >&2; exit 1; }
echo "$update_help" | grep -q -- "--force-prod" || { echo "knot update --help missing --force-prod" >&2; exit 1; }
echo "$update_help" | grep -q -- "--force-dev" || { echo "knot update --help missing --force-dev" >&2; exit 1; }

# Test main knot help
main_help="$("$KNOT_ROOT/bin/knot" --help)"
echo "$main_help" | grep -q -- "knot update" || { echo "knot help missing update" >&2; exit 1; }
echo "$main_help" | grep -q -- "knot sync" || { echo "knot help missing sync" >&2; exit 1; }
echo "  -> CLI help options: OK"

echo "=== [✓] ALL DEV OPS & LOCKOUT TESTS PASSED! ==="
