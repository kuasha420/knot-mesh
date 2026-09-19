#!/usr/bin/env bash
set -euo pipefail

# Knot Council Module
# Out-of-band multi-agent coordination protocol using GitHub Discussions

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

SKILL_DIR="$KNOT_ROOT/skills/swarm-council"
SCRIPTS_DIR="$SKILL_DIR/scripts"

council_clean() {
  local days="${1:-7}"
  local missions_dir="$HOME/.config/knot/missions"
  if [ -d "$missions_dir" ]; then
    find "$missions_dir" -mindepth 1 -maxdepth 1 -mtime "+$days" -exec rm -rf {} +
    knot_log_ok "Housekeeping complete: pruned council missions older than $days days."
  fi
}

council_copy() {
  local staged_file="$HOME/.config/knot/missions/staged/active_prompt.md"
  if [ ! -f "$staged_file" ]; then
    knot_log_err "No staged prompt found at $staged_file."
    echo "Staged prompts are created during 'knot council start --mode gui'."
    return 1
  fi

  if command -v wl-copy >/dev/null 2>&1; then
    wl-copy < "$staged_file"
    knot_log_ok "Tailored prompt copied to Wayland clipboard ($(wc -c < "$staged_file") bytes)."
    echo "You can now paste directly into Antigravity 2.0 (Ctrl+V)."
  elif command -v xclip >/dev/null 2>&1; then
    xclip -selection clipboard < "$staged_file"
    knot_log_ok "Tailored prompt copied to X11 clipboard."
  else
    knot_log_err "Neither wl-copy nor xclip found. Prompt location: $staged_file"
    return 1
  fi
}

council_start() {
  local mode="confluence"
  local pack="audit-parity"
  local prompt_text=""
  local prompt_file=""
  local nodes=""
  local dry_run=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --pack) pack="$2"; shift 2 ;;
      --prompt) prompt_text="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --nodes) nodes="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      -h|--help)
        echo "Usage: knot council start [options]"
        echo ""
        echo "Options:"
        echo "  --mode <mode>        Execution mode: confluence (default), headless, tui, gui, suggested"
        echo "  --pack <pack>        Scaffold pack: audit-parity (default), fast-triage"
        echo "  --prompt <text>      Base mission prompt text"
        echo "  --prompt-file <path> File containing base mission prompt"
        echo "  --nodes <list>       Comma-separated nodes (default: all online)"
        echo "  --dry-run            Scaffold prompts and session configs without launching"
        return 0
        ;;
      *)
        knot_log_err "Unknown option: $1"
        return 1
        ;;
    esac
  done

  # Run automated housekeeping first
  council_clean 7

  knot_log_info "Initiating Swarm Council mission..."
  echo -e "  Mode: ${C_CYAN}${mode}${C_RESET} | Pack: ${C_CYAN}${pack}${C_RESET}"

  # Stage 0: Audit tools
  echo -e "  ${C_CYAN}[0/7] Auditing tools and fleet availability...${C_RESET}"
  local audit_out
  audit_out="$(bash "$SCRIPTS_DIR/audit_tools.sh" 2>&1)" || {
    knot_log_err "Fleet audit failed:"
    echo "$audit_out"
    return 1
  }

  # Stage 1: Dynamic project sync
  echo -e "  ${C_CYAN}[1/7] Synchronizing Antigravity project mirrors...${C_RESET}"
  local sync_out
  sync_out="$(bash "$SCRIPTS_DIR/project_sync.sh" --pull 2>&1)" || {
    knot_log_err "Project sync failed:"
    echo "$sync_out"
    return 1
  }
  local proj_name
  proj_name="$(echo "$sync_out" | jq -r '.project_name // "knot-mesh"')"

  # Stage 2: Create GitHub Discussion thread
  echo -e "  ${C_CYAN}[2/7] Creating GitHub Discussion registry...${C_RESET}"
  local disc_res disc_id disc_url
  local run_id="run_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"

  if [ $dry_run -eq 0 ]; then
    local disc_body="## Knot Swarm Council Mission Registry

