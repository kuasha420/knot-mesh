#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 5 Multi-Mode Prompt Deliverance Engine
# Handles confluence, headless, tui, gui, and suggested execution modes

MODE="${1:-confluence}"
RUN_ID="${2:-}"
PROJECT="${3:-knot-mesh}"

if [ -z "$RUN_ID" ]; then
  echo "Usage: $0 <confluence|headless|tui|gui|suggested> <run_id> [project_name]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KNOT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MISSIONS_DIR="$HOME/.config/knot/missions/$RUN_ID"

if [ ! -d "$MISSIONS_DIR" ]; then
  echo "Error: Mission directory $MISSIONS_DIR not found."
  exit 1
fi

# Handle suggested mode via classifier
if [ "$MODE" = "suggested" ]; then
  SUGGESTED_MODE="$(python3 "$SCRIPT_DIR/classifier.py" --prompt-file "$MISSIONS_DIR/desktop_prompt.md" 2>/dev/null | tail -n1)"
  MODE="${SUGGESTED_MODE:-confluence}"
  echo "--> Activating suggested mode: $MODE"
fi

case "$MODE" in
  confluence)
    echo "==> Spawning Confluence Spatial Cockpit in Kitty..."
    python3 "$SCRIPT_DIR/confluence.py" --run-id "$RUN_ID" --project "$PROJECT"
    ;;

  headless)
    echo "==> Launching Headless Turbo runners across mesh..."
    for pfile in "$MISSIONS_DIR"/*_prompt.md; do
      [ -f "$pfile" ] || continue
      node_id="$(basename "$pfile" | sed 's/_prompt.md//')"
      echo "  [•] Dispatching to $node_id (headless)..."
      
      if [ "$node_id" = "desktop" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(hostname -s)" ]; then
        systemd-run --user --unit="knot-council-$RUN_ID-$node_id" \
          agy --project "$PROJECT" --dangerously-skip-permissions -p "$(cat "$pfile")" --output-format json \
          > "$MISSIONS_DIR/${node_id}_output.json" 2>&1 &
      else
        # Push prompt file to target node and execute via systemd-run
        "$KNOT_ROOT/bin/knot" exec "$node_id" "mkdir -p ~/.config/knot/missions/$RUN_ID"
        cat "$pfile" | "$KNOT_ROOT/bin/knot" exec "$node_id" "cat > ~/.config/knot/missions/$RUN_ID/prompt.md"
        "$KNOT_ROOT/bin/knot" exec "$node_id" "systemd-run --user --unit=knot-council-$RUN_ID agy --project $PROJECT --dangerously-skip-permissions -p \"\$(cat ~/.config/knot/missions/$RUN_ID/prompt.md)\" --output-format json > ~/.config/knot/missions/$RUN_ID/output.json 2>&1 &"
      fi
    done
    echo "[✓] Fleet runners dispatched headlessly in background."
    ;;

  tui)
    echo "==> Launching Konsole TUI instances on each node display..."
    for pfile in "$MISSIONS_DIR"/*_prompt.md; do
      [ -f "$pfile" ] || continue
      node_id="$(basename "$pfile" | sed 's/_prompt.md//')"
      echo "  [•] Spawning Konsole on $node_id screen..."
      
      if [ "$node_id" = "desktop" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(hostname -s)" ]; then
        WAYLAND_DISPLAY=wayland-0 DISPLAY=:0 nohup konsole --hold -e agy --project "$PROJECT" --dangerously-skip-permissions -i "$(cat "$pfile")" >/dev/null 2>&1 &
      else
        # Push prompt and launch konsole on remote display
        "$KNOT_ROOT/bin/knot" exec "$node_id" "mkdir -p ~/.config/knot/missions/$RUN_ID"
        cat "$pfile" | "$KNOT_ROOT/bin/knot" exec "$node_id" "cat > ~/.config/knot/missions/$RUN_ID/prompt.md"
        
        uid="1000"
        if [ "$node_id" = "steamdeck" ]; then uid="1001"; fi
        "$KNOT_ROOT/bin/knot" exec "$node_id" "WAYLAND_DISPLAY=wayland-0 XDG_RUNTIME_DIR=/run/user/$uid nohup konsole --hold -e agy --project $PROJECT --dangerously-skip-permissions -i \"\$(cat ~/.config/knot/missions/$RUN_ID/prompt.md)\" >/dev/null 2>&1 &"
      fi
    done
    echo "[✓] Interactive TUI windows open on fleet displays."
    ;;

  gui)
    echo "==> Staging prompts for GUI delivery with anti-echo protection..."
    for pfile in "$MISSIONS_DIR"/*_prompt.md; do
      [ -f "$pfile" ] || continue
      node_id="$(basename "$pfile" | sed 's/_prompt.md//')"
      echo "  [•] Staging prompt on $node_id..."
      
      if [ "$node_id" = "desktop" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(hostname -s)" ]; then
        mkdir -p "$HOME/.config/knot/missions/staged"
        if command -v notify-send >/dev/null 2>&1; then
          notify-send -u normal "Knot Swarm Council" "Prompt staged for desktop. Run 'knot council copy' to load clipboard."
        fi
      else
        "$KNOT_ROOT/bin/knot" exec "$node_id" "mkdir -p ~/.config/knot/missions/staged"
        cat "$pfile" | "$KNOT_ROOT/bin/knot" exec "$node_id" "cat > ~/.config/knot/missions/staged/active_prompt.md"
        "$KNOT_ROOT/bin/knot" exec "$node_id" "if command -v notify-send >/dev/null 2>&1; then notify-send -u normal 'Knot Swarm Council' 'Prompt staged for $node_id. Run knot council copy to load clipboard.'; fi"
      fi
    done
    echo ""
    echo "=========================================================================="
    echo "  [✓] Prompts staged on all target nodes."
    echo "  Clipboard echoing prevented. To load a node's prompt into its local"
    echo "  clipboard for pasting into Antigravity 2.0 GUI, run:"
    echo "      knot council copy"
    echo "=========================================================================="
    ;;

  *)
    echo "Error: Unknown mode '$MODE'. Supported: confluence, headless, tui, gui, suggested"
    exit 1
    ;;
esac
