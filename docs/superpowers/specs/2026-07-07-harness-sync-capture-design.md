# Harness Sync & Capture — Design

**Date:** 2026-07-07
**Status:** Approved (design) — pending implementation plan
**Scope owner:** Henry
**Related:** `claude/harness/README.md`, `scripts/utils/harness.sh`, `scripts/setup/link-claude.sh`

## Problem

Custom agentic artifacts (skills, slash commands, subagents, plugins, MCP
servers) get created and installed **locally** on the primary Mac, but only the
ones already living under `claude/harness/{skills,commands,agents}/` flow to
other machines. Everything else — a skill authored ad-hoc into `~/.claude/skills`,
an enabled marketplace plugin, a local MCP server, a remote connector like
`vault-os` — is stranded on one machine.

Goal: make the dotfiles repo the **single portable source of truth** for the
custom harness, in both directions:

- **Capture** — pull locally-made/installed artifacts *into* the tracked repo.
- **Distribute** — a `git pull` + deploy on another machine (BD790i) makes them
  available there, natively.

## Non-goals

- Syncing third-party marketplace *bundle contents* (those re-install from their
  own marketplace; we only record *which* are enabled).
- Carrying remote-connector **auth** across machines (account-side; impossible
  via git). We record intent + a re-enable checklist only.
- Replacing the marketplace/plugin system. We use it as-is.

## Background: how Claude Code actually loads these

Established by inspection on 2026-07-07:

| Thing | Where it lives | Portable as |
|---|---|---|
| Skill / command / agent (file) | `~/.claude/{skills,commands,agents}/<name>` | files (symlink into repo) |
| Plugin bundle | marketplace dir; `.claude-plugin/marketplace.json` | **local marketplace** in repo |
| Which plugins are on | `~/.claude/settings.json` → `enabledPlugins: {"name@mkt": true}` | tracked config (manifest) |
| Registered marketplaces | `~/.claude/plugins/known_marketplaces.json` (supports **local dir source**) | tracked config (deploy registers) |
| Local MCP server | `~/.claude.json` / `claude/mcp.json` (`command`,`args`,`env`) | config w/ `${ENV}` refs (manifest) |
| Remote connector (e.g. `vault-os`) | claude.ai account connectors | **not file-portable** — checklist only |

`~/.claude/skills/` today has three feeders; only two are repo-tracked:
`harness/skills` ✓, `claude/skills` ✓, and `.agents/skills/*` +
`plugins/cache/*` (marketplace-managed symlinks — **must be left alone** by
capture).

## Approved decisions

1. **Plugins → local marketplace.** `harness/marketplace/` is a repo-owned local
   marketplace. Deploy registers it and flips `enabledPlugins`.
2. **Capture → move + symlink.** Back up the real dir, move it into the repo,
   replace with a symlink. One source of truth, keeps working instantly.
3. **Capture acts by default** — keep it simple. `--dry-run` is an opt-in
   preview flag. Safety comes from backups, not from a confirm gate.
4. **No secrets in git.** Secret-looking env values are redacted to `${VAR}`
   refs; literal-looking secrets are flagged, not written.
5. **Everything hangs off the existing spine** — `claw harness` dispatcher +
   `scripts/utils/harness.sh` engine + `scripts/setup/link-claude.sh` deployer.
   No parallel dispatcher, no second updater front door.

## Architecture

```
                    ┌─────────────────────── repo (git, portable) ───────────────────────┐
                    │  claude/harness/                                                     │
   capture  ◀───────┤    skills/  commands/  agents/     ← plain-file artifacts            │
  (this Mac)        │    marketplace/                    ← local marketplace (plugins)     │
                    │      .claude-plugin/marketplace.json                                 │
                    │      <plugin>/ …                                                      │
                    │    manifest.json                   ← MCP defs · enabled plugins ·    │
                    │                                       remote-connector checklist     │
                    └──────────────────────────────────────────────────────────────────────┘
                    deploy  ▶  (any machine: BD790i)
```

