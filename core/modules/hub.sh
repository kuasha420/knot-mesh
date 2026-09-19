#!/usr/bin/env bash
set -euo pipefail

# Knot Swarm Hub & Task Management Module
# Manages knot-hub, knot-agent daemons, and Linda Tuplespace blackboard interactions

if [ -z "${KNOT_ROOT:-}" ]; then
  KNOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
source "$KNOT_ROOT/core/lib.sh"

hub_resolve_url() {
  if [ -n "${KNOT_HUB_URL:-}" ]; then
    echo "$KNOT_HUB_URL"
    return 0
  fi

  local active_swarm=""
  active_swarm="$(knot_get_active_swarm)"
  local anchor_target="desktop"
  local hub_port=4242
  if knot_load_swarm_profile "$active_swarm"; then
    anchor_target="${ANCHOR_ID:-desktop}"
    hub_port="${HUB_PORT:-4242}"
  fi

  local my_host
  my_host="$(knot_detect_hostname)"
  if [ "$my_host" = "$anchor_target" ] || [ -n "${ANCHOR_HOST:-}" ] && [ "$my_host" = "$ANCHOR_HOST" ]; then
    echo "https://127.0.0.1:${hub_port}"
    return 0
  fi

  local resolved_ip=""
  if resolved_ip="$("$KNOT_ROOT/core/resolver.sh" "$anchor_target" "$hub_port")"; then
    if [ -n "$resolved_ip" ]; then
      echo "https://${resolved_ip}:${hub_port}"
      return 0
    fi
  fi

  echo "https://127.0.0.1:${hub_port}"
}

hub_ensure_services() {
  local user_systemd="$HOME/.config/systemd/user"
  mkdir -p "$user_systemd"

  cat << EOF > "$user_systemd/knot-hub.service"
[Unit]
Description=Knot Swarm Blackboard Hub Daemon
After=network.target default.target

[Service]
Type=simple
ExecStart=$KNOT_ROOT/core/hub/hub.py
Restart=always
RestartSec=3
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  cat << EOF > "$user_systemd/knot-agent.service"
[Unit]
Description=Knot Swarm Worker Agent Daemon
After=network.target default.target

[Service]
Type=simple
ExecStart=$KNOT_ROOT/core/hub/agent.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
}

cmd_hub() {
  local action="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi

  hub_ensure_services

  case "$action" in
    start)
      knot_log_info "Starting Knot Swarm Blackboard Hub (knot-hub)..."
      systemctl --user enable --now knot-hub.service
      knot_log_ok "knot-hub.service started."
      ;;
    stop)
      knot_log_info "Stopping Knot Swarm Blackboard Hub..."
      systemctl --user stop knot-hub.service
      knot_log_ok "knot-hub.service stopped."
      ;;
    restart)
      knot_log_info "Restarting Knot Swarm Blackboard Hub..."
      systemctl --user restart knot-hub.service
      knot_log_ok "knot-hub.service restarted."
      ;;
    status)
      echo -e "${C_BOLD}--- Knot Swarm Hub Status ---${C_RESET}"
      systemctl --user status knot-hub.service --no-pager || true
      echo ""
      local hub_url
      hub_url="$(hub_resolve_url)"
      knot_log_info "Querying Hub Health at $hub_url/health..."
      local health_out="" rc=0
      health_out="$(curl -k -s --connect-timeout 2 "$hub_url/health" 2>&1)" || rc=$?
      if [ $rc -eq 0 ] && [ -n "$health_out" ]; then
        if command -v jq >/dev/null 2>&1; then
          echo "$health_out" | jq .
        else
          echo "$health_out"
        fi
      else
        knot_log_warn "Could not connect to knot-hub at $hub_url (Hub may be stopped)"
      fi
      ;;
    logs)
      journalctl --user -u knot-hub.service -n 50 -f
      ;;
    *)
      echo "Usage: knot hub <start|stop|restart|status|logs>"
      exit 1
      ;;
  esac
}

