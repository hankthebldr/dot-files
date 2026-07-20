# AI Tool Config Management — opencode & openwork under dot-files

- **Status:** Approved (operator, 2026-07-19)
- **Goal:** Bring the *configuration* of the two AI coding tools already installed
  in the AI profile — **opencode** (v1.17.20, sst/opencode terminal agent) and
  **openwork** (headless OpenWork orchestrator on opencode) — under dot-files as
  a managed, theme-synced component, following the `clin.sh` precedent.
- **Non-goal:** install/invocation (already done — both are `claw` agents,
  installed by `ai-toolchain.sh`, listed in the AI profile help + tool-check).

## Context & constraints (verified 2026-07-19)

- **opencode** config `~/.config/opencode/opencode.jsonc` is currently a stub
  (`{"$schema": "https://opencode.ai/config.json"}`). opencode reads it as a
  clean input; it supports a `theme` key (built-in named themes, plus custom
  themes under `~/.config/opencode/themes/*.json`) and MCP servers. **Clean
  render target.**
- **openwork** config `~/.config/openwork/` holds four files **all rewritten
  together at runtime** (same mtime): `server.json` (workspaces +
  `authorizedRoots`, machine-local abs paths), `runtime-opencode-config.json`
  (generated — bakes in `/Applications/OpenWork.app/...` plugin paths),
  `runtime.sqlite` (runtime state), `tokens.json` (**auth secrets**). openwork
  regenerates the runtime files every launch; `server.json` is also app-written
  when workspaces change in the GUI.
- **Precedent — `scripts/utils/clin.sh`**: renders a tool's config from two
  dot-files sources of truth (active palette via `theme.sh` → `CLAW_C_*`; vault
  path via obsidian resolvers), tops it with a **managed-file sentinel**,
  refuses to clobber a hand-tuned config missing the sentinel unless
  `CLAW_CLIN_MANAGED=force` (opt out with `=0`), and is re-run by `theme.sh set`
  (theme.sh:147-149) so the tool tracks the active palette.
- **Reusable sources**: `_claw_obsidian_vault` → `~/hr-vault-main-pa`;
  `theme.sh` exports `CLAW_C_*`/`CLAW_RGB_*`; `theme.sh` slug for the active
  palette.
- **Latent bug in scope**: `shell/.zshrc:259` hardcodes
  `export PATH=/Users/henry/.opencode/bin:$PATH` — a machine-local `/Users/henry`
  path in the tracked `.zshrc` (the exact leak CLAUDE.md forbids).

## Architecture (Approach B — one engine under `claw ai config`)

```
config/opencode/opencode.base.jsonc   portable base (schema, model/mcp/agent defaults) — tracked
scripts/utils/ai-config.sh            POSIX engine (render/sync/status/setup) — mirrors clin.sh
  ├─ reads: theme.sh → CLAW_C_*, active slug   +   _claw_obsidian_vault → vault path
  ├─ writes: ~/.config/opencode/opencode.jsonc         (base + theme, sentinel line 1)
  ├─ writes: ~/.config/opencode/themes/claw.json       (custom theme, only when no built-in maps)
  └─ writes: ~/.config/openwork/server.json            (rendered roots, "_claw_managed": true)
ai.sh: `config)` arm → ai-config.sh                    surface: claw ai config {render|sync|status|setup}
theme.sh set → ai-config.sh sync                       (added after the clin sync block)
```

Rejected alternatives: **A** (two clin-style modules `opencode.sh`/`openwork.sh`)
collides with the `claw opencode`/`claw openwork` agent-launch dispatch; **C**
(generic `toolconfig.sh` framework) over-engineers for two tools (YAGNI).

## Component 1 — `scripts/utils/ai-config.sh` (the engine)

POSIX `sh`, mirrors `clin.sh` structure. Sentinel:
`AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"`. Managed-file
gate honors `CLAW_AICONFIG_MANAGED` (`1` default / `force` / `0` opt-out).

Subcommands:
- `render <tool> [out]` — emit one tool's config to stdout or `out`.
- `sync` — render both tools' live configs, honoring the managed-file gate.
- `status` — show what's managed, the active theme mapping, and openwork's
  secret/runtime files (presence only, never values).
- `setup` — first-run seed (idempotent): render if missing.

## Component 2 — opencode render

