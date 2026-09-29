#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh - Desktop Runner for Jim Heart Game
# Runs inside the desktop's Wayland graphical session

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export DISPLAY="${DISPLAY:-:0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/1000}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"

# Discover Xwayland authority cookie if available
if [ -z "${XAUTHORITY:-}" ]; then
  for xa in /run/user/1000/xauth_*; do
    if [ -f "$xa" ]; then
      export XAUTHORITY="$xa"
      break
    fi
  done
fi

# Terminate existing instance if already running
if pgrep -f 'apps/jimheart/main.py' > /tmp/knot-jimheart-prior.tmp; then
  pkill -f 'apps/jimheart/main.py'
  sleep 0.5
fi

LOG_FILE="/tmp/knot-jimheart.log"
PID_FILE="/tmp/knot-jimheart.pid"

nohup python3 -u "$HOME/Dev/knot-mesh/apps/jimheart/main.py" > "$LOG_FILE" 2>&1 &
GAME_PID=$!
echo "$GAME_PID" > "$PID_FILE"

sleep 1.0
if kill -0 "$GAME_PID" 2> /tmp/knot-jimheart-verify.err; then
  echo "[SUCCESS] Jim Heart Game is now live and running in fullscreen on desktop!"
  echo "  PID: $GAME_PID"
  echo "  Display: $WAYLAND_DISPLAY"
else
  echo "[ERROR] Game failed to start. Log output:"
  cat "$LOG_FILE"
  exit 1
fi
