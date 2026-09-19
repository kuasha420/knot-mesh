#!/usr/bin/env bash
set -euo pipefail

# Swarm Council: Stage 0 Tool & Fleet Availability Audit
# Probes online nodes for gh, git, knot, agy, model connectivity, and repo write access

REPO="${1:-}"
if [ -z "$REPO" ]; then
  if git_remote="$(git config --get remote.origin.url 2>/dev/null)"; then
    REPO="$(echo "$git_remote" | sed -E 's#.*github\.com[:/]([^/]+/[^/.]+)(\.git)?#\1#')"
  fi
  REPO="${REPO:-kuasha420/knot-mesh}"
fi

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
KNOT_ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd -P)"

KNOT_BIN=""
if [ -x "$KNOT_ROOT/bin/knot" ]; then
  KNOT_BIN="$KNOT_ROOT/bin/knot"
elif command -v knot >/dev/null 2>&1; then
  KNOT_BIN="$(command -v knot)"
elif [ -x "$HOME/.local/bin/knot" ]; then
  KNOT_BIN="$HOME/.local/bin/knot"
fi

# Discover online nodes
nodes=()
if [ -n "$KNOT_BIN" ] && [ -x "$KNOT_BIN" ]; then
  while read -r node_id; do
    [ -n "$node_id" ] || continue
    nodes+=("$node_id")
  done < <("$KNOT_BIN" status 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$5 == "ONLINE" {print $1}')
fi

if [ ${#nodes[@]} -eq 0 ]; then
  nodes=("$(hostname -s)")
fi

audit_results="{"
audit_results+="\"target_repo\":\"$REPO\","
audit_results+="\"nodes\":{"

node_count=${#nodes[@]}
idx=0

sync_settings_cmd="python3 -c 'import json, os; p1=os.path.expanduser(\"~/.gemini/config/config.json\"); p2=os.path.expanduser(\"~/.gemini/antigravity-cli/settings.json\"); [json.dump((lambda d: (d.setdefault(\"userSettings\",{}).update({\"useAiCredits\":False,\"useG1Credits\":False,\"themeMode\":\"THEME_MODE_DARK\"}), d)[1])(json.load(open(p1))), open(p1,\"w\"), indent=2) for _ in [1] if os.path.exists(p1)]; [json.dump((lambda d: (d.update({\"useAiCredits\":False,\"useG1Credits\":False,\"accepted_latest_terms_of_service\":True,\"theme\":\"dark\",\"theme_mode\":\"THEME_MODE_DARK\"}), d)[1])(json.load(open(p2))), open(p2,\"w\"), indent=2) for _ in [1] if os.path.exists(p2)]'"

for node in "${nodes[@]}"; do
  idx=$((idx + 1))
  is_local=0
  if [ "$node" = "$(hostname -s)" ] || [ "$node" = "desktop" ] || [ "$node" = "localhost" ]; then
    is_local=1
  fi

  status="READY"
  gh_ok=true
  git_ok=true
  knot_ok=true
  agy_ok=true
  auth_ok=true
  models_ok=true

  if [ $is_local -eq 1 ]; then
    if command -v secret-tool >/dev/null 2>&1; then
      if sec_out="$(secret-tool search service gemini 2>/dev/null)"; then
        sec_token="$(echo "$sec_out" | awk -F'secret = ' '/^secret = / {print $2}' | head -n1)"
        if [ -n "$sec_token" ]; then
          echo "$sec_token" > "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
          chmod 600 "$HOME/.gemini/antigravity-cli/antigravity-oauth-token"
        fi
      fi
    fi
    if ! eval "$sync_settings_cmd" >/dev/null 2>&1; then
      status="DEGRADED"
    fi

    command -v gh >/dev/null 2>&1 || { gh_ok=false; status="DEGRADED"; }
    command -v git >/dev/null 2>&1 || { git_ok=false; status="DEGRADED"; }
    command -v knot >/dev/null 2>&1 || [ -n "$KNOT_BIN" ] || { knot_ok=false; status="DEGRADED"; }
    command -v agy >/dev/null 2>&1 || { agy_ok=false; status="DEGRADED"; }
    gh auth status >/dev/null 2>&1 || { auth_ok=false; status="DEGRADED"; }
    timeout 5 agy --version >/dev/null 2>&1 || { models_ok=false; status="DEGRADED"; }
  else
    if ! "$KNOT_BIN" exec "$node" "$sync_settings_cmd" >/dev/null 2>&1; then
      status="DEGRADED"
    fi

    if ! timeout 5 "$KNOT_BIN" exec "$node" "which gh >/dev/null 2>&1"; then gh_ok=false; status="DEGRADED"; fi
    if ! timeout 5 "$KNOT_BIN" exec "$node" "which git >/dev/null 2>&1"; then git_ok=false; status="DEGRADED"; fi
    if ! timeout 5 "$KNOT_BIN" exec "$node" "which knot >/dev/null 2>&1 || [ -x ~/.local/bin/knot ]"; then knot_ok=false; status="DEGRADED"; fi
    if ! timeout 5 "$KNOT_BIN" exec "$node" "which agy >/dev/null 2>&1 || [ -x ~/.local/bin/agy ]"; then agy_ok=false; status="DEGRADED"; fi
    if ! timeout 5 "$KNOT_BIN" exec "$node" "gh auth status >/dev/null 2>&1"; then auth_ok=false; status="DEGRADED"; fi
    if ! timeout 8 "$KNOT_BIN" exec "$node" "PATH=\"\$HOME/.local/bin:\$PATH\" agy --version >/dev/null 2>&1"; then models_ok=false; status="DEGRADED"; fi
  fi

  audit_results+="\"$node\":{"
  audit_results+="\"status\":\"$status\","
  audit_results+="\"gh\":$gh_ok,"
  audit_results+="\"git\":$git_ok,"
  audit_results+="\"knot\":$knot_ok,"
  audit_results+="\"agy\":$agy_ok,"
  audit_results+="\"auth\":$auth_ok,"
  audit_results+="\"models\":$models_ok"
  audit_results+="}"
  if [ $idx -lt $node_count ]; then
    audit_results+=","
  fi
done

audit_results+="}}"

echo "$audit_results"
