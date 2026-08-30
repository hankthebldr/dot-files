# claw update — one engine, phased daily ops (design)

**Date:** 2026-08-17
**Status:** Approved (design) → implementation plan `docs/superpowers/plans/2026-08-17-claw-update-one-engine.md`
**Author:** Henry + Claude
**Related:** `docs/superpowers/specs/2026-06-30-claw-upgrade-streaming-ux-design.md` (streaming chrome this design reuses), CLAUDE.md "The Spine"

## Problem

`claw update` presents as the one updater front door (spine contract), but behind
the door there are **four separate update engines with divergent coverage**:

| Entry point | Engine | Coverage |
|---|---|---|
| `claw update` / `upgrade` | `system-update.sh` | hand-rolled sweep (apt/dnf/brew/npm/pipx/uv/gem/rustup/omz/fwupd…) |
| `claw update --tools` + silent login daemon | `tool-updater.sh` | hardcoded curated list (`CATEGORIES` at `tool-updater.sh:30`), per-category cache |
| `claw pkg update` | `pkg-manifest.sh` | topgrade if installed, else a *different* hand-rolled sweep |
| weekly timer (`claw update --schedule`) | `selfupdate.sh` → `pkg-manifest.sh update` | same as above |

Consequences:

1. **Manual and scheduled updates run different engines** — same machine,
   different results depending on which door you walked through.
2. **No update path ever pulls the dotfiles repo.** The only `git pull` in the
   tree is scoped to `harness.sh`; `selfupdate` (despite the name) updates
   packages, not the dotfiles. Multi-machine drift until a manual pull, and the
   derived-artifact chain (integrity manifest, gen-fastfetch, stow, link-claude)
   never re-runs.
3. **Two tool registries.** `tool-updater.sh`'s hardcoded `CATEGORIES` is a
   parallel registry to `config/manifest/tools.list` (the self-declared
   "self-aware registry") — exactly the parallel-dispatcher pattern the spine
   forbids.
4. **Update state is invisible.** `situation.sh` (cached-JSON spine + tick/notify)
   and the fastfetch dashboards (`ff-readout.sh fields`) carry no
   "N packages outdated / repo behind by M" signal. `validate` detects repo-behind
   but only when run by hand.
5. Frictions: sudo password prompt fires mid-run (first apt step); `go clean
   -modcache` is a cache wipe, not an update; `gem update --system` never updates
   installed gems; no `--dry-run`; no receipt of what a run did; the weekly timer
   fails silently into a log file while `notify.sh` (the one notification engine)
   sits unused.

## Decisions (locked with operator)

1. **One package engine: `system-update.sh`, topgrade-first.** When `topgrade`
   is installed, `system-update.sh` runs it (streamed via `claw_step`) with a
   repo-shipped declarative config `config/topgrade.toml`; the existing
   hand-rolled sweep survives only as the no-topgrade fallback (with the fixes
   in decision 7). All other doors route here.
2. **`claw update` gains phases: repo → packages.** Phase 1 is a new
   `scripts/utils/repo-sync.sh` (ff-only pull + conditional regen of derived
   artifacts). Phase 2 is the one engine. `selfupdate`'s timer runs the same
   phased front door (`bin/claw update --non-interactive`), so scheduled ≡ manual.
   `claw pkg update` becomes a delegating alias (muscle memory preserved).
3. **Registry merge.** `tools.list` grows an **optional third field**
   `id|source|cadence` (cadence ∈ `daily|weekly|biweekly|monthly`). Only entries
   *with* a cadence tag are in `tool-updater.sh`'s background fast lane —
   curation is kept, but it lives in the one registry. The hardcoded
   `CATEGORIES` array remains solely as a fallback when the manifest is missing
   or carries no cadence entries.
4. **Update state becomes data.** A new `scripts/utils/update-status.sh` probes
   pending-update counts (brew outdated, apt upgradable, repo ahead/behind,
   last-run) into `~/.cache/claw/updates.json` (atomic, self-throttled to ≥6h
   unless `--force`). `situation.sh probe` merges it as `.updates`;
   `ff-readout.sh` exposes an `updates` field; `claw doctor` prints it; the
   welcome TUI kicks a background refresh at login. `situation tick` notifies
   (info tier) on the *rising edge* of repo-behind only.
5. **Every run leaves a receipt.** One TSV line per run in
   `~/.cache/claw/updates.tsv` (ts, trigger, duration, result, detail).
   `claw update --last` pretty-prints recent runs. The weekly timer's failure
   path fires `notify.sh send --crit`.