cmd_agent() {
  local action="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi

  hub_ensure_services

  case "$action" in
    start)
      knot_log_info "Starting Knot Swarm Worker Agent (knot-agent)..."
      systemctl --user enable --now knot-agent.service
      knot_log_ok "knot-agent.service started."
      ;;
    stop)
      knot_log_info "Stopping Knot Swarm Worker Agent..."
      systemctl --user stop knot-agent.service
      knot_log_ok "knot-agent.service stopped."
      ;;
    restart)
      knot_log_info "Restarting Knot Swarm Worker Agent..."
      systemctl --user restart knot-agent.service
      knot_log_ok "knot-agent.service restarted."
      ;;
    status)
      echo -e "${C_BOLD}--- Knot Swarm Worker Agent Status ---${C_RESET}"
      systemctl --user status knot-agent.service --no-pager || true
      ;;
    logs)
      journalctl --user -u knot-agent.service -n 50 -f
      ;;
    *)
      echo "Usage: knot agent <start|stop|restart|status|logs>"
      exit 1
      ;;
  esac
}

cmd_task() {
  local action="${1:-list}"
  if [ $# -gt 0 ]; then shift; fi

  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    post)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot task post \"<prompt>\" [--plane <plane>] [--title <title>]"
        exit 1
      fi
      local prompt="$1"
      shift
      local target_plane="any"
      local title="Autonomous Swarm Task"

      while [ $# -gt 0 ]; do
        case "$1" in
          --plane)
            target_plane="$2"
            shift 2
            ;;
          --title)
            title="$2"
            shift 2
            ;;
          *)
            shift
            ;;
        esac
      done

      local payload
      payload="$(jq -n \
        --arg title "$title" \
        --arg prompt "$prompt" \
        --arg target_plane "$target_plane" \
        '{title: $title, prompt: $prompt, target_plane: $target_plane}')"

      local resp="" rc=0
      resp="$(curl -k -s -X POST "$hub_url/tasks/post" \
        -H "Content-Type: application/json" \
        -d "$payload" 2>&1)" || rc=$?

      if [ $rc -eq 0 ] && [ -n "$resp" ]; then
        local task_id
        task_id="$(echo "$resp" | jq -r '.id // empty')"
        if [ -n "$task_id" ]; then
          knot_log_ok "Task successfully posted to Blackboard!"
          echo -e "  Task ID:      ${C_BOLD}${C_CYAN}$task_id${C_RESET}"
          echo -e "  Title:        $title"
          echo -e "  Target Plane: ${C_YELLOW}$target_plane${C_RESET}"
          echo -e "  Status:       ${C_GREEN}QUEUED${C_RESET}"
          echo ""
          echo -e "To follow execution: ${C_BOLD}knot task wait $task_id${C_RESET}"
        else
          knot_log_err "Failed to post task: $resp"
          exit 1
        fi
      else
        knot_log_err "Hub connection error to $hub_url: $resp"
        exit 1
      fi
      ;;

    list)
      local status_filter="${1:-}"
      local url="$hub_url/tasks/list"
      if [ -n "$status_filter" ] && [ "$status_filter" != "--all" ]; then
        url="$url?status=$status_filter"
      fi

      local resp="" rc=0
      resp="$(curl -k -s "$url" 2>&1)" || rc=$?
      if [ $rc -ne 0 ] || [ -z "$resp" ]; then
        knot_log_err "Failed to reach Knot Hub at $hub_url"
        exit 1
      fi

      echo -e "${C_BOLD}--- Knot Swarm Blackboard Tasks ---${C_RESET}"
      printf "%-10s %-24s %-12s %-12s %-10s %-8s\n" "TASK ID" "TITLE" "PLANE" "STATUS" "NODE" "DURATION"
      printf "%-10s %-24s %-12s %-12s %-10s %-8s\n" "-------" "-----" "-----" "------" "----" "--------"

      if command -v jq >/dev/null 2>&1; then
        echo "$resp" | jq -r '.[] | [.id[:8], .title[:24], .target_plane, .status, (.claimed_by // "-"), ((.duration_seconds // 0 | tostring) + "s")] | @tsv' | while IFS=$'\t' read -r tid ttitle tplane tstatus tnode tdur; do
          local color="$C_RESET"
          case "$tstatus" in
            QUEUED)    color="$C_YELLOW" ;;
            BLOCKED_ON_DEPS) color="$C_YELLOW"; tstatus="BLOCKED" ;;
            BLOCKED_FAILED) color="$C_RED"; tstatus="BLK_FAIL" ;;
            CLAIMED)   color="$C_BLUE" ;;
            RUNNING)   color="$C_CYAN" ;;
            COMPLETED|SUCCESS) color="$C_GREEN" ;;
            FAILED|ERROR) color="$C_RED" ;;
          esac
          printf "%-10s %-24s %-12s ${color}%-12s${C_RESET} %-10s %-8s\n" "$tid" "$ttitle" "$tplane" "$tstatus" "$tnode" "$tdur"
        done
      else
        echo "$resp"
      fi
      ;;

    batch)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot task batch <batch_id>"
        exit 1
      fi
      local batch_id="$1"
      local resp="" rc=0
      resp="$(curl -k -s "$hub_url/tasks/batch/$batch_id" 2>&1)" || rc=$?
      if [ $rc -eq 0 ] && [ -n "$resp" ]; then
        if command -v jq >/dev/null 2>&1; then
          echo "$resp" | jq .
        else
          echo "$resp"
        fi
      else
        knot_log_err "Batch '$batch_id' not found or hub unreachable"
        exit 1
      fi
      ;;

    get)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot task get <task_id>"
        exit 1
      fi
      local task_id="$1"
      local resp="" rc=0
      resp="$(curl -k -s "$hub_url/tasks/$task_id" 2>&1)" || rc=$?
      if [ $rc -eq 0 ] && [ -n "$resp" ]; then
        if command -v jq >/dev/null 2>&1; then
          echo "$resp" | jq .
        else
          echo "$resp"
        fi
      else
        knot_log_err "Task '$task_id' not found or hub unreachable"
        exit 1
      fi
      ;;

    wait)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot task wait <task_id> [--timeout <secs>]"
        exit 1
      fi
      local task_id="$1"
      local timeout_secs=300
      local start_time
      start_time="$(date +%s)"

      knot_log_info "Waiting for completion of task '$task_id'..."
      while true; do
        local resp="" rc=0
        resp="$(curl -k -s "$hub_url/tasks/$task_id" 2>&1)" || rc=$?
        if [ $rc -eq 0 ] && [ -n "$resp" ]; then
          local status
          status="$(echo "$resp" | jq -r '.status // empty')"
          case "$status" in
            COMPLETED|SUCCESS)
              knot_log_ok "Task completed successfully!"
              local node dur tokens sess result
              node="$(echo "$resp" | jq -r '.claimed_by // "unknown"')"
              dur="$(echo "$resp" | jq -r '.duration_seconds // 0')"
              tokens="$(echo "$resp" | jq -r '.tokens_used // 0')"
              sess="$(echo "$resp" | jq -r '.session_id // "none"')"
              result="$(echo "$resp" | jq -r '.result // ""')"

              echo -e "  Executed By: ${C_BOLD}$node${C_RESET}"
              echo -e "  Duration:    ${C_YELLOW}${dur}s${C_RESET}"
              echo -e "  Tokens Used: $tokens"
              echo -e "  Session ID:  $sess"
              echo -e "\n${C_BOLD}--- Result ---${C_RESET}\n"
              echo -e "$result"
              return 0
              ;;
            FAILED|ERROR|TIMEOUT)
              knot_log_err "Task finished with status: $status"
              local err_result
              err_result="$(echo "$resp" | jq -r '.result // ""')"
              echo "$err_result"
              return 1
              ;;
            *)
              local node
              node="$(echo "$resp" | jq -r '.claimed_by // "unclaimed"')"
              echo -ne "  Status: ${C_CYAN}$status${C_RESET} (node: $node) ...\r"
              ;;
          esac
        fi

        local now
        now="$(date +%s)"
        if [ $((now - start_time)) -ge $timeout_secs ]; then
          echo ""
          knot_log_err "Wait timed out after ${timeout_secs}s"
          return 1
        fi
        sleep 2
      done
      ;;

    watch)
      knot_log_info "Connecting to real-time Blackboard stream at $hub_url/stream..."
      curl -k -N -s "$hub_url/stream" | while read -r line; do
        if [[ "$line" =~ ^event: ]]; then
          echo -e "\n${C_BOLD}${C_BLUE}>>> $line${C_RESET}"
        elif [[ "$line" =~ ^data: ]]; then
          local data="${line#data: }"
          if command -v jq >/dev/null 2>&1; then
            echo "$data" | jq -C .
          else
            echo "$data"
          fi
        fi
      done
      ;;

    *)
      echo "Usage: knot task <post|list|batch|get|wait|watch>"
      exit 1
      ;;
  esac
}

