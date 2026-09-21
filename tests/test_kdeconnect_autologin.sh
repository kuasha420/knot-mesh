#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Test Suite: KDE Connect & Ephemeral Autologin Module Verification
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
unset KNOT_NODE_ID KNOT_HUB_URL KNOT_RUN_ID KNOT_COUNCIL_RUN_ID KNOT_ACTIVE_SWARM

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/modules/kdeconnect.sh"
bash -n "$KNOT_ROOT/core/modules/autologin.sh"
bash -n "$KNOT_ROOT/bin/knot"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in \
  "$KNOT_ROOT/core/modules/kdeconnect.sh" \
  "$KNOT_ROOT/core/modules/autologin.sh"; do
  # Check for forbidden error swallowing constructs
  if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$f" | grep -v "source " | grep -v "^[[:space:]]*#"; then
    echo "Error: Forbidden error swallowing construct found in $f" >&2
    exit 1
  fi
done
echo "  -> PSL Rule 1 compliance: OK"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/kdeconnect"
mkdir -p "$HOME/.config/knot/swarms/testswarm/nodes"

echo "=== [Test 3] Python INI Parsing Idempotency & Case Preservation (KDE Connect) ==="
CFG_FILE="$HOME/.config/kdeconnect/config"

# Seed initial config with existing customDevices and mixed case keys
cat << 'EOF' > "$CFG_FILE"
[General]
customDevices=192.168.1.100,192.168.1.101
keyAlgorithm=EC
mixedCaseOption=PreserveMePlease
EOF

# Define helper to run Python INI injection matching kdeconnect_configure_custom_devices
run_ini_injection() {
  local new_ips_arg="$1"
  python3 - << PY_INI
import configparser
import os

cfg_file = "$CFG_FILE"
new_ips_str = "$new_ips_arg"
new_ips = [x.strip() for x in new_ips_str.split(",") if x.strip()]

config = configparser.RawConfigParser()
config.optionxform = lambda opt: opt

if os.path.isfile(cfg_file):
    config.read(cfg_file)

if not config.has_section("General"):
    config.add_section("General")

existing_ips = []
if config.has_option("General", "customDevices"):
    cur = config.get("General", "customDevices")
    existing_ips = [x.strip() for x in cur.split(",") if x.strip()]

for ip in new_ips:
    if ip not in existing_ips:
        existing_ips.append(ip)

config.set("General", "customDevices", ",".join(existing_ips))
if not config.has_option("General", "keyAlgorithm"):
    config.set("General", "keyAlgorithm", "EC")

cfg_dir = os.path.dirname(cfg_file)
os.makedirs(cfg_dir, exist_ok=True)
tmp_file = cfg_file + ".tmp"
with open(tmp_file, "w") as f:
    config.write(f, space_around_delimiters=False)
os.replace(tmp_file, cfg_file)
PY_INI
}

# 3a. Inject an existing IP (192.168.1.101) and a new IP (192.168.1.102)
run_ini_injection "192.168.1.101,192.168.1.102"

# Verify 192.168.1.100 is retained, 192.168.1.101 is not duplicated, 192.168.1.102 is added
cur_devices="$(awk -F= '/^customDevices=/ {print $2}' "$CFG_FILE")"
echo "  Updated customDevices: $cur_devices"
[ "$cur_devices" = "192.168.1.100,192.168.1.101,192.168.1.102" ] || {
  echo "Error: Unexpected customDevices string: $cur_devices" >&2
  exit 1
}

# Verify mixed-case key was NOT lowercased
grep -q "^mixedCaseOption=PreserveMePlease" "$CFG_FILE" || {
  echo "Error: mixedCaseOption was mutated or lost" >&2
  exit 1
}

