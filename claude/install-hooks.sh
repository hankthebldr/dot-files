#!/usr/bin/env bash
# Idempotently register Claude Code hooks in ~/.claude/settings.json.
# Run once per fresh box, after `claude/` is symlinked into `~/.claude/`.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
[[ -f "$SETTINGS" ]] || { echo "✗ $SETTINGS not found — is Claude Code installed?"; exit 1; }

BACKUP_DIR="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$SETTINGS" "$BACKUP_DIR/settings.json"

python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / ".claude" / "settings.json"
data = json.loads(p.read_text())
hooks = data.setdefault("hooks", {})
hooks["PreToolUse"] = [{
    "matcher": "Bash",
    "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/pre_tool_use.py"}],
}]
hooks["PostToolUse"] = [{
    "matcher": "*",
    "hooks": [{"type": "command", "command": "python3 ~/.claude/hooks/post_tool_use.py"}],
}]
p.write_text(json.dumps(data, indent=2) + "\n")
print(f"✓ hooks registered in {p}")
PY

echo "✓ backup: $BACKUP_DIR/settings.json"
echo "Restart Claude Code to load hooks."
