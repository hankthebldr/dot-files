#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Installer
# ============================================
# Usage:
#   From inside the repo:  ./install.sh
#   From anywhere:         ./install.sh --path /path/to/dot-files
#   Remote one-liner:      curl -fsSL <url>/install.sh | bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
DOTFILES_DIR="$HOME/.dotfiles"

echo ""
echo "  ╭──────────────────────────────────────╮"
echo "  │  OPEN CLAW — Installing dot-files    │"
echo "  ╰──────────────────────────────────────╯"
echo ""

# Parse args
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --path) SCRIPT_DIR="$2"; shift ;;
        *) break ;;
    esac
    shift
done

# ── Detect: are we running from inside the repo? ────────
if [[ -f "$SCRIPT_DIR/bootstrap.sh" && -f "$SCRIPT_DIR/shell/.zshrc" ]]; then
    echo "  Found Open Claw repo at: $SCRIPT_DIR"

    # Create symlink if needed
    if [[ "$SCRIPT_DIR" != "$DOTFILES_DIR" ]]; then
        if [[ -L "$DOTFILES_DIR" ]]; then
            echo "  Symlink exists: ~/.dotfiles → $(readlink "$DOTFILES_DIR")"
        elif [[ -d "$DOTFILES_DIR" ]]; then
            echo "  ~/.dotfiles already exists (not a symlink). Using it."
            SCRIPT_DIR="$DOTFILES_DIR"
        else
            ln -sf "$SCRIPT_DIR" "$DOTFILES_DIR"
            echo "  Created symlink: ~/.dotfiles → $SCRIPT_DIR"
        fi
    fi

    cd "$SCRIPT_DIR"
    chmod +x bootstrap.sh
    exec bash bootstrap.sh "$@"

# ── Not in repo: try to clone ───────────────────────────
else
    # Install git if missing
    if ! command -v git &>/dev/null; then
        echo "  Installing git..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            xcode-select --install 2>/dev/null || true
        elif command -v apt &>/dev/null; then
            sudo apt update -y && sudo apt install -y git
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y git
        fi
    fi

    # Try to detect repo URL from git remote (if run via curl into a partial clone)
    REPO_URL="${OPENCLAW_REPO_URL:-}"
    if [[ -z "$REPO_URL" ]]; then
        # Check if there's a git remote in CWD
        REPO_URL=$(git -C "$(pwd)" remote get-url origin 2>/dev/null || true)
    fi

    if [[ -z "$REPO_URL" ]]; then
        echo "  ERROR: Not inside the dot-files repo and no OPENCLAW_REPO_URL set."
        echo ""
        echo "  Option 1: Run from inside the cloned repo:"
        echo "    cd /path/to/dot-files && ./install.sh"
        echo ""
        echo "  Option 2: Set the repo URL:"
        echo "    OPENCLAW_REPO_URL=https://github.com/you/dot-files.git ./install.sh"
        echo ""
        exit 1
    fi

    if [[ -d "$DOTFILES_DIR" ]]; then
        echo "  Updating existing installation..."
        cd "$DOTFILES_DIR" && git pull --rebase
    else
        echo "  Cloning to $DOTFILES_DIR..."
        git clone "$REPO_URL" "$DOTFILES_DIR"
    fi

    cd "$DOTFILES_DIR"
    chmod +x bootstrap.sh
    exec bash bootstrap.sh "$@"
fi
