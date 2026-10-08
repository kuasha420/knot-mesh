#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 5 Multi-Mode Prompt Deliverance Engine
# Handles confluence, headless, tui, gui, and suggested execution modes

MODE="${1:-confluence}"
RUN_ID="${2:-}"
PROJECT="${3:-knot-mesh}"
TILING="${4:-grid}"
INTERACTIVE="${5:-0}"
NODES="${6:-}"
RESUME="${7:-0}"
LAUNCH="${LAUNCH:-${8:-1}}"

if [ -z "$RUN_ID" ]; then
  echo "Usage: $0 <confluence|headless|tui|gui|suggested> <run_id> [project_name] [tiling] [interactive] [nodes] [resume] [launch]"
  exit 1
fi

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KNOT_ROOT="${KNOT_ROOT:-$(cd -P "$SCRIPT_DIR/../../../.." && pwd -P)}"
KNOT_BIN=""
if [ -x "$KNOT_ROOT/bin/knot" ]; then
  KNOT_BIN="$KNOT_ROOT/bin/knot"
elif command -v knot >/dev/null; then
  KNOT_BIN="$(command -v knot)"
elif [ -x "$HOME/.local/bin/knot" ]; then
  KNOT_BIN="$HOME/.local/bin/knot"
fi
MISSIONS_DIR="$HOME/.config/knot/missions/$RUN_ID"
LOCAL_NODE="$(python3 "$SCRIPT_DIR/resolve_node.py")"
LOCAL_HOST="$(uname -n | cut -d. -f1)"

if [ ! -d "$MISSIONS_DIR" ]; then
  echo "Error: Mission directory $MISSIONS_DIR not found."
  exit 1
fi

# Handle suggested mode via classifier
if [ "$MODE" = "suggested" ]; then
  SUGGESTED_MODE="$(python3 "$SCRIPT_DIR/classifier.py" --prompt-file "$MISSIONS_DIR/desktop_prompt.md" | tail -n1)"
  MODE="${SUGGESTED_MODE:-confluence}"
  echo "--> Activating suggested mode: $MODE"
fi