cmd_project() {
  local action="${1:-list}"
  if [ $# -gt 0 ]; then shift; fi
  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    list)
      local resp="" rc=0
      resp="$(curl -k -s "$hub_url/projects" 2>&1)" || rc=$?
      if [ $rc -ne 0 ] || [ -z "$resp" ]; then
        knot_log_err "Failed to reach Knot Hub at $hub_url"
        exit 1
      fi

      echo -e "${C_BOLD}--- Knot Native Antigravity Projects ---${C_RESET}"
      printf "%-24s %-28s %-10s %-12s\n" "PROJECT ID" "NAME" "FOLDERS" "DEFAULT CHAN"
      printf "%-24s %-28s %-10s %-12s\n" "----------" "----" "-------" "------------"

      if command -v jq >/dev/null 2>&1; then
        echo "$resp" | jq -r '.[] | [.id[:24], .name[:28], (.folders | length | tostring), (.default_channel // "main")] | @tsv' | while IFS=$'\t' read -r pid pname pfolders pchan; do
          printf "%-24s %-28s %-10s %-12s\n" "$pid" "$pname" "$pfolders" "#$pchan"
        done
      else
        echo "$resp"
      fi
      ;;
    get)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot project get <project_id>"
        exit 1
      fi
      local pid="$1"
      local resp
      resp="$(curl -k -s "$hub_url/projects/$pid")"
      if command -v jq >/dev/null 2>&1; then
        echo "$resp" | jq .
      else
        echo "$resp"
      fi
      ;;
    sync)
      knot_log_info "Synchronizing native Antigravity projects with Hub..."
      local resp
      resp="$(curl -k -s "$hub_url/projects")"
      local count
      count="$(echo "$resp" | jq -r 'length // 0')"
      knot_log_ok "Hub registered $count native Antigravity projects."
      ;;
    worktree)
      cmd_worktree "$@"
      ;;
    *)
      echo "Usage: knot project <list|get|sync|worktree>"
      exit 1
      ;;
  esac
}

