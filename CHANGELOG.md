# Changelog

All notable changes to this project are documented here.

The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `gemini-cli` (`@google/gemini-cli`) installed by `ai-toolchain.sh` and
  pre-registered in the `claw` agents.toml seed — `claw gemini` works
  from any profile out of the box; surfaced in ai/cortex/default help
  blocks (694e49e, cea228c, 9df6232)
- Profile-aware Obsidian vault routing with `claw` subcommand and welcome-TUI row (3fde5ba)
- `bin/claw` dispatcher + `agents.toml` registry + agents FZF picker (588a077, 9aa7b3f)
- `claw` shell function for native profile load/off (9aa7b3f)
- `_claw_guard` helper that prints an install hint when a tool is missing (bf4b316)
- `docs/claw.md` — single-page user guide for the claw command (ca42600)
- `tool-updater.sh` `--interactive` and `--force` foreground modes (713bace)
- Welcome-TUI agents row; deduped Claude entry (1e5dda8)
- Real brand art for 8 profile fastfetch logos via chafa pipeline (58060e1)

### Changed
- Bootstrap now ensures `bin/claw` and scripts are executable + verifies install (7931a0e)
- Restored OS auto-detect logo for the generic fastfetch dashboard (2e74b63)
- Extracted shared `tui-style.sh` helpers; slimmed `system-update.sh` (065b08e)
- Dropped `<profile>-` alias prefixes across all profiles (-138 lines) (19dbf9b)

### Fixed
- Local profile stubs + bash 3.2 compatibility in `claw doctor` (fcc9602)
- PR #1 review feedback: `BASH_SOURCE` handling under zsh + pcap timestamp (c922aeb)
- Skills picker now follows symlinks (f701dce)
- Prevented `[N]+done` bleed over the fastfetch logo on shell init (a286e01)

### Docs
- Regenerated `docs/ARCHITECTURE.md` and `docs/ALIASES.md`
- Added top-level `CHANGELOG.md`
- Linked `docs/claw.md` from `README.md`

[Unreleased]: https://github.com/hankthebldr/dot-files/compare/master...HEAD
