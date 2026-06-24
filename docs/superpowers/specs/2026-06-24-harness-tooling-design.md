# Harness Tooling Upgrade — Design

**Date:** 2026-06-24
**Status:** Approved — pending implementation plan
**Scope:** Sub-project **A** of a 4-part harness/skills expansion (A tooling · B fill slots · C net-new skills · D deepen existing). A is the foundation; B/C/D ride on it and get their own spec → plan → build cycles.

## Goal

Make the `claw harness` authoring/management loop substantially better so adding and maintaining custom agentic tooling (skills, slash commands, subagents, plugins) is fast and consistent across the Mac and the BD790i. Three concrete capabilities:

1. **Scaffold any type** — `claw harness new` can create skills, commands, subagents, and plugins (today: skills only).
2. **Rich discovery** — `claw harness list` shows each item's description/trigger and deploy state (today: names + ✓/○ only).
3. **Cross-machine sync** — one command to pull + redeploy the harness across endpoints (today: separate `git pull` then `claw harness deploy`).

## Non-Goals (YAGNI)

- **Validation gate** — wiring `scan-skills.sh` into `deploy`/pre-commit was deselected for this build. `scan-skills.sh` stays a standalone tool.
- **`~/.agents/skills` capture** — the 11 third-party skills stay machine-local and re-installable; `sync` does not pull them into the repo.
- **Plugin auto-deploy** — plugins remain "referenced, manual" per `claude/harness/README.md`; `new plugin` scaffolds the bundle but `deploy` does not link it.
- Sub-projects B/C/D — separate specs.

## Architecture decision

**Extract a `scripts/utils/harness.sh` engine; keep `cmd_harness` in `bin/claw` a thin dispatcher.**

This matches the repo's spine: `bin/claw` routes, and substantial subsystems live as engines under `scripts/utils/` (`theme.sh`, `ai-services.sh`, `tunnel-manager.sh`, `clin.sh`). `deploy` already delegates to `scripts/setup/link-claude.sh`, so the precedent is set. Growing `cmd_harness` inline would bloat the dispatcher with frontmatter-parsing and git logic. `cmd_harness` becomes: parse subcommand → dispatch to `harness.sh` (or `link-claude.sh` for `deploy`).

Rejected alternative: keep everything inline in `bin/claw`. Simpler file count, but violates the one-engine-per-subsystem pattern and makes the list/sync logic hard to test in isolation.

## CLI surface

Additions in **bold**; the rest is unchanged and back-compatible.

```
claw harness new <kind> <name>     # kind ∈ skill | command | agent | plugin
claw harness new <name>            # bare = skill (back-compat preserved)
claw harness list [--all] [--fzf]  # rich: name · description · deploy state
claw harness sync [--dry-run]      # git pull --ff-only + redeploy, one step
claw harness deploy [--dry-run]    # unchanged (wraps link-claude.sh)
claw harness path                  # unchanged
```

## Feature 1 — Scaffold any type

Templates live in `claude/harness/_templates/` (`_`-prefixed → the deployer skips it, so templates never deploy):

| Kind | Template | Creates | Deploy target |
|------|----------|---------|---------------|
| skill | `_templates/SKILL.md` | `harness/skills/<name>/SKILL.md` | `~/.claude/skills/<name>` |
| command | `_templates/command.md` | `harness/commands/<name>.md` | `~/.claude/commands/<name>.md` |
| agent | `_templates/agent.md` | `harness/agents/<name>.md` | `~/.claude/agents/<name>.md` |
| plugin | `_templates/plugin/` | `harness/plugins/<name>/` | (manual — not auto-linked) |

`harness_new <kind> <name>`: validate `kind`; refuse if the target already exists; copy the template; substitute `<name>` into the frontmatter (`name:` / filename); print the next step (`edit it, then: claw harness deploy`). Bare `new <name>` defaults `kind=skill`. The existing `harness/skills/_template/SKILL.md` migrates into `_templates/` (single template home).

Template frontmatter is Claude Code-correct:
- **agent.md** — `name`, `description` ("Use this agent when…"), `tools` list.
- **command.md** — `description` (the `/<name>` trigger) + a `$ARGUMENTS` body stub.
- **SKILL.md** — unchanged from today's `_template` (`name`, `description` as "Use when…").