cmd_chat() {
  local action="${1:-read}"
  if [ $# -gt 0 ]; then shift; fi
  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    channels|list)
      local project_id=""
      while [ $# -gt 0 ]; do
        case "$1" in
          -p|--project) project_id="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      local url="$hub_url/chat/conversations"
      if [ -n "$project_id" ]; then
        url="$url?project_id=$project_id"
      fi
      local resp="" rc=0
      resp="$(curl -k -s "$url" 2>&1)" || rc=$?
      if [ $rc -ne 0 ] || [ -z "$resp" ]; then
        knot_log_err "Failed to reach Knot Hub at $hub_url"
        exit 1
      fi

      echo -e "${C_BOLD}--- Knot Swarm Channels & Conversations ---${C_RESET}"
      printf "%-18s %-20s %-24s %-8s %-12s\n" "CHANNEL ID" "PROJECT" "TITLE" "MSGS" "CREATED BY"
      printf "%-18s %-20s %-24s %-8s %-12s\n" "----------" "-------" "-----" "----" "----------"

      if command -v jq >/dev/null 2>&1; then
        echo "$resp" | jq -r '.[] | [.id[:18], .project_id[:20], .title[:24], (.message_count // 0 | tostring), .created_by[:12]] | @tsv' | while IFS=$'\t' read -r cid cproj ctitle cmsgs cby; do
          printf "%-18s %-20s %-24s %-8s %-12s\n" "#$cid" "$cproj" "$ctitle" "$cmsgs" "@$cby"
        done
      else
        echo "$resp"
      fi
      ;;
    create)
      local channel_id="" title="" desc="" project_id="knot"
      while [ $# -gt 0 ]; do
        case "$1" in
          -p|--project) project_id="$2"; shift 2 ;;
          -d|--description) desc="$2"; shift 2 ;;
          *)
            if [ -z "$channel_id" ]; then
              channel_id="$1"
            elif [ -z "$title" ]; then
              title="$1"
            fi
            shift
            ;;
        esac
      done

      if [ -z "$channel_id" ]; then
        knot_log_err "Usage: knot chat create <channel_id> [title] [-p project_id] [-d description]"
        exit 1
      fi
      [ -z "$title" ] && title="#$channel_id"

      local payload
      payload="$(jq -n \
        --arg id "$channel_id" \
        --arg p "$project_id" \
        --arg t "$title" \
        --arg d "$desc" \
        --arg cb "$(knot_detect_node_id)" \
        '{id: $id, project_id: $p, title: $t, description: $d, created_by: $cb}')"

      local resp
      resp="$(curl -k -s -X POST -H "Content-Type: application/json" -d "$payload" "$hub_url/chat/conversations")"
      local created_id
      created_id="$(echo "$resp" | jq -r '.id // empty')"
      if [ -n "$created_id" ]; then
        knot_log_ok "Created channel #$created_id under project '$project_id'"
      else
        knot_log_err "Failed to create channel: $(echo "$resp" | jq -r '.error // "unknown error"')"
        exit 1
      fi
      ;;
    post)
      local sender="" conv_id="main"
      while [ $# -gt 0 ]; do
        case "$1" in
          -s|--sender) sender="$2"; shift 2 ;;
          -c|--channel) conv_id="$2"; shift 2 ;;
          *) break ;;
        esac
      done
      local content="$*"
      if [ -z "$content" ]; then
        knot_log_err "Usage: knot chat post [-s sender] [-c channel] <message>"
        exit 1
      fi
      if [ -z "$sender" ]; then
        sender="$(knot_detect_node_id)"
      fi
      local payload
      payload="$(jq -n --arg s "$sender" --arg c "$content" --arg ch "$conv_id" \
        '{sender: $s, content: $c, conv_id: $ch}')"
      local resp
      resp="$(curl -k -s -X POST -H "Content-Type: application/json" -d "$payload" "$hub_url/chat/messages")"
      knot_log_ok "Message posted to #$conv_id as @$sender"
      ;;
    read)
      local conv_id="main" limit=20
      while [ $# -gt 0 ]; do
        case "$1" in
          -c|--channel) conv_id="$2"; shift 2 ;;
          -n|--limit) limit="$2"; shift 2 ;;
          *) shift ;;
        esac
      done
      local resp
      resp="$(curl -k -s "$hub_url/chat/messages?conv_id=$conv_id&limit=$limit")"
      echo -e "${C_BOLD}--- Swarm Konversations: #$conv_id ---${C_RESET}"
      if command -v jq >/dev/null 2>&1; then
        echo "$resp" | jq -r '.[] | "[\(.created_at | todateiso8601 | .[11:19])] @\(.sender): \(.content)"'
      else
        echo "$resp"
      fi
      ;;
    *)
      echo "Usage: knot chat <channels|create|post|read>"
      exit 1
      ;;
  esac
}

