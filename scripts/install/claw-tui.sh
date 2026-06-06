#!/usr/bin/env bash
# claw-tui.sh — build/install the ratatui front-end to ~/.local/bin.
# Prefers a CI release binary (future); falls back to `cargo build --release`.
set -e
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
DEST="$HOME/.local/bin/claw-tui"; mkdir -p "$HOME/.local/bin"
if command -v cargo &>/dev/null; then
    echo "building claw-tui (release)…"
    (cd "$DOTFILES/tui/claw-tui" && cargo build --release)
    install -m755 "$DOTFILES/tui/claw-tui/target/release/claw-tui" "$DEST"
    echo "✓ installed $DEST  ·  enable with: export CLAW_TUI=1 && exec zsh"
else
    echo "✗ cargo not found — install Rust (claw provision) then re-run"; exit 1
fi