## Feature 2 — Rich discovery

`harness_list` walks `harness/{skills,commands,agents,plugins}`, and for each item parses the frontmatter `description:` (from `SKILL.md` for skills, the `.md` for commands/agents, the manifest for plugins). Renders per kind:

```
skills
  ✓ docsync            Project-aware sync between a GitHub repo, its Things 3 …
  ○ my-new-skill       Use when …
```

`✓`/`○` = deployed (a link exists at `~/.claude/<kind>/<name>`) or not. Flags:
- `--all` — also walk `claude/skills/` (security) and `claude/agent-skills/` (vendored), so `list` is a full inventory of every skill source, not just the harness.
- `--fzf` — pipe the rows through `fzf` with a preview pane showing the item's `SKILL.md`/`.md`. Reuses `claw_theme_fzf` so it tracks the active palette.

Description parsing is a small awk/sed helper in `harness.sh` (read frontmatter block, extract `description:`, collapse to one line, truncate to terminal width).

## Feature 3 — Cross-machine sync

`harness_sync [--dry-run]`:

1. `git -C "$DOTFILES" pull --ff-only` — fast-forward only. If the local branch has diverged it stops with a clear message (don't auto-merge a convenience command into dotfiles history).
2. `bash scripts/setup/link-claude.sh` — redeploy onto the freshly-pulled tree.
3. Print a summary: commits pulled (`git log` range) + what `link-claude.sh` linked/backed-up.

`--dry-run` → `git fetch` + show the incoming range, and `link-claude.sh --dry-run`, mutating nothing. Ordering is **pull-then-deploy** so the deploy operates on updated content. `~/.agents/skills` is untouched.

## File manifest

| File | Change |
|------|--------|
| `scripts/utils/harness.sh` | **new** — engine: `harness_new`, `harness_list`, `harness_sync` + helpers |
| `bin/claw` | `cmd_harness` slimmed to a dispatcher that calls `harness.sh`; add `sync`; route `new <kind>` |
| `claude/harness/_templates/SKILL.md` | **moved** from `harness/skills/_template/SKILL.md` |
| `claude/harness/_templates/command.md` | **new** template |
| `claude/harness/_templates/agent.md` | **new** template |
| `claude/harness/_templates/plugin/` | **new** skeleton (manifest + README) |
| `claude/harness/README.md` | document `new <kind>`, `list --all/--fzf`, `sync` |
| `docs/claw.md` | refresh the `claw harness` reference |

## Error handling

- `new`: unknown `kind` → usage + non-zero exit. Existing target → refuse (no clobber). Missing template → clear error.
- `list`: an item missing/empty `description:` → render `(no description)`, don't fail the whole listing. No `fzf` on PATH with `--fzf` → fall back to the plain list + a hint.
- `sync`: non-ff (diverged) → stop, print the divergence and the manual reconcile path; never auto-merge. Not a git repo / no network → clear error, deploy not attempted.

## Testing

- `bash -n` syntax check on `harness.sh` and `bin/claw`.
- `new <kind> <name>` for each kind into a temp `CLAUDE_HOME`/harness root → assert the file lands with the name substituted; re-run → assert no-clobber.
- `list` against a fixture harness → assert descriptions + deploy markers; `--all` includes the other sources.
- `sync --dry-run` → assert it fetches and reports without mutating (no new commits, no links changed).
- Cross-platform: `harness.sh` uses `#!/usr/bin/env bash`, `set -euo pipefail`, `logger.sh`, and `platform.zsh` conventions (no raw `pbcopy`/`open`).

## Acceptance criteria

1. `claw harness new agent foo` / `command foo` / `plugin foo` / `skill foo` each scaffold the right file from a template; bare `new foo` still makes a skill.
2. `claw harness list` shows descriptions + deploy state; `--all` covers all three skill sources; `--fzf` browses with a preview.
3. `claw harness sync` pulls (ff-only) and redeploys in one step, with a change summary; `--dry-run` mutates nothing.
4. `bin/claw` stays a thin dispatcher; all real logic is in `scripts/utils/harness.sh`.
5. Back-compat: existing `new <name>`, `list`, `deploy`, `path` behave as before.