cmd_artifact() {
  local action="${1:-list}"
  if [ $# -gt 0 ]; then shift; fi
  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    list)
      echo -e "${C_BOLD}--- Knot 3-State Artifact Leases ---${C_RESET}"
      local resp
      resp="$(curl -k -s "$hub_url/artifacts/leases")"
      if command -v jq >/dev/null 2>&1; then
        printf "%-28s %-20s %-12s %-10s\n" "ARTIFACT" "STATE" "HOLDER" "EXPIRES"
        printf "%-28s %-20s %-12s %-10s\n" "--------" "-----" "------" "-------"
        local now
        now="$(date +%s)"
        echo "$resp" | jq -r --argjson now "$now" '.[] | [.name[:28], .state, (.locked_by // "-"), (if .expires_at then (if .expires_at > $now then ((.expires_at - $now | tostring) + "s") else "expired" end) else "-" end)] | @tsv' | while IFS=$'\t' read -r aname astate aholder aexp; do
          local color="$C_RESET"
          case "$astate" in
            DRAFTING) color="$C_YELLOW" ;;
            LOCKED_SURGERY) color="$C_CYAN" ;;
            VERIFIED_COMMITTED) color="$C_GREEN" ;;
          esac
          printf "%-28s ${color}%-20s${C_RESET} %-12s %-10s\n" "$aname" "$astate" "$aholder" "$aexp"
        done
      else
        echo "$resp"
      fi
      ;;
    lock)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot artifact lock <name> [--ttl <secs>]"
        exit 1
      fi
      local name="$1" ttl=120
      if [ "${2:-}" = "--ttl" ]; then ttl="${3:-120}"; fi
      local node
      node="$(knot_detect_node_id)"
      local payload
      payload="$(jq -n --arg n "$name" --arg nd "$node" --argjson t "$ttl" \
        '{name: $n, node_id: $nd, ttl: $t, state: "LOCKED_SURGERY"}')"
      local resp
      resp="$(curl -k -s -X POST -H "Content-Type: application/json" -d "$payload" "$hub_url/artifacts/lock")"
      if echo "$resp" | grep -q '"ok": true'; then
        knot_log_ok "Acquired lease on '$name' (LOCKED_SURGERY, ${ttl}s) for @$node"
      else
        knot_log_err "Failed to acquire lease: $(echo "$resp" | jq -r '.error // "conflict"')"
        exit 1
      fi
      ;;
    release)
      if [ $# -lt 1 ]; then
        knot_log_err "Usage: knot artifact release <name> [--state <state>]"
        exit 1
      fi
      local name="$1" state="VERIFIED_COMMITTED"
      if [ "${2:-}" = "--state" ]; then state="${3:-VERIFIED_COMMITTED}"; fi
      local node
      node="$(knot_detect_node_id)"
      local payload
      payload="$(jq -n --arg n "$name" --arg nd "$node" --arg s "$state" \
        '{name: $n, node_id: $nd, state: $s}')"
      local resp
      resp="$(curl -k -s -X POST -H "Content-Type: application/json" -d "$payload" "$hub_url/artifacts/release")"
      if echo "$resp" | grep -q '"ok": true'; then
        knot_log_ok "Released lease on '$name' -> state: $state"
      else
        knot_log_err "Failed to release lease: $(echo "$resp" | jq -r '.error // "unknown"')"
        exit 1
      fi
      ;;
    *)
      echo "Usage: knot artifact <list|lock|release>"
      exit 1
      ;;
  esac
}

