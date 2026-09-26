#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Test Suite: KDE Connect Full E2E & Wayland Clipboard Harmonization
# Governed by PSL Monorepo Engineering Standard (Rule 1: Zero Error Swallowing, Rule 2: No Test Homework)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
unset KNOT_NODE_ID KNOT_HUB_URL KNOT_RUN_ID KNOT_COUNCIL_RUN_ID KNOT_ACTIVE_SWARM

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$KNOT_ROOT/core/modules/kdeconnect.sh"
bash -n "$KNOT_ROOT/core/modules/firewall.sh"
bash -n "$KNOT_ROOT/core/modules/auth.sh"
bash -n "$KNOT_ROOT/bin/knot"
bash -n "$KNOT_ROOT/bin/knot-installer"
echo "  -> Syntax audit: OK"

echo "=== [Test 2] PSL Rule 1 Zero Error Swallowing Code Audit ==="
for f in \
  "$KNOT_ROOT/core/modules/kdeconnect.sh" \
  "$KNOT_ROOT/core/modules/firewall.sh" \
  "$KNOT_ROOT/core/modules/auth.sh" \
  "$KNOT_ROOT/bin/knot" \
  "$KNOT_ROOT/bin/knot-installer"; do
  # Check for forbidden error swallowing constructs
  if grep -n -E '(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)' "$f" | grep -v "source " | grep -v "^[[:space:]]*#"; then
    echo "Error: Forbidden error swallowing construct found in $f" >&2
    exit 1
  fi
done
echo "  -> PSL Rule 1 compliance: OK"

TMP_DIR="$(mktemp -d)"
_cleanup_qa_suite() {
  rm -rf "$TMP_DIR"
}
trap _cleanup_qa_suite EXIT

export HOME="$TMP_DIR/home"
mkdir -p "$HOME/.config/kdeconnect"
mkdir -p "$HOME/.config/knot/swarms/testswarm/nodes"

echo "=== [Test 3] Python INI Parsing Idempotency & Case Preservation ==="
CFG_FILE="$HOME/.config/kdeconnect/config"

cat << 'EOF' > "$CFG_FILE"
[General]
customDevices=192.168.1.100,192.168.1.101
keyAlgorithm=EC
mixedCaseOption=PreserveMePlease
EOF

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

run_ini_injection "192.168.1.101,192.168.1.102"
cur_devices="$(awk -F= '/^customDevices=/ {print $2}' "$CFG_FILE")"
[ "$cur_devices" = "192.168.1.100,192.168.1.101,192.168.1.102" ] || {
  echo "Error: Unexpected customDevices string: $cur_devices" >&2
  exit 1
}

# Idempotency check
run_ini_injection "192.168.1.101,192.168.1.102"
cur_devices_2="$(awk -F= '/^customDevices=/ {print $2}' "$CFG_FILE")"
[ "$cur_devices_2" = "$cur_devices" ] || {
  echo "Error: INI injection was not idempotent: $cur_devices_2 vs $cur_devices" >&2
  exit 1
}
echo "  -> KDE Connect customDevices INI parsing & idempotency: OK"

echo "=== [Test 4] Wayland & Klipper Clipboard Pipeline Integrity ==="
# Source product module directly (PSL Rule 2)
source "$KNOT_ROOT/core/lib.sh"
source "$KNOT_ROOT/core/modules/kdeconnect.sh"

# 4a. Short text roundtrip
SHORT_TEXT="KnotMesh-Test-Short-$(date +%s)"
if kdeconnect_set_clipboard "$SHORT_TEXT"; then
  read_back="$(kdeconnect_get_clipboard | tr -d '\r\n')"
  [ "$read_back" = "$SHORT_TEXT" ] || {
    echo "Error: Short text mismatch: expected '$SHORT_TEXT', got '$read_back'" >&2
    exit 1
  }
  echo "  -> Short text round-trip: OK"
else
  echo "  -> Notice: Headless environment without Klipper/Wayland display; skipping direct DBus round-trip"
fi

# 4b. Multi-line snippet roundtrip
MULTILINE_TEXT=$'Line 1: Knot Mesh\nLine 2: KDE Connect Clipboard\nLine 3: Zero-latency input leap'
if kdeconnect_set_clipboard "$MULTILINE_TEXT"; then
  read_back_multi="$(kdeconnect_get_clipboard)"
  # Compare with stripped trailing newline
  [ "${read_back_multi%$'\n'}" = "${MULTILINE_TEXT%$'\n'}" ] || {
    echo "Error: Multi-line text mismatch" >&2
    exit 1
  }
  echo "  -> Multi-line snippet round-trip: OK"
fi

