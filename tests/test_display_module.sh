#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Automated Verification for Display Module (Strand B: #71, #66)

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
BIN_KNOT="$KNOT_ROOT/bin/knot"
DISPLAY_MODULE="$KNOT_ROOT/core/modules/display.sh"

echo "=== [Test 1] Bash Syntax Verification ==="
bash -n "$DISPLAY_MODULE"
echo "  -> display.sh syntax: OK"

echo "=== [Test 2] Zero Error Swallowing Audit (PSL Rule 1) ==="
FORBIDDEN_PATTERN='(2>/dev/null|&>/dev/null|> */dev/null *2>&1|\|\| *true|\|\| *:)'
matches=""
if ! matches=$(grep -n -E "$FORBIDDEN_PATTERN" "$DISPLAY_MODULE" 2>&1 | grep -v "^[0-9]*:[[:space:]]*#"); then
  matches=""
fi
if [ -n "$matches" ]; then
  echo "Error: Forbidden error swallowing detected in display.sh:" >&2
  echo "$matches" >&2
  exit 1
fi
echo "  -> Zero error swallowing in display.sh: OK"

echo "=== [Test 3] knot display launch Presets & Hub URL Injection ==="
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

# Test board preset
out_board="$("$BIN_KNOT" display launch laptop board --dry-run)"
if ! echo "$out_board" | grep -q "export KNOT_HUB_URL="; then
  echo "Error: KNOT_HUB_URL missing in display launch board: $out_board" >&2
  exit 1
fi
if ! echo "$out_board" | grep -q "knot council board --compact"; then
  echo "Error: board preset command missing: $out_board" >&2
  exit 1
fi
echo "  -> Preset 'board' command and KNOT_HUB_URL injection: OK"

# Test quota preset
out_quota="$("$BIN_KNOT" display launch laptop quota --dry-run)"
if ! echo "$out_quota" | grep -q "knot quota live --compact"; then
  echo "Error: quota preset command missing: $out_quota" >&2
  exit 1
fi
echo "  -> Preset 'quota' command: OK"

# Test confluence preset
out_conf="$("$BIN_KNOT" display launch laptop confluence --dry-run)"
if ! echo "$out_conf" | grep -q "knot council start --interactive --tiling grid"; then
  echo "Error: confluence preset command missing: $out_conf" >&2
  exit 1
fi
echo "  -> Preset 'confluence' command: OK"

# Test custom command
out_custom="$("$BIN_KNOT" display launch laptop "htop" --dry-run)"
if ! echo "$out_custom" | grep -q "htop"; then
  echo "Error: custom command missing: $out_custom" >&2
  exit 1
fi
echo "  -> Custom command launch: OK"

echo "=== [Test 4] knot display capture-fleet Structured JSON Output ==="
cap_out="$("$BIN_KNOT" display capture-fleet --output-dir "$TEST_TMP/caps" --json)"

# Validate JSON schema using python
python3 -c '
import sys, json
try:
    data = json.loads(sys.argv[1])
except Exception as e:
    print(f"Error: Invalid JSON output: {e}", file=sys.stderr)
    sys.exit(1)

assert "timestamp" in data, "Missing timestamp field"
assert "captures" in data, "Missing captures field"
assert isinstance(data["captures"], list), "captures must be a list"
for c in data["captures"]:
    assert "node" in c, "Missing node in capture item"
    assert "display" in c, "Missing display in capture item"
    assert "status" in c, "Missing status in capture item"
    st = c.get("status")
    assert st in ("ok", "error"), f"Invalid status: {st}"
' "$cap_out"
echo "  -> Structured JSON schema validation: OK"

echo "=== [Test 5] Synthetic Mock Screenshot Capture & Dimensions ==="
# Create a synthetic 100x50 PNG image to test the dimension parser and base64 encoding
MOCK_BIN_DIR="$TEST_TMP/mock_bin"
mkdir -p "$MOCK_BIN_DIR"