cmd_web() {
  local action="${1:-open}"
  if [ $# -gt 0 ]; then shift; fi

  local web_dir="$KNOT_ROOT/web"
  if [ ! -d "$web_dir" ]; then
    knot_log_err "Web cockpit directory not found at $web_dir"
    return 1
  fi

  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    open)
      knot_log_info "Opening Knot Kommand Kafe..."
      local target_url="${hub_url}/kafe"
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$target_url" >/dev/null 2>&1 || true
      fi
      echo -e "${C_BOLD}☕ Knot Kommand Kafe:${C_RESET} ${C_CYAN}$target_url${C_RESET}"
      ;;
    dev)
      knot_log_info "Starting Knot Cockpit development server (Vite HMR)..."
      pnpm --dir "$web_dir" dev --host 0.0.0.0 --port 5173
      ;;
    build)
      knot_log_info "Building Knot Cockpit static bundle for production..."
      pnpm --dir "$web_dir" build
      knot_log_ok "Build complete! Static assets saved to web/dist (served directly by knot-hub)."
      ;;
    install)
      knot_log_info "Installing Knot Cockpit npm dependencies..."
      pnpm --dir "$web_dir" install
      knot_log_ok "Dependencies installed."
      ;;
    typecheck)
      pnpm --dir "$web_dir" typecheck
      ;;
    *)
      echo "Usage: knot kafe [open|dev|build|install|typecheck]"
      exit 1
      ;;
  esac
}