- **Run ID**: \`$run_id\`
- **Initiated**: $(date -u)
- **Project**: \`$proj_name\`
- **Pack**: \`$pack\`

All node checkpoints and final audit deliverables will be posted here."
    disc_res="$(python3 "$SCRIPTS_DIR/gh_discussion.py" create --title "Swarm Council Mission: $run_id" --body "$disc_body" 2>&1)" || {
      knot_log_err "Could not create discussion thread: $disc_res"
      return 1
    }
    disc_id="$(echo "$disc_res" | jq -r '.id')"
    disc_url="$(echo "$disc_res" | jq -r '.url')"
    echo -e "  Discussion thread created: ${C_GREEN}${disc_url}${C_RESET}"
  else
    disc_id="DRY_RUN_ID"
    disc_url="https://github.com/kuasha420/knot-mesh/discussions"
    echo -e "  ${C_YELLOW}[DRY RUN] Skipping discussion creation.${C_RESET}"
  fi

  # Stage 3: Scaffold prompts
  echo -e "  ${C_CYAN}[3/7] Scaffolding tailored node prompts (1.5x coverage)...${C_RESET}"
  local scaffold_cmd=(python3 "$SCRIPTS_DIR/scaffolder.py" --run-id "$run_id" --pack "$pack" --discussion-url "$disc_url")
  if [ -n "$prompt_file" ]; then scaffold_cmd+=(--prompt-file "$prompt_file"); fi
  if [ -n "$prompt_text" ]; then scaffold_cmd+=(--prompt "$prompt_text"); fi
  if [ -n "$nodes" ]; then scaffold_cmd+=(--nodes "$nodes"); fi
  if [ $dry_run -eq 1 ]; then scaffold_cmd+=(--dry-run); fi

  local scaffold_res
  scaffold_res="$("${scaffold_cmd[@]}")"
  if command -v jq >/dev/null 2>&1; then
    local cov_msg
    cov_msg="$(echo "$scaffold_res" | jq -r '.actual_coverage | "  Coverage ratio achieved: \(.)x"')"
    echo "$cov_msg"
  fi

  # Save run metadata
  local missions_dir="$HOME/.config/knot/missions/$run_id"
  mkdir -p "$missions_dir"
  echo "{\"run_id\":\"$run_id\",\"disc_id\":\"$disc_id\",\"disc_url\":\"$disc_url\",\"mode\":\"$mode\",\"project\":\"$proj_name\"}" > "$missions_dir/meta.json"

  if [ $dry_run -eq 1 ]; then
    knot_log_ok "Dry run completed successfully for $run_id."
    return 0
  fi

  # Stage 4 & 5: Mode selection and delivery
  echo -e "  ${C_CYAN}[4-5/7] Delivering prompts via mode: ${C_BOLD}${mode}${C_RESET}..."
  bash "$SCRIPTS_DIR/deliver.sh" "$mode" "$run_id" "$proj_name"

  echo ""
  knot_log_ok "Swarm Council mission $run_id successfully launched!"
  echo -e "  Discussion: ${C_CYAN}$disc_url${C_RESET}"
  echo -e "  Status:     ${C_YELLOW}knot council status $run_id${C_RESET}"
  echo -e "  Attach:     ${C_YELLOW}knot council attach <node_id> $run_id${C_RESET}"
  echo -e "  Reconcile:  ${C_YELLOW}knot council reconcile $run_id${C_RESET}"
}

council_status() {
  local run_id="${1:-}"
  local missions_dir="$HOME/.config/knot/missions"

  if [ -z "$run_id" ]; then
    local latest=""
    if compgen -G "$missions_dir/run_*" >/dev/null; then
      latest="$(ls -td "$missions_dir"/run_* | head -n1)"
    fi
    if [ -n "$latest" ]; then
      run_id="$(basename "$latest")"
    else
      knot_log_err "No council missions found."
      return 1
    fi
  fi

  local meta_file="$missions_dir/$run_id/meta.json"
  if [ ! -f "$meta_file" ]; then
    knot_log_err "Mission metadata for $run_id not found."
    return 1
  fi

  local disc_id disc_url
  disc_id="$(jq -r '.disc_id' "$meta_file")"
  disc_url="$(jq -r '.disc_url' "$meta_file")"

  echo -e "${C_BOLD}--- Swarm Council Mission Status: $run_id ---${C_RESET}"
  echo -e "Discussion: ${C_CYAN}$disc_url${C_RESET}"
  echo ""

  python3 "$SCRIPTS_DIR/reconcile.py" --discussion-id "$disc_id" --run-id "$run_id"
}

council_attach() {
  local node_id="${1:-}"
  local run_id="${2:-}"

  if [ -z "$node_id" ]; then
    echo "Usage: knot council attach <node_id> [run_id]"
    return 1
  fi

  knot_log_info "Connecting to active agent session on node '$node_id'..."
  if [ "$node_id" = "desktop" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(hostname -s)" ]; then
    agy -c
  else
    "$KNOT_ROOT/bin/knot" exec "$node_id" -tt "agy -c"
  fi
}

council_reconcile() {
  local run_id="${1:-}"
  local missions_dir="$HOME/.config/knot/missions"

  if [ -z "$run_id" ]; then
    local latest=""
    if compgen -G "$missions_dir/run_*" >/dev/null; then
      latest="$(ls -td "$missions_dir"/run_* | head -n1)"
    fi
    if [ -n "$latest" ]; then
      run_id="$(basename "$latest")"
    else
      knot_log_err "No council missions found."
      return 1
    fi
  fi

  local meta_file="$missions_dir/$run_id/meta.json"
  if [ ! -f "$meta_file" ]; then
    knot_log_err "Mission metadata for $run_id not found."
    return 1
  fi

  local disc_id
  disc_id="$(jq -r '.disc_id' "$meta_file")"
  local out_file="$missions_dir/$run_id/reconciled_report.md"

  python3 "$SCRIPTS_DIR/reconcile.py" --discussion-id "$disc_id" --run-id "$run_id" --out-file "$out_file"
  cat "$out_file"
}

council_kill() {
  local run_id="${1:-}"
  if [ -z "$run_id" ]; then
    echo "Usage: knot council kill <run_id>"
    return 1
  fi

  knot_log_info "Stopping council processes for $run_id..."
  if pgrep -f "knot-council-$run_id" >/dev/null 2>&1; then
    pkill -f "knot-council-$run_id"
  fi
  if pgrep -f "$run_id.*kitty" >/dev/null 2>&1; then
    pkill -f "$run_id.*kitty"
  fi
  "$KNOT_ROOT/bin/knot" exec --all "if pgrep -f knot-council-$run_id >/dev/null 2>&1; then pkill -f knot-council-$run_id; fi"
  knot_log_ok "Council run $run_id halted across fleet."
}
