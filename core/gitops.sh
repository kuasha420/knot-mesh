#!/usr/bin/env bash
set -euo pipefail

# Knot GitOps Hygiene & Conventional Commit Engine

KNOT_ROOT="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
source "$KNOT_ROOT/core/lib.sh"

gitops_ensure_clean() {
  cd "$KNOT_ROOT"
  if [ ! -d .git ]; then
    knot_log_err "Not a git repository: $KNOT_ROOT"
    return 1
  fi
  # Ensure local author identity exists so commits don't fail on fresh OS installs
  local u_name="" u_email=""
  if git config --get user.name >/dev/null; then
    u_name="$(git config --get user.name)"
  fi
  if git config --get user.email >/dev/null; then
    u_email="$(git config --get user.email)"
  fi
  if [ -z "$u_name" ]; then
    git config user.name "$(knot_detect_user)"
  fi
  if [ -z "$u_email" ]; then
    git config user.email "$(knot_detect_user)@$(knot_detect_hostname)"
  fi
}

gitops_current_branch() {
  cd "$KNOT_ROOT"
  local b
  b="$(git branch --show-current)"
  if [ -n "$b" ]; then
    echo "$b"
  else
    echo "main"
  fi
}

gitops_commit() {
  local type="$1"
  local scope="$2"
  local message="$3"
  shift 3
  local files=("$@")

  cd "$KNOT_ROOT"
  gitops_ensure_clean

  for f in "${files[@]}"; do
    if [[ "$f" =~ id_rsa$|id_ed25519$|\.priv$|\.key$ ]]; then
      knot_log_err "CRITICAL SAFETY ABORT: Attempted to stage private key '$f'!"
      return 1
    fi
  done

  git add "${files[@]}"
  local commit_msg="${type}"
  if [ -n "$scope" ]; then
    commit_msg="${type}(${scope}): ${message}"
  else
    commit_msg="${type}: ${message}"
  fi

  git commit -m "$commit_msg"
  knot_log_ok "Committed: $commit_msg"
}