cmd_sleep() {
  local action="${1:-status}"
  if [ $# -gt 0 ]; then shift; fi

  local hub_url
  hub_url="$(hub_resolve_url)"

  case "$action" in
    status)
      echo -e "${C_BOLD}--- Knot Swarm Power & Sleep Prevention Status ---${C_RESET}"
      local resp
      if resp="$(curl -k -s --connect-timeout 2 "$hub_url/power/status")" && [ -n "$resp" ]; then
        if command -v jq >/dev/null 2>&1; then
          local swarm_active
          swarm_active="$(echo "$resp" | jq -r '.swarm_active')"
          local reasons
          reasons="$(echo "$resp" | jq -r '.activity.reasons | join(", ") // "none"')"
          local hold_sec
          hold_sec="$(echo "$resp" | jq -r '.activity.manual_hold_sec_remaining // 0')"

          if [ "$swarm_active" = "true" ]; then
            echo -e "Swarm State:       ${C_GREEN}⚡ ACTIVE (Sleep Prevention Enforced)${C_RESET}"
          else
            echo -e "Swarm State:       ${C_GRAY}💤 DORMANT / IDLE (Natural Sleep Permitted)${C_RESET}"
          fi
          echo -e "Activity Drivers:  $reasons"
          if [ "$hold_sec" -gt 0 ]; then
            echo -e "Manual Wake Hold:  ${hold_sec}s remaining"
          fi
          echo ""
          printf "%-14s %-10s %-14s %-18s %-14s\n" "NODE" "STATUS" "ON AC POWER" "SLEEP INHIBITED" "TASK EXECUTING"
          printf "%-14s %-10s %-14s %-18s %-14s\n" "----" "------" "-----------" "---------------" "--------------"

          echo "$resp" | jq -r '.nodes[] | [
            .id,
            .status,
            (if .power.on_ac == true then "YES (Mains)" elif .power.on_ac == false then "NO (Battery)" else "Unknown" end),
            (if .power.sleep_inhibited == true then "ACTIVE (Locked)" else "Inactive" end),
            (if .power.is_executing_task == true then "YES" else "No" end)
          ] | @tsv' | while IFS=$'\t' read -r nid nstatus nac ninhib nexec; do
            printf "%-14s %-10s %-14s %-18s %-14s\n" "$nid" "$nstatus" "$nac" "$ninhib" "$nexec"
          done
        else
          echo "$resp"
        fi
      else
        knot_log_err "Failed to connect to Knot Hub at $hub_url"
        return 1
      fi
      ;;
    prevent|wake|awake)
      local mins="${1:-60}"
      local duration_sec=$((mins * 60))
      knot_log_info "Enforcing wholesale sleep prevention across swarm for ${mins} minutes..."
      local resp
      resp="$(curl -k -s -X POST "$hub_url/swarm/wake" -H "Content-Type: application/json" -d "{\"duration_sec\": $duration_sec}")"
      if echo "$resp" | grep -q '"ok":true'; then
        knot_log_ok "Sleep prevention lock enforced on all nodes on AC power for ${mins} minutes."
      else
        knot_log_err "Failed to set wake hold: $resp"
        return 1
      fi
      ;;
    allow|release)
      knot_log_info "Releasing manual swarm wake hold..."
      local resp
      resp="$(curl -k -s -X POST "$hub_url/swarm/sleep-allow" -H "Content-Type: application/json" -d "{}")"
      if echo "$resp" | grep -q '"ok":true'; then
        knot_log_ok "Manual wake hold released. Swarm will sleep naturally when idle."
      else
        knot_log_err "Failed to release wake hold: $resp"
        return 1
      fi
      ;;
    *)
      echo "Usage: knot sleep <status|prevent [mins]|allow>"
      echo "Aliases: knot power <status|prevent [mins]|allow>"
      exit 1
      ;;
  esac
}


