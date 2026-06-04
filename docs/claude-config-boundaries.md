# Claude Code (CLI) vs Claude Desktop — Config Boundaries

> Policy: **on macOS, prefer Claude Desktop for any config it manages.** The
> dot-files repo only owns CLI-only concerns.

## The two apps own different surfaces

| Surface | Owner | Location |
|---|---|---|
| MCP server registry (which servers the AI can call) | **Desktop** (when installed) | `~/Library/Application Support/Claude/Claude Extensions/` |
| Desktop preferences (sidebar, browser actions, trusted folders) | **Desktop** | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Pre/Post tool-use hooks (Bash gates, telemetry) | **CLI** | `~/.claude/settings.json` + `~/.claude/hooks/` |
| Slash commands | **CLI** | `~/.claude/commands/` |
| User memory (CLAUDE.md) | **CLI** | `~/.claude/CLAUDE.md` |
| Pentest scope allowlist | **CLI** (Open Claw) | `~/.claude/scope.txt` |
| Plugin marketplace state | **CLI** | `~/.claude/settings.json` `enabledPlugins` |

Claude Code (CLI) and Claude Desktop are separate apps. Installing an
extension in Desktop does NOT make it available in CLI, and vice versa.
**Don't try to bridge them** — pick one per concern.

## What this repo manages — and what it doesn't

**Symlinks the dot-files creates into `~/.claude/`:**

| Symlink | Owner | Status |
|---|---|---|
| `~/.claude/CLAUDE.md` | dot-files | ✅ keep |
| `~/.claude/hooks/` | dot-files | ✅ keep |
| `~/.claude/commands/` | dot-files | ✅ keep |
| `~/.claude/scope.txt` | dot-files | ✅ keep |
| `~/.claude/mcp.json` | ~~dot-files~~ | ❌ **removed** (Desktop owns MCP on macOS) |

**Files dot-files writes into surgically (additive merge, never clobber):**

- `~/.claude/settings.json` — Claude Code owns this file, so we never overwrite
  it. `claude/install-hooks.sh` performs a **surgical merge**: it appends our
  `PreToolUse` (Bash) and `PostToolUse` (`*`) hook commands into the existing
  arrays, reusing a matcher block if present and skipping anything already
  registered. Other keys, other matchers, and any hooks you or a plugin added
  are preserved. A timestamped backup is written to `~/.dotfiles-backups/`
  first, and re-running is a no-op.

**Files dot-files explicitly does NOT manage:**

- `~/.claude.json` — user state (theme, history); CLI manages
- `~/Library/Application Support/Claude/*` — Desktop's territory. The one
  exception is `scripts/utils/mcp-manager.sh`, an **interactive** TUI: only when
  you choose "add server" does it edit `claude_desktop_config.json` (the
  documented Desktop MCP config), and it does so atomically (`jq … > tmp && mv`).
  Nothing writes there during `bootstrap.sh` or any unattended flow.

## Applying the policy

Run [`scripts/utils/claude-config-policy.sh`](../scripts/utils/claude-config-policy.sh).
Idempotent — safe to re-run on any machine.

```bash
bash scripts/utils/claude-config-policy.sh           # show diff
bash scripts/utils/claude-config-policy.sh --apply   # actually change things
```

The script's behavior:

1. **macOS + Claude Desktop installed** → ensure `~/.claude/mcp.json` is NOT
   symlinked into this repo. Removes the symlink if found. Leaves any
   non-symlink file at that path alone (would only exist if you intentionally
   put something there).
2. **Linux (no Desktop available)** → no-op. The mcp.json symlink is
   harmless here because there's no competing Desktop registry.
3. **Other CLI-only symlinks** → never touched.

## If you need a CLI-side MCP server

Don't put it in `~/.claude/mcp.json` (the path we just severed). Use
Claude Code's canonical mechanism instead:

```bash
# Project-scoped (writes to ./.mcp.json):
claude mcp add <name> <command>

# User-scoped (writes to ~/.claude/settings.json `mcpServers`):
claude mcp add --user <name> <command>
```

This keeps dot-files out of the loop entirely.

## On BD790i (Ubuntu)

No Claude Desktop on Linux as of 2026-05. The CLI is the only player, and
there's no conflict to manage. The policy script no-ops on Linux.

If/when Claude Desktop ships for Linux, revisit this doc.
