#!/usr/bin/env bash
# docs-to-vault.sh — mirror repo design docs into the Obsidian vault.
# The cloud session can't reach the local vault, so docs live in the repo and
# this syncs them on YOUR machine into Github-Projects/dot-files/.
#   bash scripts/utils/docs-to-vault.sh        (or: claw docs-sync)
set -e
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
VAULT="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
DEST="$VAULT/Github-Projects/dot-files"
[[ -d "$VAULT" ]] || { echo "✗ vault not found: $VAULT (set OBSIDIAN_VAULT)"; exit 1; }
mkdir -p "$DEST"
# Sync the design/spec docs (markdown) the agent produces.
for f in ULTRAPLAN.md AUDIT.md ratatui-plan.md claude-config-boundaries.md; do
    [[ -f "$DOTFILES/docs/$f" ]] && cp "$DOTFILES/docs/$f" "$DEST/$f" && echo "✓ $f → $DEST"
done
echo "synced repo docs → $DEST"
