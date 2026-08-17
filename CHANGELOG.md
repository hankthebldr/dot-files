# Changelog

All notable changes to this project are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Phased `claw update` — one engine: phase 1 `scripts/utils/repo-sync.sh`
  (conservative ff-only pull of the dotfiles repo; a dirty tree or diverged
  branch skips with a reason, never auto-stash/merge; regen only of what the
  pull changed — gen-fastfetch, `stow -R shell`, link-claude, integrity
  manifest), phase 2 topgrade-first `system-update.sh` (one streamed
  `claw_step` run under the repo-shipped `config/topgrade.toml`; the
  hand-rolled sweep survives only as the no-topgrade fallback). New flags:
  `--repo` / `--packages` (single phase), `--dry-run` (plan only, executes
  nothing), `--last` (recent run receipts)
- Update receipts: every run — manual or timer — appends one TSV row
  (ISO timestamp, trigger, duration, ok|fail, detail) to
  `~/.cache/claw/updates.tsv`; `claw update --last` pretty-prints them
- Update state as data: new `scripts/utils/update-status.sh` probes brew/apt
  pending counts + repo ahead/behind + last run into
  `~/.cache/claw/updates.json` (atomic, self-throttled to ≥6h unless
  `--force`; absent manager = null, never 0) — merged by `situation.sh probe`
  as `.updates` (info-notify on the rising edge of repo-behind), exposed as
  the `updates` field in `ff-readout.sh`, printed by `claw doctor`, and
  refreshed in the background at login by the welcome TUI
- Registry merge: optional third field in `config/manifest/tools.list`
  (`id|source|cadence`, cadence `daily`/`weekly`/`biweekly`/`monthly`); the
  tool-updater background fast lane now runs only cadence-tagged rows of the
  one registry, keeping the hardcoded category list solely as the fallback
  when the manifest is missing or carries no tagged rows
- Streaming step runner `claw_step` + themed `claw_ui_*` chrome in
  `claw-progress.sh` — `claw update` / `claw update --tools` now stream every
  install step live (viewport that collapses on success, retained on failure,
  tee'd to a logfile) instead of hiding output under `gum spin`
- HR-TRUST homelab lab board: 4-node `fleet.yml` (ms-01/r630/bd790i/pihole) with
  `cluster{}` + per-service `group`/`glyph`, new `dns` + Host-header `http`
  probe kinds and a non-tailnet reachability fallback in `situation.sh`, and a
  shared theme-aware renderer `homelab-board.sh` wired into the `local` +
  `homelab` fastfetch dashboards and cache-first `hstatus`
- `gemini-cli` (`@google/gemini-cli`) installed by `ai-toolchain.sh` and
  pre-registered in the `claw` agents.toml seed — `claw gemini` works
  from any profile out of the box; surfaced in ai/cortex/default help
  blocks (694e49e, cea228c, 9df6232)
- Profile-aware Obsidian folder routing within `~/hr-vault-main-pa` (profile → top-level folder; daily notes stay global) with `claw` subcommand and welcome-TUI row (3fde5ba)
- `bin/claw` dispatcher + `agents.toml` registry + agents FZF picker (588a077, 9aa7b3f)
- `claw` shell function for native profile load/off (9aa7b3f)
- `_claw_guard` helper that prints an install hint when a tool is missing (bf4b316)
- `docs/claw.md` — single-page user guide for the claw command (ca42600)
- `tool-updater.sh` `--interactive` and `--force` foreground modes (713bace)
- Welcome-TUI agents row; deduped Claude entry (1e5dda8)
- Real brand art for 8 profile fastfetch logos via chafa pipeline (58060e1)

### Changed
- Scheduled ≡ manual: the weekly self-update timer now runs the same phased
  front door (`bin/claw update --non-interactive`, `CLAW_UPDATE_TRIGGER=timer`)
  and fires a `notify.sh` crit alert on failure; `claw pkg update` delegates
  to the one package engine
- Sweep fixes on the no-topgrade fallback: upfront `sudo -v` + keepalive when
  a sudo-needing manager is present, dropped `go clean -modcache` (a cache
  wipe, not an update), `gem update --system` → `gem update` (user gems),
  `--dry-run` prints the step plan without executing
- Bootstrap now ensures `bin/claw` and scripts are executable + verifies install (7931a0e)
- Restored OS auto-detect logo for the generic fastfetch dashboard (2e74b63)
- Extracted shared `tui-style.sh` helpers; slimmed `system-update.sh` (065b08e)
- Dropped `<profile>-` alias prefixes across all profiles (-138 lines) (19dbf9b)

### Fixed
- `claw-progress.sh` `_c()` now emits truecolor from `CLAW_RGB_*` (was printing
  raw hex from `CLAW_C_*` into escape sequences)
- `claw-dashboard.py` no longer requires Python 3.12 (f-string quote reuse)
- Local profile stubs + bash 3.2 compatibility in `claw doctor` (fcc9602)
- PR #1 review feedback: `BASH_SOURCE` handling under zsh + pcap timestamp (c922aeb)
- Skills picker now follows symlinks (f701dce)
- Prevented `[N]+done` bleed over the fastfetch logo on shell init (a286e01)

### Docs
- Regenerated `docs/ARCHITECTURE.md` and `docs/ALIASES.md`
- Added top-level `CHANGELOG.md`
- Linked `docs/claw.md` from `README.md`

[Unreleased]: https://github.com/hankthebldr/dot-files/compare/master...HEAD