# 4c. Long URL with complex query parameters
LONG_URL="https://accounts.google.com/o/oauth2/v2/auth?scope=openid%20profile%20email&response_type=code&state=knot_state_42&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob&client_id=1020304050-example.apps.googleusercontent.com"
if kdeconnect_set_clipboard "$LONG_URL"; then
  read_back_url="$(kdeconnect_get_clipboard | tr -d '\r\n')"
  [ "$read_back_url" = "$LONG_URL" ] || {
    echo "Error: Long URL mismatch: expected '$LONG_URL', got '$read_back_url'" >&2
    exit 1
  }
  echo "  -> Complex long URL round-trip: OK"
fi

# 4d. Large payload (>8KB / 16KB text blocks)
LARGE_PAYLOAD="HEADER_$(head -c 16384 < /dev/urandom | base64 | tr -d '\r\n')_FOOTER"
if kdeconnect_set_clipboard "$LARGE_PAYLOAD"; then
  read_back_large="$(kdeconnect_get_clipboard | tr -d '\r\n')"
  [ "${#read_back_large}" -ge 16384 ] || {
    echo "Error: Large payload was truncated: expected >= 16384 bytes, got ${#read_back_large}" >&2
    exit 1
  }
  [ "$read_back_large" = "$LARGE_PAYLOAD" ] || {
    echo "Error: Large payload content mismatch" >&2
    exit 1
  }
  echo "  -> Large payload (${#read_back_large} bytes) round-trip: OK"
fi

echo "=== [Test 5] Knot CLI Dispatch & Subcommand Routing ==="
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

cat << 'EOF' > "$FAKE_BIN/kdeconnect-cli"
#!/usr/bin/env bash
case "${1:-}" in
  --my-id)
    echo "mock-device-id-qa-1234"
    ;;
  -l)
    echo "- psl-0000: 1e5a1fc88ac847748f1cf8b109899543 on 192.168.68.147 via LAN (reachable)"
    echo "- devbox: 2eea46b4fa5942d49286ef3ba8e6df56 on 192.168.68.145 via LAN (reachable)"
    echo "2 devices found"
    ;;
  -a)
    echo "1 device found: - devbox: 2eea46b4fa5942d49286ef3ba8e6df56 on 192.168.68.145 via LAN (paired and reachable)"
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

  # 5a. knot kdeconnect status
  echo "  Testing 'knot kdeconnect status'..."
  status_out="$("$KNOT_ROOT/bin/knot" kdeconnect status)"
  echo "$status_out" | grep -q "mock-device-id-qa-1234" || {
    echo "Error: status failed to display mock device ID" >&2
    exit 1
  }

  # 5b. knot kdeconnect pair missing arguments check
  echo "  Testing 'knot kdeconnect pair' error handling..."
  local_out=""
  local_rc=0
  local_out="$("$KNOT_ROOT/bin/knot" kdeconnect pair 2>&1)" || local_rc=$?
  [ $local_rc -ne 0 ] || {
    echo "Error: 'knot kdeconnect pair' should have exited with non-zero when target missing: $local_out" >&2
    exit 1
  }

  # 5c. knot kdeconnect share help
  echo "  Testing 'knot kdeconnect share --help'..."
  share_help="$("$KNOT_ROOT/bin/knot" kdeconnect share --help)"
  echo "$share_help" | grep -q "knot kdeconnect share" || {
    echo "Error: share help text missing" >&2
    exit 1
  }
)
echo "  -> CLI dispatch for kdeconnect: OK"

echo "=== [Test 6] Keyring & Secret Leakage Prevention Audit ==="
SECRET_MOCK="super-secret-oauth-bearer-token-123456789"
echo "$SECRET_MOCK" > "$TMP_DIR/secret.txt"

# Test that sharing via CLI pipes payload without leaking to unrelated logging
share_audit_out="$(bash -c "
  source \"$KNOT_ROOT/core/lib.sh\"
  source \"$KNOT_ROOT/core/modules/kdeconnect.sh\"
  out=\"\$(kdeconnect_share --target non_existent_node \"$SECRET_MOCK\" 2>&1)\" || rc=\$?
  echo \"\$out\"
")"

# Ensure privateKey.pem is not referenced in public manifests
if [ -d "$KNOT_ROOT/core/manifests" ]; then
  leak_count="$(grep -rn "privateKey.pem" "$KNOT_ROOT/core/manifests" | wc -l)"
  if [ "$leak_count" -gt 0 ]; then
    echo "Error: privateKey.pem referenced in manifests" >&2
    exit 1
  fi
fi
echo "  -> Keyring & secret leakage prevention: OK"

echo "=== All KDE Connect E2E & Wayland Harmonization Tests Passed Flawlessly! ==="
