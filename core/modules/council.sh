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
  local proj_override=""
  local db="ghd"
  local interactive=0
  local resume=0
  local resume_id=""
  local tiling="grid"
  local dry_run=0

  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) mode="$2"; shift 2 ;;
      --pack) pack="$2"; shift 2 ;;
      --prompt) prompt_text="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --nodes) nodes="$2"; shift 2 ;;
      --project) proj_override="$2"; shift 2 ;;
      --db) db="$2"; shift 2 ;;
      --interactive) interactive=1; shift ;;
      --resume)
        resume=1
        if [ $# -ge 2 ] && [[ "$2" != --* ]]; then
          resume_id="$2"
          shift 2
        else
          shift 1
        fi
        ;;
      --tiling) tiling="$2"; shift 2 ;;
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
        echo "  --project <name>     Target project name (default: auto-detected)"
        echo "  --db <ghd|mesh>      Registry backend: ghd (GitHub Discussions, default) or mesh (Mesh DB)"
        echo "  --interactive        Launch zero-token Confluence cockpit with all nodes connected in agy standby"
        echo "  --resume [run_id]    Resume active or specified interactive council session"
        echo "  --tiling <layout>    Cockpit layout: grid (default), sidebyside, splits, tall, fat, stacked"
        echo "  --dry-run            Scaffold prompts and session configs without launching"
        return 0
        ;;
      *)
        knot_log_err "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [ $resume -eq 1 ]; then
    council_resume "$resume_id"
    return $?
  fi

  # Run automated housekeeping first
  council_clean 7

  if [ $interactive -eq 1 ]; then
    mode="confluence"
    if [ "$db" = "ghd" ]; then
      db="mesh"
    fi
    knot_log_info "Initiating Zero-Token Interactive Swarm Council Cockpit..."
    echo -e "  Backend: ${C_CYAN}${db}${C_RESET} | Tiling: ${C_CYAN}${tiling}${C_RESET}"
  else
    knot_log_info "Initiating Swarm Council mission..."
    echo -e "  Mode: ${C_CYAN}${mode}${C_RESET} | Pack: ${C_CYAN}${pack}${C_RESET} | Backend: ${C_CYAN}${db}${C_RESET} | Tiling: ${C_CYAN}${tiling}${C_RESET}"
  fi

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
  local proj_name proj_folder
  if [ -n "$proj_override" ]; then
    proj_name="$proj_override"
  else
    proj_name="$(echo "$sync_out" | jq -r '.project_name // "knot-mesh"')"
  fi
  proj_folder="$(echo "$sync_out" | jq -r '.folders[0] // empty')"
  if [ -z "$proj_folder" ] || [ ! -d "$proj_folder" ]; then
    proj_folder="$(pwd)"
  fi

  # Stage 2: Create Mission registry thread
  local disc_res disc_id disc_url
  local run_id="run_$(date +%Y%m%d_%H%M%S)_$(head -c 4 /dev/urandom | xxd -p)"

  if [ "$db" = "mesh" ]; then
    echo -e "  ${C_CYAN}[2/7] Creating Mesh DB registry thread...${C_RESET}"
    if [ $dry_run -eq 0 ]; then
      local disc_body="## Knot Swarm Council Mission Registry (Mesh DB)