Live `~/.config/opencode/opencode.jsonc` = `config/opencode/opencode.base.jsonc`
(tracked portable content) + a rendered `theme`:

- Slug→built-in map: `tokyo-night`→`tokyonight`, `catppuccin-mocha`→`catppuccin`,
  `gruvbox-material`→`gruvbox`. When a built-in maps, set `"theme": "<name>"`.
- Otherwise render a custom theme to `~/.config/opencode/themes/claw.json` from
  `CLAW_C_*` and set `"theme": "claw"`.
- Line 1 sentinel comment (JSONC permits `//`):
  `// managed by the Open Claw ai-config plugin — do not hand-edit (claw ai config sync)`.
- The base file seeds `$schema` and is the place to add model/provider defaults,
  MCP servers, and agent defs later — all portable, all tracked.

## Component 3 — openwork inputs (seed-and-reconcile)

- `~/.config/openwork/server.json` rendered with:
  - `authorizedRoots` + `workspaces` derived from `_claw_obsidian_vault`
    (the vault) and `~/OpenWork` — **no machine-local literals in the repo**.
  - a `"_claw_managed": true` key as the JSON sentinel (JSON has no comments).
- `sync` writes `server.json` **only if** the on-disk file carries
  `"_claw_managed": true` (ours) or is absent. If openwork/the GUI rewrote it
  (key gone), `sync` **warns and leaves it untouched** — never clobbers the
  operator's GUI workspace edits. `CLAW_AICONFIG_MANAGED=force` overrides.
- `runtime-opencode-config.json` and `runtime.sqlite` are **generated artifacts**
  — never rendered, never managed. Managing the inputs above *is* managing
  openwork fully; hand-authoring a file the app regenerates would only be
  clobbered.

## Component 4 — secrets (`tokens.json`)

Out of the render path entirely: app-written, machine-local, rotating — **never
rendered, never committed, not sops-backed** (managing it would fight the app).
`ai-config status` surfaces its presence (not contents) and prints a one-line
note that `claw secret` is the path if durable backup is ever wanted. No repo
gitignore needed — the runtime files live under `~/.config/openwork/`, outside
the repo tree.

## Component 5 — theme-sync, surfacing, and cleanup

- **Theme hook** — in `theme.sh` immediately after the clin sync block
  (~line 149), add a guarded call: if `ai-config.sh` is readable, run
  `sh ai-config.sh sync >/dev/null 2>&1 || true`. `claw theme set` then re-tints
  opencode with the rest of the environment.
- **AI profile** (`shell/profiles/ai/common.zsh`) — add a help-card line for
  `claw ai config` and a short alias (e.g. `aicfg="claw ai config"`). Tool-check
  already lists opencode/openwork.
- **Install seed** — `scripts/install/ai-toolchain.sh` runs `ai-config setup`
  once after installing opencode/openwork.
- **`.zshrc` PATH fix** — remove the hardcoded `/Users/henry/.opencode/bin` line
  (259) and fold `$HOME/.opencode/bin` into the inline PATH block (step 1) using
  `$HOME`, killing the machine-local leak.

## Testing

bats (`tests/ai-config.bats`), stubbing `theme.sh`/vault resolver into a fake
`DOTFILES_DIR`:
- rendered `opencode.jsonc` parses as valid JSON (comments stripped) and carries
  the sentinel on line 1.
- rendered `server.json` parses and carries `"_claw_managed": true` with the
  fake vault path in `authorizedRoots`.
- managed-file gate: `sync` refuses to overwrite an on-disk config lacking the
  sentinel / `_claw_managed` key (unless `force`).
- slug→opencode-theme mapping resolves the three built-ins and falls back to the
  custom `claw` theme for an unmapped slug.
- `shellcheck -S error` clean; POSIX `sh` (no bashisms).

## Out of scope

- Managing `runtime-opencode-config.json` / `runtime.sqlite` (generated).
- sops-backing `tokens.json`.
- opencode MCP-server curation (the base file is the hook; content is a later
  pass).
- Any change to the agent-launch dispatch (`claw opencode` / `claw openwork`
  keep launching the tools).

## Commit plan

Sensible boundaries: (1) engine + opencode render + base file; (2) openwork
render; (3) theme-sync hook + ai.sh dispatch; (4) AI-profile surfacing +
ai-toolchain seed; (5) `.zshrc` PATH fix; (6) bats tests. Named-file staging;
no PR without ask.