Three verbs on `claw harness`, one engine:

- `capture [--dry-run]` — **new.** local → repo (+ manifest).
- `deploy [--dry-run]` — **extended.** repo → machine (files + marketplace +
  enabledPlugins + MCP merge + connector checklist).
- `sync [--dry-run]` — **unchanged front door.** `git pull --ff-only` + deploy.

## Component 1 — Capture (`harness_capture` in `harness.sh`)

**Purpose:** turn ad-hoc local state into tracked repo state. Idempotent; acts
by default (backs up before every mutation); `--dry-run` previews without
touching anything.

**Inputs:** `~/.claude/{skills,commands,agents}`, `~/.claude.json`,
`claude/mcp.json`, `~/.claude/settings.json`, `~/.claude/plugins/known_marketplaces.json`.

**Algorithm (files):**
1. For `kind` in skills, commands, agents — for each entry in `~/.claude/<kind>`:
   - **Skip** if: a symlink (already deployed or marketplace-managed), name
     starts with `.` or `_`, or its realpath resolves inside the repo,
     `.agents/`, or `plugins/cache/`.
   - Otherwise it is a **real, untracked** artifact → candidate.
2. For each candidate (default action):
   - Back up to `~/.dotfiles-backups/<ts>/claude/<kind>/<name>`.
   - `mv` into `claude/harness/<kind>/<name>`.
   - Recreate `~/.claude/<kind>/<name>` as a symlink to the repo path.
3. `--dry-run` prints the plan (`would capture: skill 'foo'`) and touches nothing.

**Algorithm (manifest):** a Python helper (`scripts/utils/harness-manifest.py`,
invoked by `harness.sh`) reads the configs and (re)writes `manifest.json`:
- `mcpServers`: local (`command`+`args`) servers only; each `env` value that
  matches a secret heuristic (`*_TOKEN`, `*_KEY`, `*_SECRET`, high-entropy) is
  rewritten to `${ORIGINAL_KEY}` and the pairing recorded; literal secrets that
  can't be mapped are **listed as warnings, not written**.
- `enabledPlugins`: copied verbatim from `settings.json` (both official + local).
- `connectors`: remote connectors (not local `command`-based) recorded as
  `{name, reenable: "claude.ai → Settings → Connectors"}`.
- Merge, don't overwrite: preserve manual manifest edits; only add/update keys
  the scan owns.

**Output:** summary table (captured files, manifest additions, redactions,
warnings). Non-zero exit if a literal secret was found (forces Henry to fix).

## Component 2 — Local marketplace (`harness/marketplace/`)

- `.claude-plugin/marketplace.json` — lists bundled plugins (name, source =
  local subdir, description). Regenerated by `harness new plugin` and by capture
  when a new bundle is added.
- One dir per plugin, real CC plugin shape (`.claude-plugin/plugin.json`,
  `commands/`, `agents/`, `skills/`).
- Migration: the existing `_templates/plugin` shape is updated to the real
  `.claude-plugin/plugin.json` layout; `harness new plugin` scaffolds into
  `marketplace/<name>/` and appends to `marketplace.json`.

## Component 3 — Deploy extension (`link-claude.sh`)

Existing item-level symlinking of skills/commands/agents is **unchanged**. Added
steps (all idempotent, all honor `--dry-run`):

1. **Marketplace register.** If `harness/marketplace/.claude-plugin/marketplace.json`
   exists, ensure an entry in `~/.claude/plugins/known_marketplaces.json` with a
   local-directory source pointing at the repo path. Skip if already present.
2. **Enable plugins.** For each key in manifest `enabledPlugins`, set it `true`
   in `~/.claude/settings.json` (JSON-merge; never remove existing keys).