# Locates base git repository directory across standard paths
gitops_find_repo() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    echo ""
    return 1
  fi

  # 1. Direct path check
  local wt_out=""
  if [ -d "$target/.git" ] || { wt_out="$(git -C "$target" rev-parse --is-inside-work-tree 2>&1)" && [ "$wt_out" = "true" ]; }; then
    local top
    if top="$(git -C "$target" rev-parse --show-toplevel 2>&1)"; then
      echo "$top"
      return 0
    fi
  fi

  # 2. Normalized user path check
  local u_home
  u_home="$(knot_detect_user_home)"
  local norm_target
  norm_target="$(knot_path_normalize "$target" "$u_home")"
  local norm_wt=""
  if [ -d "$norm_target/.git" ] || { norm_wt="$(git -C "$norm_target" rev-parse --is-inside-work-tree 2>&1)" && [ "$norm_wt" = "true" ]; }; then
    local top
    if top="$(git -C "$norm_target" rev-parse --show-toplevel 2>&1)"; then
      echo "$top"
      return 0
    fi
  fi

  # 3. Candidate directories search
  local bname
  bname="$(basename "$target")"
  local candidates=(
    "$u_home/Dev/$bname"
    "$u_home/$bname"
    "$u_home/.local/share/$bname"
    "$KNOT_ROOT"
  )
  if [ -d "/home" ]; then
    for u in /home/*; do
      [ -d "$u" ] || continue
      candidates+=("$u/Dev/$bname" "$u/$bname")
    done
  fi

  for c in "${candidates[@]}"; do
    local c_wt=""
    if [ -d "$c/.git" ] || { c_wt="$(git -C "$c" rev-parse --is-inside-work-tree 2>&1)" && [ "$c_wt" = "true" ]; }; then
      local top
      if top="$(git -C "$c" rev-parse --show-toplevel 2>&1)"; then
        echo "$top"
        return 0
      fi
    fi
  done

  return 1
}

# Provisions a local git worktree from base repository WITHOUT duplicate clone
gitops_worktree_add() {
  local repo_input="$1"
  local wt_name_or_path="$2"
  local branch="${3:-}"
  local base_ref="${4:-HEAD}"

  local toplevel
  if ! toplevel="$(gitops_find_repo "$repo_input")"; then
    knot_log_err "Base repository not found for '$repo_input'."
    return 1
  fi

  local u_home
  u_home="$(knot_detect_user_home)"

  local wt_path
  if [[ "$wt_name_or_path" = /* ]] || [[ "$wt_name_or_path" = ~* ]]; then
    wt_path="$(knot_path_normalize "$wt_name_or_path" "$u_home")"
  else
    wt_path="$toplevel/worktrees/$wt_name_or_path"
  fi

  if [ -z "$branch" ]; then
    branch="$(basename "$wt_path")"
  fi

  # Verify target is not an existing full clone
  if [ -d "$wt_path/.git" ] && [ ! -f "$wt_path/.git" ]; then
    knot_log_err "Target '$wt_path' contains a full .git directory. Aborting to avoid corrupting standalone clone."
    return 1
  fi

  local no_psl_link=0
  if [ "${5:-0}" = "1" ] || [ "${5:-}" = "--no-psl-link" ] || [ "${4:-}" = "--no-psl-link" ] || [ "${3:-}" = "--no-psl-link" ]; then
    no_psl_link=1
    if [ "${3:-}" = "--no-psl-link" ]; then
      branch=""
    fi
    if [ "${4:-}" = "--no-psl-link" ]; then
      base_ref="HEAD"
    fi
  fi

  # Check if worktree already registered
  local already_exists=0
  local existing_list
  if existing_list="$(git -C "$toplevel" worktree list --porcelain 2>&1)"; then
    if echo "$existing_list" | grep -q "worktree $wt_path"; then
      already_exists=1
    fi
  fi

  if [ "$already_exists" -eq 0 ]; then
    mkdir -p "$(dirname "$wt_path")"

    # Branch existence check
    local branch_exists=0
    local b_check=""
    if b_check="$(git -C "$toplevel" rev-parse --verify "refs/heads/$branch" 2>&1)"; then
      branch_exists=1
    elif b_check="$(git -C "$toplevel" rev-parse --verify "$branch" 2>&1)"; then
      branch_exists=1
    fi

    local add_out=""
    if [ "$branch_exists" -eq 1 ]; then
      if ! add_out="$(git -C "$toplevel" worktree add "$wt_path" "$branch" 2>&1)"; then
        knot_log_err "Failed to add git worktree: $add_out"
        return 1
      fi
    else
      if ! add_out="$(git -C "$toplevel" worktree add -b "$branch" "$wt_path" "$base_ref" 2>&1)"; then
        knot_log_err "Failed to add git worktree: $add_out"
        return 1
      fi
    fi

    if [ -f "$wt_path/.git" ]; then
      knot_log_ok "Provisioned git worktree at $wt_path (branch: $branch, shared storage zero-clone)."
    else
      knot_log_warn "Worktree provisioned at $wt_path."
    fi
  else
    knot_log_ok "Git worktree already provisioned at $wt_path (shared clone)."
  fi

  # Configure .git/info/exclude in common gitdir and worktree gitdir (Issue #69)
  local common_gitdir=""
  if common_gitdir="$(git -C "$wt_path" rev-parse --git-common-dir 2>&1)"; then
    if [[ "$common_gitdir" != /* ]]; then
      common_gitdir="$(cd "$wt_path" && cd "$common_gitdir" && pwd)"
    fi
  fi

  local wt_gitdir=""
  if wt_gitdir="$(git -C "$wt_path" rev-parse --git-dir 2>&1)"; then
    if [[ "$wt_gitdir" != /* ]]; then
      wt_gitdir="$(cd "$wt_path" && cd "$wt_gitdir" && pwd)"
    fi
  fi

  local exclude_targets=()
  if [ -n "$common_gitdir" ] && [ -d "$common_gitdir" ]; then
    exclude_targets+=("$common_gitdir/info/exclude")
  fi
  if [ -n "$wt_gitdir" ] && [ -d "$wt_gitdir" ] && [ "$wt_gitdir" != "$common_gitdir" ]; then
    exclude_targets+=("$wt_gitdir/info/exclude")
  fi

  local psl_excludes=(
    ".agents"
    ".agents/"
    ".psl"
    ".psl/"
    ".gemini"
    ".gemini/"
    ".cache"
    ".cache/"
    "scratch"
    "scratch/"
  )

  for ex_target in "${exclude_targets[@]}"; do
    mkdir -p "$(dirname "$ex_target")"
    [ -f "$ex_target" ] || touch "$ex_target"
    for pat in "${psl_excludes[@]}"; do
      if ! grep -qxF "$pat" "$ex_target"; then
        echo "$pat" >> "$ex_target"
      fi
    done
  done

  # Link PSL project configurations into new worktree (Issue #69)
  if [ "$no_psl_link" -eq 0 ]; then
    if [ -d "$toplevel/.agents" ] && [ ! -e "$wt_path/.agents" ] && [ ! -L "$wt_path/.agents" ]; then
      ln -s "$toplevel/.agents" "$wt_path/.agents"
      knot_log_ok "Linked PSL .agents/ into $wt_path."
    fi
    if [ -d "$toplevel/.psl" ] && [ ! -e "$wt_path/.psl" ] && [ ! -L "$wt_path/.psl" ]; then
      ln -s "$toplevel/.psl" "$wt_path/.psl"
      knot_log_ok "Linked PSL .psl/ into $wt_path."
    fi
  fi

  echo "$wt_path"
  return 0
}

# Removes git worktree and cleans references
gitops_worktree_remove() {
  local repo_input="$1"
  local wt_name_or_path="$2"
  local force_arg="${3:-0}"
  local force=0
  if [ "$force_arg" = "1" ] || [ "$force_arg" = "--force" ] || [ "$force_arg" = "-f" ]; then
    force=1
  fi

  local toplevel
  if ! toplevel="$(gitops_find_repo "$repo_input")"; then
    knot_log_err "Base repository not found for '$repo_input'."
    return 1
  fi

  local u_home
  u_home="$(knot_detect_user_home)"
  local wt_path
  if [[ "$wt_name_or_path" = /* ]] || [[ "$wt_name_or_path" = ~* ]]; then
    wt_path="$(knot_path_normalize "$wt_name_or_path" "$u_home")"
  else
    wt_path="$toplevel/worktrees/$wt_name_or_path"
  fi

  local opts=()
  if [ "$force" -eq 1 ]; then
    opts+=(-f)
  fi

  if [ -d "$wt_path" ]; then
    local rm_out=""
    if ! rm_out="$(git -C "$toplevel" worktree remove "${opts[@]}" "$wt_path" 2>&1)"; then
      knot_log_err "Failed to remove worktree: $rm_out"
      return 1
    fi
  fi
  local prune_out=""
  prune_out="$(git -C "$toplevel" worktree prune 2>&1)"
  knot_log_ok "Removed worktree at $wt_path."
}

# Lists active git worktrees for a repository
gitops_worktree_list() {
  local toplevel
  if ! toplevel="$(gitops_find_repo "$1")"; then
    knot_log_err "Base repository not found for '$1'."
    return 1
  fi
  echo -e "${C_BOLD}--- Git Worktrees: $(basename "$toplevel") ($toplevel) ---${C_RESET}"
  git -C "$toplevel" worktree list
}

# Provisions git worktree across mesh nodes without duplicate clones
gitops_provision_worktree_mesh() {
  local repo_name="$1"
  local wt_name="$2"
  local branch="${3:-$wt_name}"
  local nodes_arg="${4:-}"
  local base_ref="${5:-HEAD}"
  local no_psl_link_arg="${6:-0}"
  local no_psl_link=0
  if [ "$base_ref" = "--no-psl-link" ] || [ "$no_psl_link_arg" = "1" ] || [ "$no_psl_link_arg" = "--no-psl-link" ]; then
    if [ "$base_ref" = "--no-psl-link" ]; then
      base_ref="HEAD"
    fi
    no_psl_link=1
  fi

  local nodes=()
  if [ -z "$nodes_arg" ] || [ "$nodes_arg" = "--all" ]; then
    local nodes_dir=""
    if nodes_dir="$(knot_get_nodes_dir)"; then
      for mf in "$nodes_dir/"*.json; do
        [ -e "$mf" ] || continue
        nodes+=("$(awk -F'"' '/"id":/ {print $4}' "$mf")")
      done
    fi
  else
    IFS=',' read -ra split_nodes <<< "$nodes_arg"
    for n in "${split_nodes[@]}"; do
      nodes+=("$(echo "$n" | tr -d '[:space:]')")
    done
  fi

  if [ ${#nodes[@]} -eq 0 ]; then
    nodes=("$(knot_detect_node_id)")
  fi

  local my_node_id
  my_node_id="$(knot_detect_node_id)"
  local my_host
  my_host="$(knot_detect_hostname)"

  knot_log_info "Provisioning automated cross-node git worktrees for '$repo_name' ($wt_name)..."

  for node in "${nodes[@]}"; do
    [ -n "$node" ] || continue
    echo -e "\n${C_CYAN}=== Provisioning Worktree on [$node] ===${C_RESET}"
    if [ "$node" = "$my_node_id" ] || [ "$node" = "$my_host" ] || [ "$node" = "local" ] || [ "$node" = "localhost" ]; then
      local local_repo
      if ! local_repo="$(gitops_find_repo "$repo_name")"; then
        knot_log_err "Base clone for '$repo_name' not found on local node ($node)!"
        continue
      fi
      gitops_worktree_add "$local_repo" "$wt_name" "$branch" "$base_ref" "$no_psl_link"
    else
      local remote_cmd="knot worktree add \"$repo_name\" \"$wt_name\" --branch \"$branch\" --base \"$base_ref\""
      if [ "$no_psl_link" -eq 1 ]; then
        remote_cmd="$remote_cmd --no-psl-link"
      fi
      if ! knot exec "$node" "$remote_cmd"; then
        knot_log_warn "Failed to provision worktree on $node"
      fi
    fi
  done
  knot_log_ok "Cross-node git worktree provisioning sweep completed."
}
