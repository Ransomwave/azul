#!/usr/bin/env bash
set -euo pipefail # strict mode (fail on errors, undefined vars, and failed pipes)

PROG_NAME=$(basename "$0")
FORCE=0

usage() {
  cat <<EOF
Usage: $PROG_NAME [--force|-f]

Installs Azul on Linux systems. This script will:
  - ensure Node.js and npm are available (attempt to install using the host package manager)
  - run 'npm ci' in the repository root
  - run 'npm run build'
  - run 'npm install -g .'

Options:
  -f, --force   Run non-interactively and assume yes to all prompts
  -h, --help    Show this help
EOF
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

find_repo_root() {
  local dir
  dir=$(pwd)
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/package.json" || -d "$dir/.git" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  echo "$(pwd)"
}

install_node_with_pkgmgr() {
  if command_exists apt-get; then
    echo "Using apt-get to install nodejs/npm..."
    sudo apt-get update
    sudo apt-get install -y nodejs npm
    return 0
  fi
  if command_exists dnf; then
    echo "Using dnf to install nodejs/npm..."
    sudo dnf install -y nodejs npm
    return 0
  fi
  if command_exists pacman; then
    echo "Using pacman to install nodejs/npm..."
    sudo pacman -Syu --noconfirm nodejs npm
    return 0
  fi
  if command_exists apk; then
    echo "Using apk to install nodejs/npm..."
    sudo apk add nodejs npm
    return 0
  fi
  if command_exists brew; then
    echo "Using Homebrew to install node..."
    brew install node
    return 0
  fi
  return 1
}

refresh_shell_cache() {
  # Bash/zsh: clear the command hash table
  if command_exists hash; then
    hash -r || true
  fi
}

main() {
  # parse args
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -f|--force) FORCE=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1"; usage; exit 2 ;;
    esac
  done

  echo "=== Azul: Linux Easy Install ==="

  if [[ $FORCE -eq 0 ]]; then
    read -r -p "Install Azul on this machine? (Y/N) " ans
    case "$ans" in
      [Yy]* ) ;;
      * ) echo "Aborted."; exit 0 ;;
    esac
  else
    echo "Running non-interactive (force) mode."
  fi

  if ! command_exists node || ! command_exists npm; then
    if [[ $FORCE -eq 0 ]]; then
      read -r -p "Node.js/npm not found on PATH. Attempt to install via package manager? (Y/N) " ans
      case "$ans" in
        [Yy]* ) ;;
        * ) echo "Please install Node.js (https://nodejs.org/) and re-run this script."; exit 1 ;;
      esac
    fi

    if ! install_node_with_pkgmgr; then
      echo "Could not install Node.js automatically. Please install Node.js/npm manually and re-run this script." >&2
      exit 1
    fi

    refresh_shell_cache

    if ! command_exists node || ! command_exists npm; then
      echo "Node still not found after package manager install. You may need to open a new shell. Please re-run this script once Node is available." >&2
      exit 1
    fi
  else
    echo "Node.js detected. Skipping Node installation."
  fi

  REPO_ROOT=$(find_repo_root)
  echo "Using repository root: $REPO_ROOT"

  pushd "$REPO_ROOT" >/dev/null
  trap 'popd >/dev/null' EXIT

  if [[ $FORCE -eq 0 ]]; then
    read -r -p "Install dependencies, build, and install Azul globally now? (Y/N) " ans
    case "$ans" in
      [Yy]* ) ;;
      * ) echo "Aborted."; exit 0 ;;
    esac
  fi

  echo "Installing dependencies (npm ci)..."
  npm ci

  echo "Building (npm run build)..."
  npm run build

  echo "Installing globally (npm install -g .)..."
  if npm install -g .; then
    echo "Azul installed successfully."
  else
    echo "Global install failed. You may need to run: sudo npm install -g . or configure npm for non-root global installs." >&2
    exit 1
  fi

  echo "Installation complete. Try running 'azul --help'."
}

main "$@"
