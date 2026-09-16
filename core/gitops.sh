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