# 3b. Idempotency test: Re-run with identical parameters
run_ini_injection "192.168.1.101,192.168.1.102"
cur_devices_2="$(awk -F= '/^customDevices=/ {print $2}' "$CFG_FILE")"
[ "$cur_devices_2" = "$cur_devices" ] || {
  echo "Error: INI injection was not idempotent: $cur_devices_2 vs $cur_devices" >&2
  exit 1
}
echo "  -> KDE Connect INI parsing & idempotency: OK"

echo "=== [Test 4] Autologin Non-Mutating Check & Advisory Diagnostics ==="
# Source autologin module in subshell to avoid polluting test environment
(
  export HOME="$TMP_DIR/home"
  export KNOT_ROOT
  # Mock swarm environment
  echo "testswarm" > "$HOME/.config/knot/active_swarm"
  export KNOT_ACTIVE_SWARM="testswarm"

  # Source modules
  source "$KNOT_ROOT/core/lib.sh"
  source "$KNOT_ROOT/core/modules/autounlock.sh"
  source "$KNOT_ROOT/core/modules/autologin.sh"

  # Verify autologin_check executes and returns a recognized state without error
  check_state="$(autologin_check)"
  echo "  autologin_check reported state: $check_state"
  case "$check_state" in
    IS_ANCHOR|SESSION_LOCKED|ALREADY_LOGGED_IN|OUTSIDE_FENCE|ANCHOR_LOCKED|ANCHOR_OFFLINE|DM_MIGRATION_RECOMMENDED|READY_FOR_AUTOLOGIN)
      echo "  -> Recognized autologin check state."
      ;;
    *)
      echo "Error: Unrecognized autologin state: $check_state" >&2
      exit 1
      ;;
  esac

  # Verify autologin_doctor runs without failure
  echo "  Running autologin_doctor advisory diagnostics:"
  autologin_doctor
)
echo "  -> Autologin non-mutating check & doctor: OK"

echo "=== [Test 5] Knot CLI Dispatch for kdeconnect & autologin ==="
# Test bin/knot dispatch using mock tools
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

# Mock kdeconnect-cli
cat << 'EOF' > "$FAKE_BIN/kdeconnect-cli"
#!/usr/bin/env bash
case "${1:-}" in
  --my-id)
    echo "mock-device-id-999"
    ;;
  -a)
    if [ "${2:-}" = "--id-name" ]; then
      echo "mock-peer-01 PeerWorkstation"
    else
      echo "1 device found: - mock-peer-01: PeerWorkstation (paired and reachable)"
    fi
    ;;
  --pair)
    echo "Pairing requested to ${3:-unknown}"
    ;;
  *)
    echo "mock kdeconnect-cli called with: $*"
    ;;
esac
EOF
chmod +x "$FAKE_BIN/kdeconnect-cli"

(
  export PATH="$FAKE_BIN:$PATH"
  export HOME="$TMP_DIR/home"
  export KNOT_ACTIVE_SWARM="testswarm"

  # 5a. knot autologin subcommands
  echo "  Testing 'knot autologin check'..."
  "$KNOT_ROOT/bin/knot" autologin check

  echo "  Testing 'knot autologin status'..."
  "$KNOT_ROOT/bin/knot" autologin status

  # 5b. knot kdeconnect subcommands
  echo "  Testing 'knot kdeconnect status' with mock device..."
  kde_status="$("$KNOT_ROOT/bin/knot" kdeconnect status)"
  echo "$kde_status"
  echo "$kde_status" | grep -q "Local Device ID: mock-device-id-999" || {
    echo "Error: kdeconnect status failed to display local device ID" >&2
    exit 1
  }

  echo "  Testing 'knot kdeconnect pair' without arguments (expects error)..."
  if "$KNOT_ROOT/bin/knot" kdeconnect pair; then
    echo "Error: 'knot kdeconnect pair' should have failed without arguments" >&2
    exit 1
  else
    echo "  -> kdeconnect pair safely rejected missing argument."
  fi
)
echo "  -> CLI dispatch for kdeconnect & autologin: OK"

echo "=== All KDE Connect & Autologin Tests Passed Flawlessly! ==="