6. **repo-sync is conservative.** ff-only; a dirty tree or diverged branch skips
   the pull with a clear message (never auto-stash, never merge). Regen runs
   only for what the pull actually changed (`git diff --name-only old..new`):
   `gen-fastfetch.py` changed → re-run generator; `shell/` changed → `stow -R
   shell` (failure → hint `claw restore-shell`, non-fatal); `claude/` changed →
   `link-claude.sh`; any pull → `integrity generate` (quiet).
7. **Sweep fixes** (fallback path): `sudo -v` upfront + keepalive when a
   sudo-needing manager exists; drop `go clean -modcache`; `gem update --system`
   → `gem update` (user gems, incl. colorls); `--dry-run` prints the step plan
   without executing.
8. **Login kick stays** (`welcome-tui.zsh`), now dual-purpose: fast-lane tools
   *and* a background `update-status.sh --refresh` so dashboards stay fresh.
   Retiring the kick in favor of the timer is explicitly deferred.

## Architecture

```
                 ┌──────────────────────────────────────────────┐
                 │           bin/claw  cmd_update               │
                 │  update [--repo|--packages|--dry-run|--last] │
                 └───────┬──────────────────────┬───────────────┘
        phase 1          │                      │        phase 2
  ┌──────────────────────▼───┐        ┌─────────▼──────────────────┐
  │ scripts/utils/repo-sync  │        │ scripts/utils/system-update│
  │ ff-only pull → regen     │        │ topgrade --config … (one   │
  │ (gen-fastfetch·stow·     │        │ streamed step) ⤳ fallback: │
  │  link-claude·integrity)  │        │ fixed hand-rolled sweep    │
  └──────────┬───────────────┘        └─────────┬──────────────────┘
             │      receipts: ~/.cache/claw/updates.tsv
             ▼                                  ▼
  ┌────────────────────────────────────────────────────────────────┐
  │ scripts/utils/update-status.sh → ~/.cache/claw/updates.json    │
  │  read by: situation.sh (.updates) · ff-readout (updates field) │
  │           claw doctor · welcome TUI login kick                 │
  └────────────────────────────────────────────────────────────────┘

  timers:  selfupdate.sh (weekly)  → bin/claw update --non-interactive
  fast lane: tool-updater.sh       → cadence-tagged rows of tools.list
  alias:   claw pkg update         → system-update.sh (delegation note)
```

### Interfaces (contracts between components)

- `system-update.sh` argv: `--non-interactive`, `--dry-run`. Exit 0 = all steps
  ok, ≠0 = at least one step failed. Writes its own receipt row
  (`trigger` from `CLAW_UPDATE_TRIGGER` env, default `manual`).
- `repo-sync.sh` argv: `--dry-run`. Prints `repo: <old>..<new>` on pull,
  `repo: up-to-date`, or `repo: skipped (<reason>)`. Exit 0 unless git itself
  errors. Writes a receipt row.
- `update-status.sh` argv: `--refresh` (respect 6h throttle), `--force`,
  `read [--json]`. JSON shape:
  `{"ts":"…","brew":N|null,"apt":N|null,"repo_behind":N|null,"repo_ahead":N|null,"last_run":EPOCH|null}`
  Missing manager ⇒ `null`, never 0. All probes `timeout`-guarded (macOS shim as
  in `situation.sh`).
- `tools.list` row: `id|source[|cadence]`. Existing 2-field rows stay valid
  everywhere (`pkg-manifest.sh` parsers already `IFS='|' read -r id src _`).
- Receipt TSV row: `ISO-ts \t trigger \t duration_s \t ok|fail \t detail`.

### Cadence → seconds

`daily=86400 · weekly=604800 · biweekly=1209600 · monthly=2592000` (matches the
current hardcoded intervals; `fast` is not a cadence — daily is the floor).

### Seed cadence tags (preserving today's curated set)

`eza bat zoxide fd ripgrep bottom zellij → |weekly` (brew) ·
`rovr osint-d2 → |weekly` (pipx) · `clawea → |biweekly` (go) ·
`netwatch-tui eilmeldung → |monthly` (cargo).

## Out of scope

Hand-maintained fastfetch jsonc rows, p10k prompt segment, retiring the login
kick, auto-stash/rebase in repo-sync, per-tool (vs per-category) cache
granularity, `claw pkg` manifest install changes.

## Testing

`bats` suites per component (`tests/update-engine.bats`, `tests/repo-sync.bats`,
`tests/tool-updater.bats`, `tests/update-status.bats`) using PATH-stub fakes for
`topgrade`/`brew`/`apt-get` and fixture git repos for repo-sync; every touched
script passes `shellcheck -x`; bash-3.2-safe constructs only (stock macOS).