3. **MCP merge.** For each manifest `mcpServers` entry, add it to the machine's
   MCP config **only if absent**; resolve `${ENV}` refs from the environment,
   and **warn (don't write)** if a referenced env var is unset. Never clobber an
   existing server of the same name.
4. **Connector checklist.** Print each manifest `connectors[]` as an actionable
   line: `⚠ enable 'vault-os' via claude.ai → Settings → Connectors`.

Writes to `settings.json` / `known_marketplaces.json` / MCP config back up the
target first and use a JSON-aware merge (Python helper), never `echo >>`.

## Data flow

```
CAPTURE (Mac):   ~/.claude state ──scan──▶ back up ──▶ repo files + manifest.json ──▶ git commit
DISTRIBUTE (BD): git pull ──▶ deploy: symlink files
                                     + register marketplace
                                     + enable plugins
                                     + merge MCP (env-resolved)
                                     + print connector checklist
```

## Manifest schema (`claude/harness/manifest.json`)

```json
{
  "version": 1,
  "generatedAt": "2026-07-07T00:00:00Z",
  "mcpServers": {
    "example-local": {
      "command": "npx",
      "args": ["-y", "some-mcp"],
      "env": { "SOME_API_KEY": "${SOME_API_KEY}" }
    }
  },
  "enabledPlugins": { "code-review@claude-plugins-official": true },
  "connectors": [
    { "name": "vault-os", "reenable": "claude.ai → Settings → Connectors" }
  ]
}
```

## Error handling & safety

- **Backups** before every `mv` and every JSON write, to
  `~/.dotfiles-backups/<ts>/`.
- **Idempotent** everywhere: re-running capture or deploy is a no-op when
  already in sync.
- **Secret guard:** literal secrets abort the manifest write for that entry with
  a clear message; nothing secret reaches git.
- **Never clobber:** MCP merge and enabledPlugins are additive; existing machine
  state is preserved. Marketplace registration is skip-if-present.
- **Offline-safe / SSH-safe:** capture and deploy never depend on network; no
  stdout pollution during non-interactive shell init (they're explicit commands,
  not sourced).
- **Cross-platform:** use `platform.zsh` shims and `$HOMEBREW_PREFIX`; JSON via
  `python3` (already a repo dependency).

## Testing

- **Capture dry-run:** on a scratch `CLAUDE_HOME`, seed a fake real skill + a
  fake marketplace symlink; assert only the real one is a candidate and the
  symlink is skipped.
- **Capture --apply:** assert backup created, dir moved into repo, symlink
  points back, second run is a no-op.
- **Secret redaction:** seed an MCP env with `FOO_TOKEN=sk-literal`; assert it is
  flagged, not written, and exit is non-zero.
- **Deploy marketplace/enable:** on a scratch `CLAUDE_HOME`, assert marketplace
  registered once, `enabledPlugins` keys set true, existing keys preserved.
- **Deploy MCP merge:** assert absent server added with env resolved; unset env
  warns; existing same-name server untouched.
- **Connector checklist:** assert each connector prints an actionable line.

Scratch-home pattern: set `CLAUDE_HOME`/`CLAUDE_DST` to a temp dir (engine
already honors `CLAUDE_HOME`).

## Open items for the plan

- Exact machine MCP config target (`~/.claude.json` vs `claude mcp add`): confirm
  the write surface Claude Code reads on both macOS and Linux.
- Whether `known_marketplaces.json` local source key is `{source:"directory",
  path}` or another shape — verify against a locally-registered dir before
  writing.
- README + `claw harness --help` + welcome-TUI entry updates.

## Surfaces to update

- `bin/claw` help text (`harness <cmd>` line) + `cmd_harness` (no change; passes
  through).
- `scripts/utils/harness.sh` — add `capture`, extend `main` dispatch.
- `scripts/setup/link-claude.sh` — add marketplace/enable/MCP/connector steps.
- `scripts/utils/harness-manifest.py` — new JSON helper.
- `claude/harness/README.md` — document capture + marketplace + manifest.
- `claude/harness/_templates/plugin/` — update to real `.claude-plugin` shape.
