# AI Tool Config Management — opencode & openwork under dot-files

- **Status:** Approved (operator, 2026-07-19; revised 2026-07-20 after opencode
  theme-mechanism verification — see "Revision" below).
- **Goal:** Bring the *configuration* of the two AI coding tools already installed
  in the AI profile — **opencode** (v1.17.20, sst/opencode terminal agent) and
  **openwork** (headless OpenWork orchestrator on opencode) — under dot-files as
  a **managed, portable, reproducible** component, using the `clin.sh` render /
  sentinel / managed-file mechanism.
- **Non-goal:** install/invocation (already done — both are `claw` agents,
  installed by `ai-toolchain.sh`, listed in the AI profile help + tool-check).

## Revision (2026-07-20) — theme-sync dropped

The original draft mirrored clin's *theme-sync* as well as its mechanism.
Verification killed that premise:

- opencode's config schema (`opencode.ai/config.json`) exposes **no `theme`
  field** — only a per-agent `color` (hex / `primary` / `accent` / …).
- The installed v1.17.20 has **never persisted a theme**; it renders with the
  terminal's ANSI colors by default.
- Ghostty's `theme.conf` already sets the ANSI palette from the active claw
  theme, so **opencode tracks the palette for free via the terminal** — nothing
  to render. openwork's managed config (`server.json`) is workspaces/roots — not
  color-bearing at all.

So neither tool's managed config depends on the palette. The theme-sync hook,
the slug→opencode-theme map, and the custom-theme JSON are **removed**. What
remains is the real value: managed, portable, reproducible config.

## Context & constraints (verified 2026-07-19/20)

- **opencode** config `~/.config/opencode/opencode.jsonc` is a stub
  (`{"$schema": "https://opencode.ai/config.json"}`). Clean render target for a
  portable base (model/provider/MCP/agent defaults live here).
- **openwork** config `~/.config/openwork/` holds four files **all rewritten
  together at runtime**: `server.json` (workspaces + `authorizedRoots`,
  machine-local abs paths), `runtime-opencode-config.json` (generated — bakes in
  `/Applications/OpenWork.app/...` plugin paths), `runtime.sqlite` (runtime
  state), `tokens.json` (**auth secrets**). openwork regenerates the runtime
  files every launch; `server.json` is also app-written on GUI workspace change.
  Current `server.json` workspaces: `~/hr-vault-main-pa` + `~/OpenWork`.
- **Precedent — `scripts/utils/clin.sh`**: renders a tool's config from dot-files
  sources, tops it with a **managed-file sentinel**, and refuses to clobber a
  config missing the sentinel unless `CLAW_CLIN_MANAGED=force` (opt out with
  `=0`). We reuse this *mechanism* (not its theme-sync).
- **Reusable source**: vault path via `_claw_obsidian_vault` (exported as
  `OBSIDIAN_VAULT`; standalone fallback `$HOME/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}`).
- **Latent bug in scope**: `shell/.zshrc:258-259` hardcodes
  `export PATH=/Users/henry/.opencode/bin:$PATH` — a machine-local `/Users/henry`
  path in the tracked `.zshrc`.

## Architecture (Approach B — one engine under `claw ai config`)

```
config/opencode/opencode.base.jsonc   portable base ($schema; model/mcp/agent defaults) — tracked
scripts/utils/ai-config.sh            POSIX engine (render/sync/status/setup) — clin.sh mechanism
  ├─ reads: _claw_obsidian_vault / OBSIDIAN_VAULT → vault path
  ├─ writes: ~/.config/opencode/opencode.jsonc     (base + line-1 JSONC sentinel)
  └─ writes: ~/.config/openwork/server.json         (rendered roots, "_claw_managed": true)
ai.sh: `config)` arm → ai-config.sh               surface: claw ai config {render|sync|status|setup}
```

Rejected alternatives: **A** (two clin-style modules) collides with the
`claw opencode`/`claw openwork` agent-launch dispatch; **C** (generic framework)
over-engineers for two tools (YAGNI).

## Component 1 — `scripts/utils/ai-config.sh` (the engine)

POSIX `sh`, reuses `clin.sh` structure. Sentinel:
`AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"`. Managed-file
gate honors `CLAW_AICONFIG_MANAGED` (`1` default / `force` / `0` opt-out).

Subcommands:
- `render <tool> [out]` — emit one tool's config (`opencode`|`openwork`) to
  stdout or `out`.
- `sync` — render both live configs, honoring the managed-file gate.
- `status` — show what's managed, and openwork's secret/runtime files (presence
  only, never values).
