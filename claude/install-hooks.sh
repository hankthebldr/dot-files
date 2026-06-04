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


def ensure(event: str, matcher: str, command: str) -> bool:
    """Additively register one hook command. Never clobbers existing entries.

    - Reuses an existing matcher block if present (appends our command unless
      it's already there) instead of replacing the whole array.
    - Idempotent: re-running makes no change once registered.
    Returns True if anything changed.
    """
    entries = hooks.setdefault(event, [])
    for entry in entries:
        if entry.get("matcher") == matcher:
            hlist = entry.setdefault("hooks", [])
            if any(h.get("command") == command for h in hlist):
                return False
            hlist.append({"type": "command", "command": command})
            return True
    entries.append({"matcher": matcher,
                    "hooks": [{"type": "command", "command": command}]})
    return True


changed = False
changed |= ensure("PreToolUse", "Bash", "python3 ~/.claude/hooks/pre_tool_use.py")
changed |= ensure("PostToolUse", "*", "python3 ~/.claude/hooks/post_tool_use.py")

if changed:
    p.write_text(json.dumps(data, indent=2) + "\n")
    print(f"✓ hooks merged into {p} (existing hooks preserved)")
else:
    print(f"= hooks already present in {p} — no change")
PY

echo "✓ backup: $BACKUP_DIR/settings.json"
echo "Restart Claude Code to load hooks."
