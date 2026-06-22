#!/usr/bin/env bash
# docs-to-vault.sh — transpose the repo planning corpus into the Obsidian vault.
# Mirrors specs / plans / ADRs / backlog / reference docs (docs/) and the Claude
# harness (claude/) into Github-Projects/dot-files/<category>/ as vault notes with
# provenance frontmatter, plus a planning index. Idempotent (overwrites in place).
# The cloud session can't reach the local vault, so this runs on YOUR machine:
#   bash scripts/utils/docs-to-vault.sh        (or: claw docs-sync)
set -e
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
VAULT="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
[[ -d "$VAULT" ]] || { echo "✗ vault not found: $VAULT (set OBSIDIAN_VAULT)"; exit 1; }
exec python3 "$DOTFILES/scripts/utils/docs-to-vault.py" --dotfiles "$DOTFILES" --vault "$VAULT"
