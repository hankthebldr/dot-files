#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Remote Installer
# ============================================
# One-liner install:
#   curl -fsSL https://raw.githubusercontent.com/<user>/dot-files/master/install.sh | bash
#   -- or with options --
#   curl -fsSL ... | bash -s -- --minimal
#   curl -fsSL ... | bash -s -- --security

set -e

REPO_URL="https://github.com/<user>/dot-files.git"  # TODO: replace with actual repo URL
DOTFILES_DIR="$HOME/.dotfiles"

echo ""
echo "  ╭──────────────────────────────────────╮"
echo "  │  OPEN CLAW — Installing dot-files    │"
echo "  ╰──────────────────────────────────────╯"
echo ""

# 1. Install git if missing
if ! command -v git &>/dev/null; then
    echo "  Installing git..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        xcode-select --install 2>/dev/null || true
    elif command -v apt &>/dev/null; then
        sudo apt update -y && sudo apt install -y git
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y git
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm git
    fi
fi

# 2. Clone repository
if [[ -d "$DOTFILES_DIR" ]]; then
    echo "  Updating existing installation at $DOTFILES_DIR..."
    cd "$DOTFILES_DIR" && git pull --rebase
else
    echo "  Cloning dot-files to $DOTFILES_DIR..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
fi

# 3. Run bootstrap
cd "$DOTFILES_DIR"
chmod +x bootstrap.sh
exec bash bootstrap.sh "$@"
