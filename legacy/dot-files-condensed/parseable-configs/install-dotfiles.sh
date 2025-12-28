#!/bin/bash
# Dotfiles installation script
# Usage: ./install-dotfiles.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"

echo 'Installing dotfiles...'

# Backup existing dotfiles
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Install .yarnrc
if [ -f "$HOME/.yarnrc" ]; then
    cp "$HOME/.yarnrc" "$BACKUP_DIR/"
    echo 'Backed up existing .yarnrc'
fi
cp "$DOTFILES_DIR/.yarnrc" "$HOME/.yarnrc"
echo 'Installed .yarnrc'

# Install .zshrc
if [ -f "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$BACKUP_DIR/"
    echo 'Backed up existing .zshrc'
fi
cp "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
echo 'Installed .zshrc'

# Install .zprofile
if [ -f "$HOME/.zprofile" ]; then
    cp "$HOME/.zprofile" "$BACKUP_DIR/"
    echo 'Backed up existing .zprofile'
fi
cp "$DOTFILES_DIR/.zprofile" "$HOME/.zprofile"
echo 'Installed .zprofile'

# Install .vimrc
if [ -f "$HOME/.vimrc" ]; then
    cp "$HOME/.vimrc" "$BACKUP_DIR/"
    echo 'Backed up existing .vimrc'
fi
cp "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"
echo 'Installed .vimrc'

# Install .gitconfig
if [ -f "$HOME/.gitconfig" ]; then
    cp "$HOME/.gitconfig" "$BACKUP_DIR/"
    echo 'Backed up existing .gitconfig'
fi
cp "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
echo 'Installed .gitconfig'

echo 'Dotfiles installation complete!'
echo 'Backups saved to: $BACKUP_DIR'