- **Run ID**: \`$run_id\`
- **Initiated**: $(date -u)
- **Project**: \`$proj_name\`
- **Pack**: \`$pack\`
- **Interactive**: $([ $interactive -eq 1 ] && echo "Yes" || echo "No")

All node checkpoints and audit deliverables will be posted here."
      disc_res="$(python3 "$SCRIPTS_DIR/mesh_db.py" create --title "Swarm Council Mission: $run_id" --body "$disc_body" --run-id "$run_id" 2>&1)" || {
        knot_log_err "Could not create mesh db registry: $disc_res"
        return 1
      }
      disc_id="$(echo "$disc_res" | jq -r '.id')"
      disc_url="$(echo "$disc_res" | jq -r '.url')"
      echo -e "  Mesh registry thread created: ${C_GREEN}${disc_url}${C_RESET}"
    else
      disc_id="$run_id"
      disc_url="knot://mesh/council/$run_id"
      echo -e "  ${C_YELLOW}[DRY RUN] Skipping mesh db thread creation.${C_RESET}"
    fi
  else
    echo -e "  ${C_CYAN}[2/7] Creating GitHub Discussion registry...${C_RESET}"
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
  fi

  # Stage 3: Scaffold prompts (if not interactive)
  if [ $interactive -eq 0 ]; then
    echo -e "  ${C_CYAN}[3/7] Scaffolding tailored node prompts (1.5x coverage)...${C_RESET}"
    local scaffold_cmd=(python3 "$SCRIPTS_DIR/scaffolder.py" --run-id "$run_id" --pack "$pack" --discussion-url "$disc_url" --db "$db" --project-dir "$proj_folder")
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
  else
    echo -e "  ${C_CYAN}[3/7] Interactive mode: Zero-Token standby (prompts on-demand via steering).${C_RESET}"
  fi

  # Save run metadata
  local missions_dir="$HOME/.config/knot/missions/$run_id"
  mkdir -p "$missions_dir"
  echo "{\"run_id\":\"$run_id\",\"disc_id\":\"$disc_id\",\"disc_url\":\"$disc_url\",\"mode\":\"$mode\",\"project\":\"$proj_name\",\"db\":\"$db\",\"tiling\":\"$tiling\",\"interactive\":$interactive,\"nodes\":\"$nodes\",\"status\":\"ACTIVE\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$missions_dir/meta.json"

  if [ $dry_run -eq 1 ]; then
    if [ $interactive -eq 1 ]; then
      local dry_conf_cmd=(python3 "$SCRIPTS_DIR/confluence.py" --run-id "$run_id" --project "$proj_name" --tiling "$tiling" --interactive --dry-run)
      if [ -n "$nodes" ]; then dry_conf_cmd+=(--nodes "$nodes"); fi
      "${dry_conf_cmd[@]}"
    fi
    knot_log_ok "Dry run completed successfully for $run_id."
    return 0
  fi

  # Stage 4 & 5: Mode selection and delivery
  if [ $interactive -eq 1 ]; then
    echo -e "  ${C_CYAN}[4-5/7] Spawning zero-token interactive spatial cockpit (tiling: ${C_BOLD}${tiling}${C_RESET})..."
  else
    echo -e "  ${C_CYAN}[4-5/7] Delivering prompts via mode: ${C_BOLD}${mode}${C_RESET} (tiling: ${C_BOLD}${tiling}${C_RESET})..."
  fi
  bash "$SCRIPTS_DIR/deliver.sh" "$mode" "$run_id" "$proj_name" "$tiling" "$interactive" "$nodes" "$resume"

  echo ""
  if [ $interactive -eq 1 ]; then
    knot_log_ok "Zero-Token Interactive Swarm Cockpit session $run_id launched!"
  else
    knot_log_ok "Swarm Council mission $run_id successfully launched!"
  fi
  echo -e "  Registry:   ${C_CYAN}$disc_url${C_RESET}"
  echo -e "  Reply:      ${C_YELLOW}knot council reply $run_id --status <status> --body <text>${C_RESET}"
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

  local disc_id disc_url db_type
  disc_id="$(jq -r '.disc_id' "$meta_file")"
  disc_url="$(jq -r '.disc_url' "$meta_file")"
  db_type="$(jq -r '.db // "auto"' "$meta_file")"

  echo -e "${C_BOLD}--- Swarm Council Mission Status: $run_id ---${C_RESET}"
  echo -e "Registry:   ${C_CYAN}$disc_url${C_RESET}"
  echo -e "Backend:    ${C_YELLOW}$db_type${C_RESET}"
  echo ""

  python3 "$SCRIPTS_DIR/reconcile.py" --discussion-id "$disc_id" --run-id "$run_id" --db-backend "$db_type"
}

council_reply() {
  local run_id="${1:-}"
  if [ -z "$run_id" ]; then
    echo "Usage: knot council reply <run_id> [--node <id>] [--status <status>] [--body <text>]"
    return 1
  fi
  shift

  local node="$(hostname -s)"
  if [ -n "${KNOT_NODE_ID:-}" ]; then node="$KNOT_NODE_ID"; fi
  local status="PROGRESS"
  local body=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --node) node="$2"; shift 2 ;;
      --status) status="$2"; shift 2 ;;
      --body) body="$2"; shift 2 ;;
      *)
        knot_log_err "Unknown option: $1"
        return 1
        ;;
    esac
  done

  if [ -z "$body" ]; then
    if [ ! -t 0 ]; then
      body="$(cat)"
    else
      knot_log_err "Message body required via --body or stdin."
      return 1
    fi
  fi

  local missions_dir="$HOME/.config/knot/missions"
  local meta_file="$missions_dir/$run_id/meta.json"
  local db_type="mesh"
  local disc_id="$run_id"

  if [ -f "$meta_file" ]; then
    db_type="$(jq -r '.db // "mesh"' "$meta_file")"
    disc_id="$(jq -r '.disc_id // ""' "$meta_file")"
    if [ -z "$disc_id" ]; then disc_id="$run_id"; fi
  fi

  if [ "$db_type" = "mesh" ]; then
    python3 "$SCRIPTS_DIR/mesh_db.py" reply --discussion-id "$disc_id" --run-id "$run_id" --node-id "$node" --status "$status" --body "$body"
  else
    python3 "$SCRIPTS_DIR/gh_discussion.py" reply --discussion-id "$disc_id" --run-id "$run_id" --node-id "$node" --status "$status" --body "$body"
  fi
  knot_log_ok "Reply posted for node '$node' (Status: $status) to mission $run_id"
}

council_list() {
  local filter="${1:-}"
  echo -e "${C_BOLD}--- Knot Swarm Council Missions ---${C_RESET}"
  local missions_dir="$HOME/.config/knot/missions"
  if [ -d "$missions_dir" ]; then
    local count=0
    for m in $(ls -td "$missions_dir"/run_* 2>/dev/null); do
      local rid
      rid="$(basename "$m")"
      local m_meta="$m/meta.json"
      local m_db="mesh"
      local m_mode="confluence"
      local m_proj="knot-mesh"
      local m_interactive=0
      local m_status="ACTIVE"
      local m_tiling="grid"
      local m_nodes=""
      if [ -f "$m_meta" ]; then
        m_db="$(jq -r '.db // "mesh"' "$m_meta")"
        m_mode="$(jq -r '.mode // "confluence"' "$m_meta")"
        m_proj="$(jq -r '.project // "knot-mesh"' "$m_meta")"
        m_interactive="$(jq -r '.interactive // 0' "$m_meta")"
        m_status="$(jq -r '.status // "ACTIVE"' "$m_meta")"
        m_tiling="$(jq -r '.tiling // "grid"' "$m_meta")"
        m_nodes="$(jq -r '.nodes // ""' "$m_meta")"
      fi

      if [ -n "$filter" ]; then
        if [ "$filter" = "interactive" ] && [ "$m_interactive" != "1" ] && [ "$m_interactive" != "true" ]; then
          continue
        elif [ "$filter" = "mesh" ] || [ "$filter" = "ghd" ]; then
          if [ "$filter" != "$m_db" ]; then continue; fi
        elif [ "$filter" = "active" ] && [ "$m_status" != "ACTIVE" ]; then
          continue
        fi
      fi

      local type_tag
      if [ "$m_interactive" = "1" ] || [ "$m_interactive" = "true" ]; then
        type_tag="${C_GREEN}[INTERACTIVE | ${m_status}]${C_RESET}"
      else
        type_tag="${C_BLUE}[AUTONOMOUS | ${m_status}]${C_RESET}"
      fi

      local node_tag=""
      if [ -n "$m_nodes" ]; then
        node_tag=" | nodes: $m_nodes"
      fi

      echo -e "  • ${C_CYAN}$rid${C_RESET} $type_tag [backend: ${C_YELLOW}$m_db${C_RESET} | mode: $m_mode | tiling: $m_tiling | project: $m_proj$node_tag]"
      count=$((count + 1))
      if [ $count -ge 20 ]; then break; fi
    done
    if [ $count -eq 0 ]; then
      echo "  (No matching council missions found)"
    fi
  fi
}

council_resume() {
  local run_id="${1:-}"
  local missions_dir="$HOME/.config/knot/missions"

  if [ -z "$run_id" ]; then
    local latest=""
    if [ -d "$missions_dir" ]; then
      for m in $(ls -td "$missions_dir"/run_* 2>/dev/null); do
        if [ -f "$m/meta.json" ]; then
          latest="$(basename "$m")"
          break
        fi
      done
    fi
    if [ -n "$latest" ]; then
      run_id="$latest"
    else
      knot_log_err "No council missions found to resume."
      return 1
    fi
  fi

  local meta_file="$missions_dir/$run_id/meta.json"
  if [ ! -f "$meta_file" ]; then
    knot_log_err "Mission metadata for $run_id not found at $meta_file."
    return 1
  fi

  local proj_name tiling nodes db
  proj_name="$(jq -r '.project // "knot-mesh"' "$meta_file")"
  tiling="$(jq -r '.tiling // "grid"' "$meta_file")"
  nodes="$(jq -r '.nodes // ""' "$meta_file")"
  db="$(jq -r '.db // "mesh"' "$meta_file")"

  knot_log_info "Resuming Swarm Council interactive session: $run_id"
  echo -e "  Project: ${C_CYAN}$proj_name${C_RESET} | Tiling: ${C_CYAN}$tiling${C_RESET} | Backend: ${C_CYAN}$db${C_RESET}"

  local conf_cmd=(python3 "$SCRIPTS_DIR/confluence.py" --run-id "$run_id" --project "$proj_name" --tiling "$tiling" --interactive --resume)
  if [ -n "$nodes" ]; then
    conf_cmd+=(--nodes "$nodes")
  fi
  "${conf_cmd[@]}"
}

council_attach() {
  local node_id="${1:-}"
  local run_id="${2:-}"

  if [ -z "$node_id" ]; then
    echo "Usage: knot council attach <node_id> [run_id]"
    return 1
  fi

  local missions_dir="$HOME/.config/knot/missions"
  local m_db="mesh"
  local m_proj="knot-mesh"
  if [ -n "$run_id" ] && [ -f "$missions_dir/$run_id/meta.json" ]; then
    m_db="$(jq -r '.db // "mesh"' "$missions_dir/$run_id/meta.json")"
    m_proj="$(jq -r '.project // "knot-mesh"' "$missions_dir/$run_id/meta.json")"
  elif [ -z "$run_id" ] && [ -d "$missions_dir" ]; then
    for m in $(ls -td "$missions_dir"/run_* 2>/dev/null); do
      if [ -f "$m/meta.json" ]; then
        run_id="$(basename "$m")"
        m_db="$(jq -r '.db // "mesh"' "$m/meta.json")"
        m_proj="$(jq -r '.project // "knot-mesh"' "$m/meta.json")"
        break
      fi
    done
  fi

  knot_log_info "Connecting to active agent session on node '$node_id' (Mission: ${run_id:-none})..."
  if [ "$node_id" = "desktop" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(hostname -s)" ]; then
    export KNOT_NODE_ID="$node_id"
    if [ -n "$run_id" ]; then export KNOT_COUNCIL_RUN_ID="$run_id"; fi
    export KNOT_HUB_URL="https://127.0.0.1:4242"
    export KNOT_COUNCIL_DB="$m_db"
    export KNOT_PROJECT="$m_proj"
    local pdir
    pdir="$("$SCRIPTS_DIR/resolve_project.py" "$m_proj" 2>/dev/null || echo "$KNOT_ROOT")"
    if [ -d "$pdir" ]; then cd "$pdir"; fi
    agy --project "$m_proj" --dangerously-skip-permissions -c
  else
    local remote_attach_cmd="export KNOT_NODE_ID='$node_id' KNOT_HUB_URL='https://127.0.0.1:4242'; if [ -n '$run_id' ]; then export KNOT_COUNCIL_RUN_ID='$run_id'; fi; export KNOT_COUNCIL_DB='$m_db' KNOT_PROJECT='$m_proj'; if [ -d \\\"Dev/$m_proj\\\" ]; then cd \\\"Dev/$m_proj\\\"; elif [ -d \\\"$m_proj\\\" ]; then cd \\\"$m_proj\\\"; fi; agy --project '$m_proj' --dangerously-skip-permissions -c"
    "$KNOT_ROOT/bin/knot" exec "$node_id" -tt "$remote_attach_cmd"
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

  local disc_id db_type
  disc_id="$(jq -r '.disc_id' "$meta_file")"
  db_type="$(jq -r '.db // "auto"' "$meta_file")"
  local out_file="$missions_dir/$run_id/reconciled_report.md"

  python3 "$SCRIPTS_DIR/reconcile.py" --discussion-id "$disc_id" --run-id "$run_id" --db-backend "$db_type" --out-file "$out_file"

  # Mark completed in meta
  local tmp_m
  tmp_m="$(mktemp)"
  jq '.status = "COMPLETED"' "$meta_file" > "$tmp_m" && mv "$tmp_m" "$meta_file"

  cat "$out_file"
}

council_kill() {
  local run_id="${1:-}"
  if [ -z "$run_id" ]; then
    echo "Usage: knot council kill <run_id>"
    return 1
  fi

  local missions_dir="$HOME/.config/knot/missions"
  local meta_file="$missions_dir/$run_id/meta.json"
  if [ -f "$meta_file" ]; then
    local tmp_m
    tmp_m="$(mktemp)"
    jq '.status = "TERMINATED"' "$meta_file" > "$tmp_m" && mv "$tmp_m" "$meta_file"
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