- `setup` — first-run adopt (idempotent): render if missing OR if the on-disk
  file is already ours; seed openwork roots from the existing `server.json` so
  no GUI-added workspace is lost.

## Component 2 — opencode config (portable base; color via terminal)

Live `~/.config/opencode/opencode.jsonc` = `config/opencode/opencode.base.jsonc`
(tracked portable content) with a line-1 JSONC sentinel comment:
`// managed by the Open Claw ai-config plugin — do not hand-edit (claw ai config sync)`.

- The base seeds `$schema` and is the home for portable model/provider defaults,
  MCP servers, and agent defs. No theme field is set (opencode has none; color
  comes from the terminal ANSI palette, which `claw theme set` already updates
  via Ghostty).
- Managed-file gate: `sync` refuses to overwrite a file lacking the line-1
  sentinel unless `CLAW_AICONFIG_MANAGED=force`.

## Component 3 — openwork inputs (seed-and-reconcile)

- `~/.config/openwork/server.json` rendered with `authorizedRoots` + `workspaces`
  derived from `_claw_obsidian_vault`/`OBSIDIAN_VAULT` (the vault) and
  `~/OpenWork` — **no machine-local literals in the repo** — plus a
  `"_claw_managed": true` key as the JSON sentinel (JSON has no comments).
- `sync` writes `server.json` **only if** the on-disk file carries
  `"_claw_managed": true` (ours) or is absent. If openwork/the GUI rewrote it
  (key gone), `sync` **warns and leaves it** — never clobbers GUI workspace
  edits. `CLAW_AICONFIG_MANAGED=force` overrides. `setup` seeds our roots by
  merging the existing file's workspaces so first-adopt is lossless.
- `runtime-opencode-config.json` and `runtime.sqlite` are **generated artifacts**
  — never rendered, never managed.

## Component 4 — secrets (`tokens.json`)

Out of the render path entirely: app-written, machine-local, rotating — **never
rendered, never committed, not sops-backed** (managing it would fight the app).
`ai-config status` surfaces its presence (not contents) and notes `claw secret`
is the path if durable backup is ever wanted. No repo gitignore needed — the
runtime files live under `~/.config/openwork/`, outside the repo.

## Component 5 — surfacing, install seed, and the cleanup

- **Dispatch** — `scripts/utils/ai.sh` gains a `config)` arm →
  `bash ai-config.sh "$@"`; the `ai.sh` usage line adds `config`. Surface:
  `claw ai config {render|sync|status|setup}`.
- **AI profile** (`shell/profiles/ai/common.zsh`) — add a help-card line for
  `claw ai config` and a short alias `aicfg="claw ai config"`. Tool-check already
  lists opencode/openwork.
- **Install seed** — `scripts/install/ai-toolchain.sh` runs `ai-config setup`
  once after installing opencode/openwork.
- **`.zshrc` PATH fix** — remove the hardcoded `/Users/henry/.opencode/bin` line
  (258-259) and fold `$HOME/.opencode/bin` into the inline PATH block (step 1,
  near lines 30-31) using `$HOME`, guarded by `[[ -d ]]`.

## Testing

bats (`tests/ai-config.bats`), stubbing the vault resolver into a fake
`DOTFILES_DIR`/`OBSIDIAN_VAULT`:
- rendered `opencode.jsonc` parses as valid JSON (comments stripped) and carries
  the sentinel on line 1.
- rendered `server.json` parses and carries `"_claw_managed": true` with the
  fake vault path in `authorizedRoots`.
- managed-file gate: `sync` refuses to overwrite an on-disk config lacking the
  sentinel / `_claw_managed` key (unless `force`).
- `setup` seeds openwork roots from an existing `server.json` without dropping a
  pre-existing extra workspace.
- `shellcheck -S error` clean; POSIX `sh` (no bashisms).

## Out of scope

- opencode theme rendering (color tracks the terminal ANSI palette that
  `claw theme set` already updates).
- Managing `runtime-opencode-config.json` / `runtime.sqlite` (generated).
- sops-backing `tokens.json`.
- opencode MCP-server curation (the base file is the hook; content is a later
  pass).
- Any change to the agent-launch dispatch (`claw opencode` / `claw openwork`
  keep launching the tools).

## Commit plan

Sensible boundaries: (1) engine + opencode render + base file; (2) openwork
render + seed-and-reconcile; (3) ai.sh dispatch + AI-profile surfacing;
(4) ai-toolchain seed; (5) `.zshrc` PATH fix; (6) bats tests. Named-file
staging; no PR without ask.
