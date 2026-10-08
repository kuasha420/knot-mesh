#!/usr/bin/env bash
set -euo pipefail

# Knot Council Module
# Out-of-band multi-agent coordination protocol using GitHub Discussions

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

SKILL_DIR="$KNOT_ROOT/runtime/skills/swarm-council"
SCRIPTS_DIR="$SKILL_DIR/scripts"

council_clean() {
  local days="${1:-7}"
  if [ "$days" = "-h" ] || [ "$days" = "--help" ]; then
    echo "Usage: knot council clean [days]"
    return 0
  fi
  local missions_dir="$HOME/.config/knot/missions"
  if [ -d "$missions_dir" ]; then
    find "$missions_dir" -mindepth 1 -maxdepth 1 -mtime "+$days" -exec rm -rf {} +
    knot_log_ok "Housekeeping complete: pruned council missions older than $days days."
  fi
}

council_copy() {
  if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "Usage: knot council copy"
    return 0
  fi
  local staged_file="$HOME/.config/knot/missions/staged/active_prompt.md"
  if [ ! -f "$staged_file" ]; then
    knot_log_err "No staged prompt found at $staged_file."
    echo "Staged prompts are created during 'knot council start --mode gui'."
    return 1
  fi

  if command -v wl-copy >/dev/null; then
    wl-copy < "$staged_file"
    knot_log_ok "Tailored prompt copied to Wayland clipboard ($(wc -c < "$staged_file") bytes)."
    echo "You can now paste directly into Antigravity 2.0 (Ctrl+V)."
  elif command -v xclip >/dev/null; then
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
  local auth_profile="${KNOT_AUTH_PROFILE:-}"

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
      --auth-profile|--profile) auth_profile="$2"; shift 2 ;;
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
        echo "  --auth-profile <al>  Pin mission permanently to specific auth profile"
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
  local sync_err_file
  sync_err_file="$(mktemp)"
  local sync_args=(--pull)
  if [ -n "$proj_override" ]; then
    sync_args+=(--project "$proj_override")
  fi
  if [ -n "$nodes" ]; then
    sync_args+=(--nodes "$nodes")
  fi
  if ! sync_out="$(bash "$SCRIPTS_DIR/project_sync.sh" "${sync_args[@]}" 2>"$sync_err_file")"; then
    knot_log_err "Project sync failed:"
    cat "$sync_err_file"
    rm -f "$sync_err_file"
    return 1
  fi
  rm -f "$sync_err_file"

  local jq_err
  if ! jq_err="$(echo "$sync_out" | jq empty 2>&1)"; then
    knot_log_err "Project sync returned invalid JSON output: $jq_err"
    echo "$sync_out"
    return 1
  fi

  if [ -z "$nodes" ]; then
    local syn_nodes=""
    if syn_nodes="$(echo "$sync_out" | jq -r '[.nodes | to_entries[]? | select(.value.status == "SYNCED") | .key] | join(",")' 2>&1)"; then
      [ -n "$syn_nodes" ] && nodes="$syn_nodes"
    fi
  fi
  if [ -z "$nodes" ]; then
    local online_nodes=()
    local ndir=""
    if ndir="$(knot_get_nodes_dir 2>&1)" && [ -d "$ndir" ]; then
      for mf in "$ndir"/*.json; do
        [ -e "$mf" ] || continue
        local nid=""
        nid="$(awk -F'"' '/"id":/ {print $4}' "$mf")"
        [ -n "$nid" ] && online_nodes+=("$nid")
      done
    fi
    if [ ${#online_nodes[@]} -gt 0 ]; then
      nodes="$(IFS=,; echo "${online_nodes[*]}")"
    else
      local my_n=""
      if ! my_n="$(knot_detect_node_id 2>&1)"; then
        if command -v hostname >/dev/null; then
          my_n="$(hostname -s)"
        else
          my_n="desktop"
        fi
      fi
      nodes="$my_n"
    fi
  fi

  local proj_name proj_folder
  proj_name="$(echo "$sync_out" | jq -r '.project_name // empty')"
  if [ -z "$proj_name" ] || [ "$proj_name" = "." ] || [ "$proj_name" = "./" ]; then
    if [ -n "$proj_override" ] && [ "$proj_override" != "." ] && [ "$proj_override" != "./" ]; then
      proj_name="$proj_override"
    else
      proj_name="knot-mesh"
    fi
  fi
  proj_folder="$(echo "$sync_out" | jq -r '.folders[0] // empty')"
  if [ -z "$proj_folder" ] || [ ! -d "$proj_folder" ]; then
    proj_folder="$(pwd)"
  fi

  # Stage 2: Create Mission registry thread
  local disc_res disc_id disc_url
  local rand_hex
  rand_hex="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  local run_id="run_$(date +%Y%m%d_%H%M%S)_${rand_hex}"

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
      local db_err_file
      db_err_file="$(mktemp)"
      if ! disc_res="$(python3 "$SCRIPTS_DIR/mesh_db.py" create --title "Swarm Council Mission: $run_id" --body "$disc_body" --run-id "$run_id" 2>"$db_err_file")"; then
        knot_log_err "Could not create mesh db registry:"
        cat "$db_err_file"
        rm -f "$db_err_file"
        return 1
      fi
      rm -f "$db_err_file"
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
      local gh_err_file
      gh_err_file="$(mktemp)"
      if ! disc_res="$(python3 "$SCRIPTS_DIR/gh_discussion.py" create --title "Swarm Council Mission: $run_id" --body "$disc_body" 2>"$gh_err_file")"; then
        knot_log_err "Could not create discussion thread:"
        cat "$gh_err_file"
        rm -f "$gh_err_file"
        return 1
      fi
      rm -f "$gh_err_file"
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
    if command -v jq >/dev/null; then
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
  if [ -f "$missions_dir/meta.json" ] && command -v jq >/dev/null; then
    local tmp_meta
    tmp_meta="$(mktemp)"
    jq --arg disc_id "$disc_id" --arg disc_url "$disc_url" --arg mode "$mode" --arg project "$proj_name" --arg db "$db" --arg tiling "$tiling" --argjson interactive "$interactive" \
      --arg auth_profile "$auth_profile" \
      '. + {disc_id: $disc_id, disc_url: $disc_url, mode: $mode, project: $project, db: $db, tiling: $tiling, interactive: $interactive, auth_profile: (if $auth_profile != "" then $auth_profile else (.auth_profile // null) end), status: "ACTIVE"}' \
      "$missions_dir/meta.json" > "$tmp_meta" && mv "$tmp_meta" "$missions_dir/meta.json"
  else
    local local_node
    local_node="$(knot_detect_node_id)"
    local auth_prof_json="null"
    if [ -n "$auth_profile" ]; then auth_prof_json="\"$auth_profile\""; fi
    echo "{\"run_id\":\"$run_id\",\"disc_id\":\"$disc_id\",\"disc_url\":\"$disc_url\",\"mode\":\"$mode\",\"project\":\"$proj_name\",\"db\":\"$db\",\"tiling\":\"$tiling\",\"pack\":\"$pack\",\"anchor\":\"$local_node\",\"opening_node\":\"$local_node\",\"interactive\":$interactive,\"nodes\":\"$nodes\",\"auth_profile\":$auth_prof_json,\"status\":\"ACTIVE\",\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$missions_dir/meta.json"
  fi

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
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council status [run_id]"
    return 0
  fi
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

  local resolved_hub=""
  if resolved_hub="$(hub_resolve_url 2>&1)"; then
    export KNOT_HUB_URL="${KNOT_HUB_URL:-$resolved_hub}"
  else
    export KNOT_HUB_URL="${KNOT_HUB_URL:-https://127.0.0.1:4242}"
  fi
  python3 "$SCRIPTS_DIR/reconcile.py" --discussion-id "$disc_id" --run-id "$run_id" --db-backend "$db_type"
}

council_reply() {
  local run_id="${1:-}"
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council reply <run_id> [--node <id>] [--status <status>] [--body <text>]"
    return 0
  fi
  if [ -z "$run_id" ]; then
    echo "Usage: knot council reply <run_id> [--node <id>] [--status <status>] [--body <text>]"
    return 1
  fi
  shift

  local node="$(knot_detect_node_id)"
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

  local resolved_hub=""
  if resolved_hub="$(hub_resolve_url 2>&1)"; then
    export KNOT_HUB_URL="${KNOT_HUB_URL:-$resolved_hub}"
  else
    export KNOT_HUB_URL="${KNOT_HUB_URL:-https://127.0.0.1:4242}"
  fi
  if [ "$db_type" = "mesh" ]; then
    python3 "$SCRIPTS_DIR/mesh_db.py" reply --discussion-id "$disc_id" --run-id "$run_id" --node-id "$node" --status "$status" --body "$body"
  else
    python3 "$SCRIPTS_DIR/gh_discussion.py" reply --discussion-id "$disc_id" --run-id "$run_id" --node-id "$node" --status "$status" --body "$body"
  fi
  local ev_hub="${KNOT_HUB_URL:-}"
  if [ -n "$ev_hub" ] && command -v curl >/dev/null; then
    local curl_out=""
    if ! curl_out="$(curl -k -sS -X POST "$ev_hub/strand/event" -H "Content-Type: application/json" -d "{\"run_id\":\"$run_id\",\"node_id\":\"$node\",\"event\":\"ACK\",\"details\":{\"status\":\"$status\"}}" 2>&1)"; then
      knot_log_warn "Notice: Event bus notification skipped: $curl_out"
    fi
  fi
  knot_log_ok "Reply posted for node '$node' (Status: $status) to mission $run_id"
}

council_steer() {
  local arg
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      echo "Usage: knot council steer [--wait-ack [sec]] <node> \"<prompt>\" [run_id]"
      echo "       echo \"<prompt>\" | knot council steer [--wait-ack [sec]] <node> [run_id]"
      return 0
    fi
  done

  local wait_ack=0
  local ack_timeout=30
  local positional=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --wait-ack)
        wait_ack=1
        if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then
          ack_timeout="$2"
          shift
        fi
        shift
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done

  local node="${positional[0]:-}"
  local prompt_text="${positional[1]:-}"
  local run_id="${positional[2]:-}"

  if [ "$prompt_text" = "-" ] || [ -z "$prompt_text" ]; then
    if [ ! -t 0 ]; then
      prompt_text="$(cat)"
    fi
  elif [ ${#positional[@]} -eq 2 ] && [ ! -t 0 ]; then
    # When piped with 2 positional args: echo "prompt" | knot council steer <node> <run_id>
    run_id="${positional[1]}"
    prompt_text="$(cat)"
  fi

  if [ -z "$node" ] || [ -z "$prompt_text" ]; then
    echo "Usage: knot council steer [--wait-ack [sec]] <node> \"<prompt>\" [run_id]"
    echo "       echo \"<prompt>\" | knot council steer [--wait-ack [sec]] <node> [run_id]"
    return 1
  fi

  # Normalize payload: strip carriage returns and guarantee trailing newline delimiter
  prompt_text="$(printf '%s' "$prompt_text" | tr -d '\r')"
  if [[ "$prompt_text" != *$'\n' ]]; then
    prompt_text="${prompt_text}"$'\n'
  fi

  local missions_dir="$HOME/.config/knot/missions"
  if [ -z "$run_id" ]; then
    local latest=""
    if compgen -G "$missions_dir/run_*" >/dev/null; then
      latest="$(ls -td "$missions_dir"/run_* | head -n1)"
    fi
    if [ -n "$latest" ]; then
      run_id="$(basename "$latest")"
    else
      knot_log_err "No active council run found to steer."
      return 1
    fi
  fi

  local sock="/tmp/kitty-council-$run_id.sock"
  local meta_file="$missions_dir/$run_id/meta.json"
  if [ ! -S "$sock" ] && [ -f "$meta_file" ]; then
    local configured_sock
    configured_sock="$(jq -r '.socket // ""' "$meta_file")"
    if [ -n "$configured_sock" ] && [ -S "$configured_sock" ]; then
      sock="$configured_sock"
    fi
  fi

  if [ ! -S "$sock" ]; then
    local target_host=""
    if [ -f "$meta_file" ]; then
      target_host="$(jq -r '.cockpit_node // .anchor // "desktop"' "$meta_file")"
    else
      target_host="desktop"
    fi
    local my_h=""
    if ! my_h="$(knot_detect_hostname 2>&1)"; then
      my_h="$(uname -n | cut -d. -f1)"
    fi
    if [ "$my_h" != "$target_host" ] && command -v knot >/dev/null; then
      if knot exec "$target_host" "test -S /tmp/kitty-council-$run_id.sock"; then
        local relay_err=""
        if relay_err="$(printf '%s' "$prompt_text" | knot exec "$target_host" "kitty @ --to unix:/tmp/kitty-council-$run_id.sock send-text --match 'title:.*${node}.*' --stdin && sleep 0.2 && kitty @ --to unix:/tmp/kitty-council-$run_id.sock send-key --match 'title:.*${node}.*' return" 2>&1)"; then
          knot_log_ok "Steered node '@$node' via Cockpit Bridge Relay to @$target_host (Run: $run_id)"
          return 0
        else
          knot_log_err "Remote steer relay to @$target_host failed for node '$node': $relay_err"
          return 1
        fi
      fi
    fi
    # If not on target_host, probe online nodes where the offloaded socket might reside
    if command -v knot >/dev/null; then
      local mesh_status=""
      if mesh_status="$(knot status 2>&1)"; then
        local cand_node=""
        while IFS= read -r cand; do
          [ -n "$cand" ] || continue
          [[ "$cand" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || continue
          [ "$cand" != "NODE" ] || continue
          [ "$cand" != "$my_h" ] && [ "$cand" != "$target_host" ] || continue
          if knot exec "$cand" "test -S /tmp/kitty-council-$run_id.sock"; then
            cand_node="$cand"
            break
          fi
        done < <(echo "$mesh_status" | awk 'NR>2 {print $1}')
        if [ -n "$cand_node" ]; then
          local relay_err=""
          if relay_err="$(printf '%s' "$prompt_text" | knot exec "$cand_node" "kitty @ --to unix:/tmp/kitty-council-$run_id.sock send-text --match 'title:.*${node}.*' --stdin && sleep 0.2 && kitty @ --to unix:/tmp/kitty-council-$run_id.sock send-key --match 'title:.*${node}.*' return" 2>&1)"; then
            knot_log_ok "Steered node '@$node' via Cockpit Bridge Relay to @$cand_node (Run: $run_id)"
            return 0
          else
            knot_log_err "Remote steer relay to @$cand_node failed for node '$node': $relay_err"
            return 1
          fi
        fi
      fi
    fi
    knot_log_err "Kitty control socket not found for run '$run_id' at $sock."
    echo "Ensure the cockpit was launched with Kitty remote control enabled."
    return 1
  fi

  # Send text to target node's pane via Kitty remote control socket using stdin
  # Matches window title containing the node name (e.g. title:.*laptop.*)
  local steer_err=""
  if steer_err="$(printf '%s' "$prompt_text" | kitty @ --to "unix:$sock" send-text --match "title:.*${node}.*" --stdin 2>&1)"; then
    sleep 0.2
    local key_err=""
    if ! key_err="$(kitty @ --to "unix:$sock" send-key --match "title:.*${node}.*" return 2>&1)"; then
      knot_log_warn "Notice: kitty send-key return failed: $key_err"
    fi

    # Execution state verification: query window buffer via get-text
    sleep 0.2
    local win_buf=""
    if win_buf="$(kitty @ --to "unix:$sock" get-text --match "title:.*${node}.*" 2>&1)"; then
      local first_line=""
      first_line="$(printf '%s' "$prompt_text" | head -n1)"
      if [ -n "$first_line" ] && echo "$win_buf" | tail -n2 | grep -Fq "$first_line"; then
        knot_log_warn "Prompt appears unsubmitted in node '@$node' window buffer. Re-attempting return key dispatch..."
        local retry_key_err="" retry_key_rc=0
        retry_key_err="$(kitty @ --to "unix:$sock" send-key --match "title:.*${node}.*" return 2>&1)" || retry_key_rc=$?
        if [ $retry_key_rc -ne 0 ]; then
          knot_log_warn "Notice: retry kitty send-key return failed ($retry_key_rc): $retry_key_err"
        fi
      fi
    fi
    knot_log_ok "Steered node '@$node' via Cockpit Bridge (Run: $run_id)"

    if [ "$wait_ack" -eq 1 ]; then
      knot_log_info "Awaiting turn-state acknowledgement from @$node (timeout: ${ack_timeout}s)..."
      local start_t
      start_t="$(date +%s)"
      local ack_received=0
      local events_sock="${KNOT_EVENTS_SOCK:-$HOME/.config/knot/events.sock}"
      local hub_url="${KNOT_HUB_URL:-}"
      if [ -z "$hub_url" ] && command -v hub_resolve_url >/dev/null; then
        local r_url=""
        if r_url="$(hub_resolve_url 2>&1)"; then
          hub_url="$r_url"
        fi
      fi

      # 1. Reactive Event Bus subscription via UNIX socket or SSE stream
      if command -v python3 >/dev/null; then
        local reactive_rc=0
        python3 -c '
import sys, os, socket, json, time, urllib.request, urllib.error

sock_path = sys.argv[1]
node_id = sys.argv[2]
run_id = sys.argv[3]
timeout = float(sys.argv[4])
hub_url = sys.argv[5] if len(sys.argv) > 5 else ""

deadline = time.time() + timeout

# 1. Try UNIX domain socket first
if sock_path and os.path.exists(sock_path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(sock_path)
        s.settimeout(min(1.0, timeout))
        buffer = ""
        while time.time() < deadline:
            try:
                chunk = s.recv(4096).decode("utf-8")
                if not chunk:
                    break
                buffer += chunk
                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                        if d.get("node_id") == node_id and d.get("event") in ("TURN_START", "ACK", "AWAITING_INPUT", "COMPLETED"):
                            if not run_id or not d.get("run_id") or d.get("run_id") == run_id:
                                sys.exit(0)
                    except json.JSONDecodeError:
                        continue
            except socket.timeout:
                continue
    except (ConnectionRefusedError, FileNotFoundError, OSError) as e:
        sys.stderr.write(f"Notice: UNIX events socket connect/recv notice: {e}\n")
    finally:
        s.close()

# 2. Try SSE endpoint if hub_url provided and time remains
if hub_url and time.time() < deadline:
    try:
        url = f"{hub_url}/strand/events"
        if run_id:
            url += f"?run_id={run_id}"
        req = urllib.request.Request(url, headers={"Accept": "text/event-stream"})
        rem_timeout = max(0.5, deadline - time.time())
        with urllib.request.urlopen(req, timeout=rem_timeout) as resp:
            for raw_line in resp:
                if time.time() >= deadline:
                    break
                line = raw_line.decode("utf-8").strip()
                if line.startswith("data:"):
                    try:
                        d = json.loads(line[5:].strip())
                        if d.get("node_id") == node_id and d.get("event") in ("TURN_START", "ACK", "AWAITING_INPUT", "COMPLETED"):
                            if not run_id or not d.get("run_id") or d.get("run_id") == run_id:
                                sys.exit(0)
                    except json.JSONDecodeError:
                        continue
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as e:
        sys.stderr.write(f"Notice: SSE events stream notice: {e}\n")

sys.exit(1)
' "$events_sock" "$node" "$run_id" "$ack_timeout" "$hub_url" || reactive_rc=$?

        if [ $reactive_rc -eq 0 ]; then
          ack_received=1
          knot_log_ok "Received acknowledgement from @$node via reactive Event Bus"
        fi
      fi

      # 2. Fallback to Mesh DB thread query if event bus did not report
      if [ "$ack_received" -eq 0 ]; then
        local poll_script="$SCRIPTS_DIR/mesh_db.py"
        if [ -f "$poll_script" ]; then
          while [ $(( $(date +%s) - start_t )) -lt "$ack_timeout" ]; do
            local latest_msg
            latest_msg="$(python3 "$poll_script" get_thread --discussion-id "$run_id" 2>&1)"
            if echo "$latest_msg" | grep -q "\"author\": {\"login\": \"$node\"}"; then
              ack_received=1
              knot_log_ok "Received acknowledgement from @$node in Mesh DB"
              break
            fi
            sleep 1
          done
        fi
      fi

      if [ "$ack_received" -eq 0 ]; then
        knot_log_warn "Timeout waiting for acknowledgement from @$node after ${ack_timeout}s"
      fi
    fi

    return 0
  else
    knot_log_err "Failed to deliver prompt to node '$node' via socket $sock"
    return 1
  fi
}

council_challenge() {
  local script="$SCRIPTS_DIR/challenge_tool.py"
  if [ ! -f "$script" ]; then
    script="$KNOT_ROOT/runtime/skills/swarm-council/scripts/challenge_tool.py"
  fi
  if [ ! -f "$script" ]; then
    knot_log_err "challenge_tool.py not found at $script"
    return 1
  fi
  python3 "$script" "$@"
}

council_db() {
  local action="${1:-inspect}"
  if [ "$action" = "-h" ] || [ "$action" = "--help" ]; then
    echo "Usage: knot council db <inspect|tail|list> [run_id] [options]"
    return 0
  fi
  [ $# -gt 0 ] && shift
  local run_id="${1:-}"
  [ $# -gt 0 ] && shift

  local missions_dir="$HOME/.config/knot/missions"
  if [ -z "$run_id" ] && [ "$action" != "list" ]; then
    local latest=""
    if compgen -G "$missions_dir/run_*" >/dev/null; then
      latest="$(ls -td "$missions_dir"/run_* | head -n1)"
    fi
    if [ -n "$latest" ]; then
      run_id="$(basename "$latest")"
    else
      knot_log_err "No active council run found."
      return 1
    fi
  fi

  local script="$SCRIPTS_DIR/mesh_db.py"
  if [ ! -f "$script" ]; then
    script="$KNOT_ROOT/runtime/skills/swarm-council/scripts/mesh_db.py"
  fi

  case "$action" in
    inspect)
      python3 "$script" get_thread --discussion-id "$run_id"
      ;;
    tail)
      python3 "$script" tail --discussion-id "$run_id" "$@"
      ;;
    list)
      python3 "$script" list
      ;;
    -h|--help)
      echo "Usage: knot council db <inspect|tail|list> [run_id] [options]"
      return 0
      ;;
    *)
      echo "Usage: knot council db <inspect|tail|list> [run_id] [options]" >&2
      return 1
      ;;
  esac
}

_council_list_runs() {
  local dir="${1:-$HOME/.config/knot/missions}"
  [ -d "$dir" ] || return 0
  shopt -s nullglob
  local runs=("$dir"/run_*)
  shopt -u nullglob
  [ ${#runs[@]} -gt 0 ] || return 0
  printf '%s\n' "${runs[@]}" | sort -r
}

council_list() {
  local filter="${1:-}"
  if [ "$filter" = "-h" ] || [ "$filter" = "--help" ]; then
    echo "Usage: knot council list [interactive|mesh|ghd|active]"
    return 0
  fi
  echo -e "${C_BOLD}--- Knot Swarm Council Missions ---${C_RESET}"
  local missions_dir="$HOME/.config/knot/missions"
  if [ -d "$missions_dir" ]; then
    local count=0
    while IFS= read -r m; do
      [ -n "$m" ] && [ -d "$m" ] || continue
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
    done < <(_council_list_runs "$missions_dir")
    if [ $count -eq 0 ]; then
      echo "  (No matching council missions found)"
    fi
  fi
}

council_resume() {
  local run_id="${1:-}"
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council resume [run_id]"
    return 0
  fi
  local missions_dir="$HOME/.config/knot/missions"

  if [ -z "$run_id" ]; then
    local latest=""
    if [ -d "$missions_dir" ]; then
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ -f "$m/meta.json" ]; then
          latest="$(basename "$m")"
          break
        fi
      done < <(_council_list_runs "$missions_dir")
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

  if [ "$node_id" = "-h" ] || [ "$node_id" = "--help" ]; then
    echo "Usage: knot council attach <node_id> [run_id]"
    return 0
  fi

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
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      if [ -f "$m/meta.json" ]; then
        run_id="$(basename "$m")"
        m_db="$(jq -r '.db // "mesh"' "$m/meta.json")"
        m_proj="$(jq -r '.project // "knot-mesh"' "$m/meta.json")"
        break
      fi
    done < <(_council_list_runs "$missions_dir")
  fi

  knot_log_info "Connecting to active agent session on node '$node_id' (Mission: ${run_id:-none})..."
  local local_node
  local_node="$(knot_detect_node_id)"
  local resolved_hub
  resolved_hub="${KNOT_HUB_URL:-$(hub_resolve_url)}"
  if [ "$node_id" = "$local_node" ] || [ "$node_id" = "localhost" ] || [ "$node_id" = "$(knot_detect_hostname)" ]; then
    export KNOT_NODE_ID="$node_id"
    if [ -n "$run_id" ]; then export KNOT_COUNCIL_RUN_ID="$run_id"; fi
    export KNOT_HUB_URL="$resolved_hub"
    export KNOT_COUNCIL_DB="$m_db"
    export KNOT_PROJECT="$m_proj"
    local pdir=""
    if ! pdir="$("$SCRIPTS_DIR/resolve_project.py" "$m_proj" 2>&1)"; then
      pdir="$KNOT_ROOT"
    fi
    if [ -d "$pdir" ]; then cd "$pdir"; fi
    agy --project "$m_proj" --dangerously-skip-permissions -c
  else
    local remote_attach_cmd="export KNOT_NODE_ID='$node_id' KNOT_HUB_URL='$resolved_hub'; if [ -n '$run_id' ]; then export KNOT_COUNCIL_RUN_ID='$run_id'; fi; export KNOT_COUNCIL_DB='$m_db' KNOT_PROJECT='$m_proj'; PDIR=\$(python3 -c 'import sys,os,glob,json;home=os.path.expanduser(\"~\");pname=sys.argv[1].lower() if len(sys.argv)>1 else \"\";pdir=os.path.join(home,\".gemini/config/projects\");res=\"\";[setattr(sys.modules[__name__],\"res\",p if os.path.isdir(p) else next((c for b in [os.path.basename(p)] for c in [os.path.join(home,\"Dev\",b),os.path.join(home,b)] if os.path.isdir(c)),\"\")) for f in (glob.glob(os.path.join(pdir,\"*.json\")) if os.path.isdir(pdir) else []) if not res for d in [json.load(open(f))] if (d.get(\"name\",\"\").lower()==pname or d.get(\"id\",\"\").lower()==pname) for r in d.get(\"projectResources\",{}).get(\"resources\",[]) for u in [r.get(\"gitFolder\",{}).get(\"folderUri\",\"\")] if u.startswith(\"file://\") for p in [u[7:].rstrip(\"/\")]]; print(res or next((c for c in [os.path.join(home,\"Dev\",pname),os.path.join(home,pname)] if os.path.isdir(c)),os.getcwd()))' '$m_proj'); if [ -d \"\$PDIR\" ]; then cd \"\$PDIR\"; fi; agy --project '$m_proj' --dangerously-skip-permissions -c"
    "$KNOT_ROOT/bin/knot" exec -tt "$node_id" "$remote_attach_cmd"
  fi
}

council_reconcile() {
  local run_id="${1:-}"
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council reconcile [run_id]"
    return 0
  fi
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
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council kill <run_id>"
    return 0
  fi
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
  if pgrep --quiet -f "knot-council-$run_id"; then
    pkill -f "knot-council-$run_id"
  fi
  if pgrep --quiet -f "$run_id.*kitty"; then
    pkill -f "$run_id.*kitty"
  fi
  if pgrep --quiet -f "kitty.*$run_id"; then
    pkill -f "kitty.*$run_id"
  fi
  if pgrep --quiet -f "$run_id"; then
    pkill -f "$run_id"
  fi
  rm -f "/tmp/kitty-council-$run_id.sock"
  "$KNOT_ROOT/bin/knot" exec --all "if pgrep --quiet -f $run_id; then pkill -f $run_id; fi"
  knot_log_ok "Council run $run_id halted across fleet."
}

council_heal() {
  local run_id="${1:-}"
  if [ "$run_id" = "-h" ] || [ "$run_id" = "--help" ]; then
    echo "Usage: knot council heal [run_id]"
    return 0
  fi
  local missions_dir="$HOME/.config/knot/missions"

  if [ -z "$run_id" ]; then
    local latest=""
    if [ -d "$missions_dir" ]; then
      while IFS= read -r m; do
        [ -n "$m" ] || continue
        if [ -f "$m/meta.json" ]; then
          latest="$(basename "$m")"
          break
        fi
      done < <(_council_list_runs "$missions_dir")
    fi
    if [ -n "$latest" ]; then
      run_id="$latest"
    else
      knot_log_err "No active council run found to heal."
      return 1
    fi
  fi

  local meta_file="$missions_dir/$run_id/meta.json"
  local sock="/tmp/kitty-council-$run_id.sock"
  if [ ! -S "$sock" ] && [ -f "$meta_file" ]; then
    local configured_sock
    configured_sock="$(jq -r '.socket // ""' "$meta_file")"
    if [ -n "$configured_sock" ] && [ -S "$configured_sock" ]; then
      sock="$configured_sock"
    fi
  fi

  if [ ! -S "$sock" ]; then
    knot_log_err "Kitty control socket not found for run '$run_id' at $sock."
    echo "Ensure the cockpit was launched with Kitty remote control enabled."
    return 1
  fi

  local kitty_ls=""
  if ! kitty_ls="$(kitty @ --to "unix:$sock" ls 2>&1)"; then
    knot_log_err "Failed to query Kitty socket at $sock: $kitty_ls"
    return 1
  fi

  local active_titles
  active_titles="$(printf '%s' "$kitty_ls" | jq -r '.. | objects | select(has("title")) | .title')"

  local target_nodes=()
  if [ -f "$meta_file" ]; then
    local meta_nodes
    meta_nodes="$(jq -r '.nodes // ""' "$meta_file")"
    if [ -n "$meta_nodes" ]; then
      IFS=',' read -r -a target_nodes <<< "$meta_nodes"
    fi
  fi
  if [ ${#target_nodes[@]} -eq 0 ]; then
    local pscripts
    shopt -s nullglob
    pscripts=("$missions_dir/$run_id"/confluence_*.sh)
    shopt -u nullglob
    for ps in "${pscripts[@]}"; do
      local bname
      bname="$(basename "$ps")"
      local nid="${bname#confluence_}"
      nid="${nid%.sh}"
      if [ -n "$nid" ]; then
        target_nodes+=("$nid")
      fi
    done
  fi

  if [ ${#target_nodes[@]} -eq 0 ]; then
    knot_log_err "No target nodes discovered for mission $run_id."
    return 1
  fi

  local missing_nodes=()
  for node in "${target_nodes[@]}"; do
    if ! echo "$active_titles" | grep -q "$node"; then
      missing_nodes+=("$node")
    fi
  done

  if [ ${#missing_nodes[@]} -eq 0 ]; then
    knot_log_ok "Cockpit topology is healthy: all nodes are active in Kitty."
    return 0
  fi

  knot_log_warn "Detected missing cockpit pane(s): ${missing_nodes[*]}"
  local healed_count=0
  for node in "${missing_nodes[@]}"; do
    local pane_script="$missions_dir/$run_id/confluence_${node}.sh"
    if [ ! -f "$pane_script" ]; then
      knot_log_warn "Pane script not found for node '$node' at $pane_script, skipping."
      continue
    fi

    local win_title=""
    local conf_file="$missions_dir/$run_id/kitty_session.conf"
    if [ -f "$conf_file" ]; then
      win_title="$(awk -v script="confluence_${node}.sh" '
        $0 ~ script { if (prev ~ /^title /) print substr(prev, 7) }
        { prev = $0 }
      ' "$conf_file")"
    fi
    if [ -z "$win_title" ]; then
      win_title="🛰️ $node ($node node)"
    fi

    knot_log_info "Healing missing cockpit pane for @[$node]..."
    local launch_err=""
    if launch_err="$(kitty @ --to "unix:$sock" launch --title "$win_title" --cwd="$KNOT_ROOT" "$pane_script" 2>&1)"; then
      knot_log_ok "Restored pane for @[$node] in cockpit (Run: $run_id)"
      healed_count=$((healed_count + 1))
    else
      knot_log_err "Failed to heal pane for @[$node]: $launch_err"
    fi
  done

  if [ "$healed_count" -gt 0 ]; then
    knot_log_ok "Cockpit topology self-healing complete: restored $healed_count missing pane(s)."
    return 0
  else
    knot_log_err "Self-healing failed: no panes could be restored."
    return 1
  fi
}

council_board() {
  if [ -z "${KNOT_HUB_URL:-}" ]; then
    local resolved_hub=""
    if resolved_hub="$(hub_resolve_url 2>&1)"; then
      export KNOT_HUB_URL="$resolved_hub"
    fi
  fi
  exec python3 "$KNOT_ROOT/runtime/skills/swarm-council/scripts/board_viewer.py" "$@"
}

