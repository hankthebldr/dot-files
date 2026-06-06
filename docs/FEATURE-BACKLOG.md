---
title: Open Claw — Feature Backlog
project: dot-files
status: living
created: 2026-06-06
tags: [open-claw, backlog, roadmap]
vault_path: Github-Projects/dot-files/FEATURE-BACKLOG.md
---

# Open Claw — Feature Backlog (Waves 6+)

Prioritized, derived from the full-code review + `UX-WALKTHROUGH.md` friction
points. P1 = highest leverage. Each item is sized S/M/L.

## P1 — Surfacing & discoverability (cheap, high impact)
- **`claw cheatsheet`** (S) — one screen of the delight/alias/agent commands
  (`cpv`/`dlv`/`xtract`/`weather`/`claw ai`/`claw secret`…). Today they're only
  discoverable by reading source. Render with `glow`/`gum`.
- **Help integration** (S) — fold `claw pkg|secret|ai|selfupdate|mcp-sync|provision`
  into `claw help` groups (some are wired but not all documented there).
- **`claw doctor` → registry-driven agent block** (M) — generalize the AI-agents
  health check to iterate `agents.toml` + check binary/key/config per agent
  (i.e. build the specced `claw agent doctor`).

## P1 — Close the interop loop fully
- **`claw pkg track` auto-hook** (M) — a `precmd`/periodic detector that notices
  newly-installed tools and nudges (or auto-commits) without manual `track`.
- **load↔install bridge** (M) — `claw load <profile>` detects missing
  `PROFILE_KEY_TOOLS` and offers `claw install <profile>`.
- **Profile-aware `mcp-sync`** (M) — honor the `profile=` tag in `mcp.toml`
  (e.g. only sync `shodan` when the security profile is active/synced).

## P2 — Ratatui TUI to parity (Wave 4 M3–M5)
- **M3 — tunnels + homelab screens** (L) — port `tunnel-manager.sh` (topology
  via `Block` chain, live `ssh -O check` on tick) and `homelab.sh` (ssh_config
  parse + preview pane); `EXEC` outcome for TTY handoff.
- **M4 — mcp + toolkit screens** (M) — `mcp.toml`/`claude_desktop_config.json`
  via serde_json; toolkit launcher tree.
- **M5 — CI release binaries** (M) — `.github/workflows/tui-release.yml`
  (macOS arm64 + Linux x86_64/arm64 musl) + `claw install claw-tui` downloads
  a verified binary instead of compiling.
- **Readout from `fastfetch --format json`** (S) — replace the minimal Rust
  probe with fastfetch's data so the TUI readout matches the shell one.
- **Live refresh** (S) — k8s context / docker counts updating on tick.

## P2 — Visual / delight packs
- **`tte` intro animation** (S) — animated OPEN CLAW reveal on first login.
- **Per-profile MOTD** (S) — profile-themed quote + glyph banner on `claw load`.
- **`pokeget`/`onefetch` MOTD options** (S) — toggleable personality.
- **Loader pack** (S) — wrap long ops (`apt`, `brew`, clones) in `gum spin`.

## P2 — Secrets & system ops depth
- **`op`/`bw` bridge** (M) — optional 1Password/Bitwarden layer feeding sops/env.
- **`claw secret rotate`** (M) — re-key age recipients (laptop + YubiKey/homelab backup).
- **`mise` migration** (M) — fnm+pyenv → mise (one runtime/env/task manager); update manifest + provision.
- **`unattended-upgrades`** (S) — wire on Debian/Ubuntu under selfupdate.

## P3 — Dead-weight triage (decide: wire or delete)
- `config/integrity/` — already invokable via `claw integrity`; confirm + keep.
- `config/agentic/openshell/policy.yaml`, `config/ai/serve-nemotron-omni.sh` —
  document the intended feature or remove.
- `config/.config/themes/*` — deploy via a `claw theme` importer or move to `docs/examples/`.
- `tools/.config/{bottom,lazygit}/.gitkeep` — populate real configs or drop.
- `should_skip_plugin()` stub in `claude-sync.sh` — implement the macOS/Linux split.

## P3 — Quality & testing
- **bats tests** (M) — for `pkg-manifest`, `toolchain-runner`, `secret`, `mcp-sync`.
- **rust unit/`TestBackend` tests** (M) — readout alignment + outcome contract snapshots.
- **shellcheck CI** (S) — lint all `scripts/**` on PR.
- **`doggo`/`trippy` alias wiring** (S) — alias `dig`→doggo, `mtr`→trip where present.

## Notes for whoever picks this up
- Everything here is *additive* and guarded — keep the fzf path + non-binary boxes fully working.
- Mirror new design docs to the vault with `claw docs-sync`.
- Update `ULTRAPLAN.md` wave checkboxes as items land.