python3 -c '
import struct, zlib
# Minimal 100x50 valid PNG generator
width, height = 100, 50
ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
ihdr_crc = struct.pack(">I", zlib.crc32(b"IHDR" + ihdr))
raw_data = b"\x00" + b"\x00\x00\xff" * width
idat_data = zlib.compress(raw_data * height)
idat_crc = struct.pack(">I", zlib.crc32(b"IDAT" + idat_data))
png = (
    b"\x89PNG\r\n\x1a\n"
    + struct.pack(">I", len(ihdr)) + b"IHDR" + ihdr + ihdr_crc
    + struct.pack(">I", len(idat_data)) + b"IDAT" + idat_data + idat_crc
    + struct.pack(">I", 0) + b"IEND" + struct.pack(">I", zlib.crc32(b"IEND"))
)
with open("'$TEST_TMP'/mock.png", "wb") as f:
    f.write(png)
'

# Create a mock spectacle executable
cat << EOF > "$MOCK_BIN_DIR/spectacle"
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  if [ "\$1" = "-o" ]; then
    cp "$TEST_TMP/mock.png" "\$2"
    exit 0
  fi
  shift
done
exit 1
EOF
chmod +x "$MOCK_BIN_DIR/spectacle"

mock_cap_out="$(PATH="$MOCK_BIN_DIR:$PATH" "$BIN_KNOT" display capture-fleet --node local --output-dir "$TEST_TMP/mock_caps" --format base64 --json)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
caps = data["captures"]
assert len(caps) >= 1, "Expected at least 1 capture"
local_cap = caps[0]
assert local_cap["status"] == "ok", f"Expected ok status, got {local_cap}"
w = local_cap["width"]
h = local_cap["height"]
assert w == 100, f"Expected width 100, got {w}"
assert h == 50, f"Expected height 50, got {h}"
assert "base64" in local_cap, "Missing base64 payload"
assert len(local_cap["base64"]) > 20, "base64 payload too short"
' "$mock_cap_out"
echo "  -> Synthetic mock capture, width 100, height 50, and base64 payload: OK"

echo "=== [Test 6] Remote Screenshot Capture Stderr Isolation & Diagnostic Integrity ==="
# Mock SSH returning PNG bytes on stdout and SSH warnings on stderr
cat << EOF > "$MOCK_BIN_DIR/ssh"
#!/usr/bin/env bash
# Simulate SSH banner/warning on stderr
echo "Warning: Permanently added 'steamdeck' to known hosts." >&2
# Simulate remote execution returning mock PNG on stdout
cat "$TEST_TMP/mock.png"
exit 0
EOF
chmod +x "$MOCK_BIN_DIR/ssh"

remote_cap_out="$(KNOT_NODE_ID="desktop" PATH="$MOCK_BIN_DIR:$PATH" "$BIN_KNOT" display capture-fleet --node steamdeck --output-dir "$TEST_TMP/remote_caps" --json)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
caps = data["captures"]
assert len(caps) == 1, f"Expected 1 capture, got {caps}"
cap = caps[0]
assert cap["status"] == "ok", f"Expected status ok, got {cap}"
w = cap["width"]
h = cap["height"]
assert w == 100, f"Expected width 100, got {w}"
assert h == 50, f"Expected height 50, got {h}"
with open(cap["path"], "rb") as f:
    header = f.read(8)
    assert header == b"\x89PNG\r\n\x1a\n", f"PNG header corrupted by stderr: {header}"
' "$remote_cap_out"
echo "  -> Remote capture PNG uncorrupted by SSH stderr: OK"

# Mock SSH failing with an error
cat << 'EOF' > "$MOCK_BIN_DIR/ssh"
#!/usr/bin/env bash
echo "ssh: connect to host steamdeck port 22: Connection refused" >&2
exit 255
EOF
chmod +x "$MOCK_BIN_DIR/ssh"

remote_fail_out="$(KNOT_NODE_ID="desktop" PATH="$MOCK_BIN_DIR:$PATH" "$BIN_KNOT" display capture-fleet --node steamdeck --output-dir "$TEST_TMP/remote_caps" --json)"

python3 -c '
import sys, json
data = json.loads(sys.argv[1])
cap = data["captures"][0]
assert cap["status"] == "error", f"Expected error status, got {cap}"
err = cap.get("error", "")
assert "connection refused" in err.lower() or "remote capture failed" in err.lower(), f"Unexpected error message: {err}"
' "$remote_fail_out"
echo "  -> Remote capture failure captures accurate diagnostic without error loss: OK"

echo "=== [✓] ALL DISPLAY MODULE TESTS PASSED! ==="