# Stage prompt files and launchers across mesh for non-interactive missions
if [ "$INTERACTIVE" != "1" ] && [ "$INTERACTIVE" != "true" ]; then
  echo "==> Staging prompt files and launchers across mesh..."
  pack=""
  opening_node=""
  auth_profile=""
  if [ -f "$MISSIONS_DIR/meta.json" ]; then
    pack="$(jq -r '.pack // ""' "$MISSIONS_DIR/meta.json")"
    opening_node="$(jq -r '.opening_node // .ring[0] // ""' "$MISSIONS_DIR/meta.json")"
    auth_profile="$(jq -r '.auth_profile // empty' "$MISSIONS_DIR/meta.json")"
  fi
  if [ -z "$opening_node" ]; then
    opening_node="$LOCAL_NODE"
  fi

  resolved_hub="${KNOT_HUB_URL:-}"
  if [ -z "$resolved_hub" ] && command -v hub_resolve_url >/dev/null; then
    r_hub=""
    if r_hub="$(hub_resolve_url 2>&1)"; then
      resolved_hub="$r_hub"
    fi
  fi
  if [ -z "$resolved_hub" ]; then
    resolved_hub="https://desktop:4242"
  fi

  anchor_node="desktop"
  if command -v knot_get_active_swarm >/dev/null; then
    active_swarm=""
    active_swarm="$(knot_get_active_swarm)"
    if command -v knot_load_swarm_profile >/dev/null && knot_load_swarm_profile "$active_swarm"; then
      anchor_node="${ANCHOR_ID:-${ANCHOR_HOST:-desktop}}"
    fi
  fi

  for pfile in "$MISSIONS_DIR"/*_prompt.md; do
    [ -f "$pfile" ] || continue
    node_id="$(basename "$pfile" | sed 's/_prompt.md//')"
    
    launcher_script="$MISSIONS_DIR/${node_id}_launch.sh"
    if [ "$pack" = "tournament" ] && [ "$node_id" != "$opening_node" ]; then
      cat << 'EOF_LAUNCH' > "$launcher_script"
#!/usr/bin/env bash
trap '' HUP
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"
export KNOT_NODE_ID="NODE_ID_PLACEHOLDER"
export KNOT_RUN_ID="RUN_ID_PLACEHOLDER"
export KNOT_COUNCIL_RUN_ID="RUN_ID_PLACEHOLDER"
export KNOT_HUB_URL="HUB_URL_PLACEHOLDER"
export KNOT_MESH_ANCHOR="ANCHOR_PLACEHOLDER"
AUTH_PROFILE_PLACEHOLDER
PROJECT_NAME="PROJECT_PLACEHOLDER"

PROJECT_DIR="$(python3 -c '
import sys, os, glob, json
home = os.path.expanduser("~")
pname = sys.argv[1].lower() if len(sys.argv) > 1 else ""
pdir = os.path.join(home, ".gemini/config/projects")
res = ""
if os.path.isdir(pdir):
    for f in glob.glob(os.path.join(pdir, "*.json")):
        try:
            with open(f) as jf:
                d = json.load(jf)
            if d.get("name", "").lower() == pname or d.get("id", "").lower() == pname:
                for r in d.get("projectResources", {}).get("resources", []):
                    u = r.get("gitFolder", {}).get("folderUri", "")
                    if u.startswith("file://"):
                        p = u[7:].rstrip("/")
                        if os.path.isdir(p):
                            res = p; break
                        b = os.path.basename(p)
                        for c in [os.path.join(home, "Dev", b), os.path.join(home, b), os.path.join(home, ".local/share", b)]:
                            if os.path.isdir(c):
                                res = c; break
                if res: break
        except Exception: pass
if not res and pname and pname not in (".", "./"):
    for c in [os.path.join(home, "Dev", pname), os.path.join(home, pname), os.path.join(home, ".local/share", pname)]:
        if os.path.isdir(c):
            res = c; break
print(res or os.getcwd())
' "$PROJECT_NAME")"

if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR"
fi
echo -e "\033[1;36m╔══════════════════════════════════════════════════════════════════════╗\033[0m"
echo -e "\033[1;36m║\033[0m  🛰️  \033[1mKnot Swarm Tournament Rally Player: @[NODE_ID_PLACEHOLDER]\033[0m"
echo -e "\033[1;36m║\033[0m  Project:   \033[33mPROJECT_PLACEHOLDER\033[0m"
echo -e "\033[1;36m║\033[0m  Registry:  \033[35mknot://mesh/council/RUN_ID_PLACEHOLDER\033[0m"
echo -e "\033[1;36m║\033[0m  Mode:      \033[32mZero-Token Standby (Awaiting challenge volley)\033[0m"
echo -e "\033[1;36m║\033[0m  Commands:  \033[32mknot council reply\033[0m | \033[32mknot council steer\033[0m"
echo -e "\033[1;36m╚══════════════════════════════════════════════════════════════════════╝\033[0m"
echo ""
if [ -n "${KNOT_HUB_URL:-}" ] && command -v curl >/dev/null; then
  curl -k -sS -o /dev/null -X POST "$KNOT_HUB_URL/strand/event" -H "Content-Type: application/json" -d "{\"run_id\":\"RUN_ID_PLACEHOLDER\",\"node_id\":\"NODE_ID_PLACEHOLDER\",\"event\":\"TURN_START\",\"details\":{\"mode\":\"standby\"}}" 2>&1 || echo "Notice: event bus report error" >&2
fi
exec agy --project "$PROJECT_NAME" --dangerously-skip-permissions
EOF_LAUNCH
    else
      cat << 'EOF_LAUNCH' > "$launcher_script"
#!/usr/bin/env bash
trap '' HUP
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:$PATH"
export KNOT_NODE_ID="NODE_ID_PLACEHOLDER"
export KNOT_RUN_ID="RUN_ID_PLACEHOLDER"
export KNOT_COUNCIL_RUN_ID="RUN_ID_PLACEHOLDER"
export KNOT_HUB_URL="HUB_URL_PLACEHOLDER"
export KNOT_MESH_ANCHOR="ANCHOR_PLACEHOLDER"
AUTH_PROFILE_PLACEHOLDER
PROMPT_FILE="$HOME/.config/knot/missions/RUN_ID_PLACEHOLDER/prompt.md"
PROJECT_NAME="PROJECT_PLACEHOLDER"

PROJECT_DIR="$(python3 -c '
import sys, os, glob, json
home = os.path.expanduser("~")
pname = sys.argv[1].lower() if len(sys.argv) > 1 else ""
pdir = os.path.join(home, ".gemini/config/projects")
res = ""
if os.path.isdir(pdir):
    for f in glob.glob(os.path.join(pdir, "*.json")):
        try:
            with open(f) as jf:
                d = json.load(jf)
            if d.get("name", "").lower() == pname or d.get("id", "").lower() == pname:
                for r in d.get("projectResources", {}).get("resources", []):
                    u = r.get("gitFolder", {}).get("folderUri", "")
                    if u.startswith("file://"):
                        p = u[7:].rstrip("/")
                        if os.path.isdir(p):
                            res = p; break
                        b = os.path.basename(p)
                        for c in [os.path.join(home, "Dev", b), os.path.join(home, b), os.path.join(home, ".local/share", b)]:
                            if os.path.isdir(c):
                                res = c; break
                if res: break
        except Exception: pass
if not res and pname and pname not in (".", "./"):
    for c in [os.path.join(home, "Dev", pname), os.path.join(home, pname), os.path.join(home, ".local/share", pname)]:
        if os.path.isdir(c):
            res = c; break
print(res or os.getcwd())
' "$PROJECT_NAME")"

if [ -d "$PROJECT_DIR" ]; then
  cd "$PROJECT_DIR"
fi

if [ -n "${KNOT_HUB_URL:-}" ] && command -v curl >/dev/null; then
  curl -k -sS -o /dev/null -X POST "$KNOT_HUB_URL/strand/event" -H "Content-Type: application/json" -d "{\"run_id\":\"RUN_ID_PLACEHOLDER\",\"node_id\":\"NODE_ID_PLACEHOLDER\",\"event\":\"TURN_START\",\"details\":{\"mode\":\"mission\"}}" 2>&1 || echo "Notice: event bus report error" >&2
fi

if [ "${1:-}" = "--headless" ] || [ "${1:-}" = "-p" ]; then
  exec agy --project "$PROJECT_NAME" --dangerously-skip-permissions -p "$(< "$PROMPT_FILE")" --output-format json
else
  exec agy --project "$PROJECT_NAME" --dangerously-skip-permissions -i "$(< "$PROMPT_FILE")"
fi
EOF_LAUNCH
    fi
    sed -i "s|RUN_ID_PLACEHOLDER|$RUN_ID|g" "$launcher_script"
    sed -i "s|PROJECT_PLACEHOLDER|$PROJECT|g" "$launcher_script"
    sed -i "s|NODE_ID_PLACEHOLDER|$node_id|g" "$launcher_script"
    sed -i "s|HUB_URL_PLACEHOLDER|$resolved_hub|g" "$launcher_script"
    sed -i "s|ANCHOR_PLACEHOLDER|$anchor_node|g" "$launcher_script"
    if [ -n "$auth_profile" ]; then
      sed -i "s|AUTH_PROFILE_PLACEHOLDER|export KNOT_AUTH_PROFILE=\"$auth_profile\"|g" "$launcher_script"
    else
      sed -i "/AUTH_PROFILE_PLACEHOLDER/d" "$launcher_script"
    fi
    chmod +x "$launcher_script"

    if [ "$node_id" = "$LOCAL_NODE" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$LOCAL_HOST" ]; then
      cp "$pfile" "$MISSIONS_DIR/prompt.md"
      cp "$launcher_script" "$MISSIONS_DIR/launch.sh"
    else
      if [ ! -f "$MISSIONS_DIR/launch.sh" ]; then
        cp "$pfile" "$MISSIONS_DIR/prompt.md"
        cp "$launcher_script" "$MISSIONS_DIR/launch.sh"
      fi
      if [ "$LAUNCH" -eq 1 ]; then
        "$KNOT_BIN" exec "$node_id" "mkdir -p ~/.config/knot/missions/$RUN_ID"
        cat "$pfile" | "$KNOT_BIN" exec "$node_id" "cat > ~/.config/knot/missions/$RUN_ID/prompt.md"
        cat "$launcher_script" | "$KNOT_BIN" exec "$node_id" "cat > ~/.config/knot/missions/$RUN_ID/launch.sh && chmod +x ~/.config/knot/missions/$RUN_ID/launch.sh"
      fi
    fi
  done
fi

case "$MODE" in
  confluence)
    if [ "$INTERACTIVE" = "1" ] || [ "$INTERACTIVE" = "true" ]; then
      if [ "$RESUME" = "1" ] || [ "$RESUME" = "true" ]; then
        echo "==> Resuming Interactive Confluence Spatial Cockpit in Kitty..."
        local_conf_cmd=(python3 "$SCRIPT_DIR/confluence.py" --run-id "$RUN_ID" --project "$PROJECT" --tiling "$TILING" --interactive --resume)
      else
        echo "==> Spawning Zero-Token Interactive Confluence Cockpit in Kitty..."
        local_conf_cmd=(python3 "$SCRIPT_DIR/confluence.py" --run-id "$RUN_ID" --project "$PROJECT" --tiling "$TILING" --interactive)
      fi
      if [ -n "$NODES" ]; then
        local_conf_cmd+=(--nodes "$NODES")
      fi
      "${local_conf_cmd[@]}"
    elif [ "$LAUNCH" -eq 1 ]; then
      echo "==> Spawning Confluence Spatial Cockpit in Kitty..."
      ACTIVE_NODES="$(python3 -c 'import glob, os, sys, re; p=glob.glob(os.path.join(sys.argv[1], "*_prompt.md")); print(",".join(re.sub(r"_prompt\.md$", "", os.path.basename(x)) for x in p))' "$MISSIONS_DIR")"
      local_conf_cmd=(python3 "$SCRIPT_DIR/confluence.py" --run-id "$RUN_ID" --project "$PROJECT" --tiling "$TILING")
      if [ -n "$ACTIVE_NODES" ]; then
        local_conf_cmd+=(--nodes "$ACTIVE_NODES")
      elif [ -n "$NODES" ]; then
        local_conf_cmd+=(--nodes "$NODES")
      fi
      "${local_conf_cmd[@]}"
    else
      echo "==> Staging complete for Confluence mode (launch=0)."
    fi
    ;;

  headless)
    echo "==> Launching Headless Turbo runners across mesh..."
    for pfile in "$MISSIONS_DIR"/*_prompt.md; do
      [ -f "$pfile" ] || continue
      node_id="$(basename "$pfile" | sed 's/_prompt.md//')"
      echo "  [•] Dispatching to $node_id (headless)..."

      if [ "$node_id" = "$LOCAL_NODE" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$LOCAL_HOST" ]; then
        systemd-run --user --unit="knot-council-$RUN_ID-$node_id" \
          bash "$MISSIONS_DIR/${node_id}_launch.sh" --headless \
          > "$MISSIONS_DIR/${node_id}_output.json" 2>&1 &
      else
        "$KNOT_BIN" exec "$node_id" "systemd-run --user --unit=knot-council-$RUN_ID bash ~/.config/knot/missions/$RUN_ID/launch.sh --headless > ~/.config/knot/missions/$RUN_ID/output.json 2>&1 &"
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

      if [ "$node_id" = "$LOCAL_NODE" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$LOCAL_HOST" ]; then
        w_disp="${WAYLAND_DISPLAY:-}"
        xdg_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
        if [ -z "$w_disp" ] && [ -d "$xdg_dir" ]; then
          for cand in "$xdg_dir"/wayland-*; do
            if [ -S "$cand" ]; then
              w_disp="$(basename "$cand")"
              break
            fi
          done
        fi
        w_disp="${w_disp:-wayland-0}"
        mkdir -p "$MISSIONS_DIR/logs"
        WAYLAND_DISPLAY="$w_disp" DISPLAY="${DISPLAY:-:0}" nohup konsole --hold -e "$MISSIONS_DIR/${node_id}_launch.sh" > "$MISSIONS_DIR/logs/konsole_$node_id.log" 2>&1 &
      else
        "$KNOT_BIN" exec "$node_id" "mkdir -p ~/.config/knot/missions/$RUN_ID/logs && XDG_DIR=\"/run/user/\$(id -u)\"; W_DISP=\"\"; for s in \"\$XDG_DIR\"/wayland-*; do if [ -S \"\$s\" ]; then W_DISP=\"\$(basename \"\$s\")\"; break; fi; done; if [ -z \"\$W_DISP\" ]; then W_DISP=\"\${WAYLAND_DISPLAY:-wayland-0}\"; fi; WAYLAND_DISPLAY=\"\$W_DISP\" DISPLAY=\"\${DISPLAY:-:0}\" XDG_RUNTIME_DIR=\"\$XDG_DIR\" nohup konsole --hold -e ~/.config/knot/missions/$RUN_ID/launch.sh > ~/.config/knot/missions/$RUN_ID/logs/konsole.log 2>&1 &"
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
      
      if [ "$node_id" = "$LOCAL_NODE" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$LOCAL_HOST" ]; then
        mkdir -p "$HOME/.config/knot/missions/staged"
        if command -v notify-send >/dev/null; then
          notify-send -u normal "Knot Swarm Council" "Prompt staged for $node_id. Run 'knot council copy' to load clipboard."
        fi
      else
        "$KNOT_BIN" exec "$node_id" "mkdir -p ~/.config/knot/missions/staged"
        cat "$pfile" | "$KNOT_BIN" exec "$node_id" "cat > ~/.config/knot/missions/staged/active_prompt.md"
        "$KNOT_BIN" exec "$node_id" "if command -v notify-send >/dev/null; then notify-send -u normal 'Knot Swarm Council' 'Prompt staged for $node_id. Run knot council copy to load clipboard.'; fi"
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
