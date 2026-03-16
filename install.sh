#!/usr/bin/env bash
# codex-switch installation script

set -euo pipefail

# Colors for output
GREEN='\033[32m'
CYAN='\033[36m'
YELLOW='\033[33m'
RESET='\033[0m'

# Project directory
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Installation directory
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"

# Data directory
DATA_DIR="${DATA_DIR:-$HOME/.codex-switch}"

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${YELLOW}Missing required command: $cmd${RESET}"
        return 1
    fi
}

detect_bash_major() {
    bash -c 'printf "%s" "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo "0"
}

echo ""
echo -e "${CYAN}codex-switch${RESET}"
echo ""
echo "This script installs codex-switch into your local bin directory."
echo ""

require_command bash
require_command jq

if [[ "$(detect_bash_major)" -lt 4 ]]; then
    echo -e "${YELLOW}WARNING: codex-switch expects bash 4+ on PATH.${RESET}"
    echo "Current 'bash' is older than 4. On macOS, install a newer bash first."
    echo ""
fi

# Check if installation directory exists
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}Creating installation directory: $INSTALL_DIR${RESET}"
    mkdir -p "$INSTALL_DIR"
fi

# Create symlink to bin/codex-switch
BIN_SRC="$PROJECT_DIR/bin/codex-switch"
BIN_DST="$INSTALL_DIR/codex-switch"

if [[ -L "$BIN_DST" ]]; then
    echo "Removing existing symlink: $BIN_DST"
    rm "$BIN_DST"
elif [[ -e "$BIN_DST" ]]; then
    echo -e "${YELLOW}Refusing to overwrite existing file: $BIN_DST${RESET}"
    echo "Remove it manually or set INSTALL_DIR to a different location."
    exit 1
fi

echo "Creating symlink: $BIN_DST -> $BIN_SRC"
ln -s "$BIN_SRC" "$BIN_DST"

# Make executable
chmod +x "$BIN_DST"
chmod +x "$BIN_SRC"

# Create data directory
echo "Creating data directory: $DATA_DIR"
mkdir -p "$DATA_DIR/profiles"

# Create index.json if it doesn't exist
if [[ ! -f "$DATA_DIR/index.json" ]]; then
    echo '{"profiles":{}}' > "$DATA_DIR/index.json"
fi

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${YELLOW}WARNING: $INSTALL_DIR is not in your PATH${RESET}"
    echo ""
    echo "Add the following to your ~/.zshrc:"
    echo ""
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "Then run: source ~/.zshrc"
    echo ""
fi

echo ""
echo -e "${GREEN}Installation complete!${RESET}"
echo ""
echo "Installed to: $BIN_DST"
echo "Data directory: $DATA_DIR"
echo ""
echo "Usage:"
echo "  codex-switch save --label personal   Save current auth as a profile"
echo "  codex-switch use --label work        Switch to a profile (recommended)"
echo "  codex-switch load --label work       Alias of use"
echo "  codex-switch list                    List all profiles"
echo "  codex-switch status                  Show current profile"
echo "  codex-switch openclaw-use [work]     Switch OpenClaw to current Codex auth or a saved profile"
echo "  codex-switch update                  Download the latest codex-switch and reinstall it"
echo "  codex-switch doctor                  Show Codex/OpenClaw auth health"
echo "  codex-switch delete --label work     Delete a profile"
echo ""
echo "For more info: codex-switch --help"
echo ""
