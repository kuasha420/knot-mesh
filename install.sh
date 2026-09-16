#!/usr/bin/env bash
set -euo pipefail

# Knot Mesh Standalone Bootstrap Installer
# curl -fsSL https://raw.githubusercontent.com/kuasha420/knot-mesh/main/install.sh | bash

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_GREEN=$'\033[1;32m'
C_CYAN=$'\033[1;36m'
C_YELLOW=$'\033[1;33m'
C_RED=$'\033[1;31m'
C_DIM=$'\033[2m'

INSTALL_DIR="${KNOT_INSTALL_DIR:-$HOME/.local/share/knot-mesh}"
BIN_DIR="${KNOT_BIN_DIR:-$HOME/.local/bin}"
REPO_URL="${KNOT_REPO_URL:-https://github.com/kuasha420/knot-mesh.git}"
BRANCH="${KNOT_BRANCH:-main}"

print_banner() {
  cat << BANNER_EOF
${C_CYAN}${C_BOLD}
  ██╗  ██╗███╗   ██╗ ██████╗ ████████╗   ███╗   ███╗███████╗███████╗██╗  ██╗
  ██║ ██╔╝████╗  ██║██╔═══██╗╚══██╔══╝   ████╗ ████║██╔════╝██╔════╝██║  ██║
  █████═╝ ██╔██╗ ██║██║   ██║   ██║█████╗██╔████╔██║█████╗  ███████╗███████║
  ██╔═██╗ ██║╚██╗██║██║   ██║   ██║╚════╝██║╚██╔╝██║██╔══╝  ╚════██║██╔══██║
  ██║ ╚██╗██║ ╚████║╚██████╔╝   ██║      ██║ ╚═╝ ██║███████╗███████║██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝    ╚═╝      ╚═╝     ╚═╝╚══════╝╚══════╝╚═╝  ╚═╝
${C_RESET}${C_DIM}         Distributed Workspace Mesh for Arch Linux / KDE Plasma 6 Wayland${C_RESET}
BANNER_EOF
}

check_dependencies() {
  echo -e "\n${C_CYAN}[•] Checking system dependencies...${C_RESET}"
  local missing=()
  local required_cmds=("git" "python3" "ssh" "openssl" "ip")

  for cmd in "${required_cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null; then
      missing+=("$cmd")
    fi
  done

  # Check for deskflow or deskflow-core
  if ! command -v deskflow-core >/dev/null && ! command -v deskflow >/dev/null; then
    missing+=("deskflow")
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo -e "${C_YELLOW}[!] Missing required packages/tools: ${missing[*]}${C_RESET}"
    if [ -f "/etc/arch-release" ] && command -v sudo >/dev/null && [ -t 0 ]; then
      read -r -p "Install missing packages via pacman now? [Y/n] " install_confirm
      if [[ ! "${install_confirm,,}" =~ ^n ]]; then
        sudo pacman -S --needed --noconfirm "${missing[@]}"
      fi
    else
      echo -e "${C_YELLOW}[!] Please ensure ${missing[*]} are installed via your package manager.${C_RESET}"
    fi
  else
    echo -e "${C_GREEN}[✓] Core dependencies satisfied.${C_RESET}"
  fi
}

install_repo() {
  echo -e "\n${C_CYAN}[•] Installing Knot Mesh to: ${C_BOLD}${INSTALL_DIR}${C_RESET}..."

  if [ -d "$INSTALL_DIR/.git" ]; then
    echo -e "${C_CYAN}[•] Existing repository found, updating to latest ${BRANCH}...${C_RESET}"
    git -C "$INSTALL_DIR" fetch origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
  elif [ -d "$INSTALL_DIR" ]; then
    echo -e "${C_YELLOW}[!] Directory exists but is not a git repo: $INSTALL_DIR${C_RESET}"
  else
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
  fi

  echo -e "${C_GREEN}[✓] Knot Mesh codebase ready.${C_RESET}"
}

setup_symlinks() {
  echo -e "\n${C_CYAN}[•] Creating command symlinks in: ${C_BOLD}${BIN_DIR}${C_RESET}..."
  mkdir -p "$BIN_DIR"

  ln -sf "$INSTALL_DIR/bin/knot" "$BIN_DIR/knot"
  ln -sf "$INSTALL_DIR/bin/knot-installer" "$BIN_DIR/knot-installer"

  chmod +x "$INSTALL_DIR/bin/knot" "$INSTALL_DIR/bin/knot-installer"

  echo -e "${C_GREEN}[✓] Symlinked 'knot' and 'knot-installer' -> ${BIN_DIR}${C_RESET}"

  # Check PATH
  if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo -e "\n${C_YELLOW}${C_BOLD}[!] Notice: ${BIN_DIR} is not in your PATH.${C_RESET}"
    echo -e "    Add it by appending this to your shell profile (~/.bashrc or ~/.zshrc):"
    echo -e "    ${C_CYAN}export PATH=\"\$HOME/.local/bin:\$PATH\"${C_RESET}"
  fi
}

interactive_onboarding() {
  if [ ! -t 0 ]; then
    return 0
  fi

  echo -e "\n${C_GREEN}${C_BOLD}======================================================================${C_RESET}"
  echo -e "${C_GREEN}${C_BOLD}                 KNOT MESH INSTALLED SUCCESSFULLY                     ${C_RESET}"
  echo -e "${C_GREEN}${C_BOLD}======================================================================${C_RESET}"
  echo -e "How would you like to configure this machine?"
  echo -e "  ${C_BOLD}[1] Anchor Workstation${C_RESET}  (Hub, KVM server, central control plane)"
  echo -e "  ${C_BOLD}[2] Strand Device${C_RESET}       (Laptop / handheld client to join a swarm)"
  echo -e "  ${C_BOLD}[3] Skip for now${C_RESET}        (I will configure manually later)"
  read -r -p "Select option [1-3] (3): " choice

  case "${choice:-3}" in
    1)
      "$BIN_DIR/knot-installer" init
      ;;
    2)
      echo -e "\nEnter the Anchor endpoint and join token provided by the Anchor:"
      read -r -p "Anchor Address (e.g. 192.168.1.50:4242): " ep
      read -r -p "Join Token: " tok
      if [ -n "$ep" ] && [ -n "$tok" ]; then
        "$BIN_DIR/knot-installer" join "$ep" "$tok"
      fi
      ;;
    *)
      echo -e "\nYou can configure at any time by running:"
      echo -e "  ${C_BOLD}knot-installer init${C_RESET}  (on Anchor)"
      echo -e "  ${C_BOLD}knot-installer join <endpoint> <token>${C_RESET}  (on Strand)\n"
      ;;
  esac
}

main() {
  print_banner
  check_dependencies
  install_repo
  setup_symlinks
  interactive_onboarding
}

main "$@"
