# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cross-platform CLI configuration system ("dot-files") that bootstraps a complete developer environment on macOS and Ubuntu/Debian. Supports 8 workflow profiles (Default, Cloud, Security, DevOps, AI, Research, Cortex, Local) with modern CLI tool replacements, profile-specific fastfetch dashboards, and an interactive FZF-based welcome TUI.

Dotfiles are symlinked from `~/.dotfiles` into the home directory. The expected clone path is `~/.dotfiles`.

## Setup & Installation

```bash
# One-liner remote install:
curl -fsSL https://raw.githubusercontent.com/<user>/dot-files/master/install.sh | bash

# Local install:
git clone <repo> ~/.dotfiles && cd ~/.dotfiles && ./bootstrap.sh

# Options:
./bootstrap.sh              # Full installation (9 steps)
./bootstrap.sh --minimal    # Essentials only (zsh, modern CLI, symlinks)
./bootstrap.sh --security   # Include pentesting tools
./bootstrap.sh --dry-run    # Preview without changes
```

`bootstrap.sh` handles: symlink, backup, brew/apt, zsh+OMZ+P10k, modern CLI, Nerd Fonts, Stow symlinks, dev/security tools.

`master-setup.sh` is a separate orchestrator with category arguments:
```bash
bash scripts/install/master-setup.sh all      # Everything
bash scripts/install/master-setup.sh base     # Shell + dev + network + extras
bash scripts/install/master-setup.sh domains  # All domain toolchain scripts
```

## Architecture

### Shell Configuration Loading Order (.zshrc)

1. P10k instant prompt (must be first)
2. Oh-My-Zsh framework + conditional plugins (macOS/Ubuntu)
3. `DOTFILES_DIR` + `shell/platform.zsh` (cross-platform shims)
4. `shell/path.zsh` - PATH setup (homebrew macOS/Linux, cargo, go)
5. `shell/exports.zsh` - Environment variables (FZF, BAT, GIT_PAGER, XDG, history)
6. `shell/load-env.zsh` - `.env` file loading (silent, guarded)
7. `shell/aliases.zsh` - All aliases and shell functions (~680 lines)
8. `shell/security.zsh` - Safe file ops, network recon, scanning aliases
9. `shell/obsidian.zsh` - Obsidian vault integration (`on`, `os`, `ov`)
10. Tool init: zoxide, direnv, atuin, thefuck, eza, zsh-syntax-highlighting (all guarded)
11. P10k theme config (profile-aware)
12. Welcome TUI (`claw_welcome_tui`) — interactive shells only, SSH-safe

### Cross-Platform Layer

`shell/platform.zsh` provides shims used by all other modules:
- `clip_copy` / `clip_paste` — pbcopy on macOS, xclip on Linux, wl-copy on Wayland
- `claw_open` — open on macOS, xdg-open on Linux
- `local_ip` — ipconfig on macOS, hostname -I on Linux
- `os_version` — sw_vers on macOS, /etc/os-release on Linux
- `vpn_status` — scutil on macOS, ip link on Linux
- `HOMEBREW_PREFIX` — auto-detected for macOS ARM/Intel and Linux

### Profile System

`shell/profiles/` contains context-specific environments loaded via the welcome TUI:
- `default.zsh` — Daily driver with help function, tool check, Apple logo fastfetch
- `cloud.zsh`, `security.zsh`, `devops.zsh`, `ai.zsh`, `research.zsh`, `cortex.zsh`, `local.zsh`

Each profile provides:
- `CLAW_PROFILE_THEME` export
- Domain-specific aliases grouped by category
- `{profile}-help` — styled quick-reference card
- `_{profile}_tool_check` — tool presence validation
- Profile-specific fastfetch config (`config-{profile}.jsonc`) with themed logo

### Fastfetch Profile Configs

`config/.config/fastfetch/` contains:
- `config.jsonc` + `logo.txt` — Generic pre-menu OPEN CLAW header
- `config-{profile}.jsonc` + `logo-{profile}.txt` — 8 profile-specific dashboards
- Each profile config: a shared, icon-rich **System / Desktop / Hardware / Network** base (Nerd Font / Font Awesome glyph per key, GitHub-dark colors) plus a domain-specific **Tooling** section of `command` modules (live tool status, k8s context, docker containers, etc.). fastfetch silently skips modules with no data, so each machine (macOS or Linux, desktop or headless) auto-populates only what it has.
- The 9 core dashboards (`config.jsonc`, `config-default.jsonc`, `config-{cloud,security,devops,ai,research,cortex,local}.jsonc`) are generated from a single source of truth — `scripts/utils/gen-fastfetch.py`. Edit the icon map / layout / per-profile tooling there and re-run `python3 scripts/utils/gen-fastfetch.py`; do not hand-edit those 9 files.
- Logo variants: same OPEN CLAW geometry, different color palettes and banner text per profile
- Default profile uses Apple-inspired logo instead of OPEN CLAW face

### Gamified Onboarding & Integrity Check

`scripts/utils/onboarding.sh` — 80s arcade-themed character-creation flow that asks 6 personality questions (work hours, weapon of choice, prod-incident style, dream homelab, etc.), tallies points against the 8 workflow profiles, announces an RPG-style "class" (e.g. `SKYSURFER` for cloud, `NIGHTHACKER` for security, `NEUROMANCER` for ai), and offers to install the matching toolchain + activate the profile. Surfaced via `claw onboard`, the welcome TUI ("Onboarding" entry), and the bootstrap end-of-install banner. Visual palette: hot pink / neon cyan / synthwave purple. Uses gum if available, falls back to plain `read`.

`scripts/utils/integrity.sh` — SHA-256 manifest generator and verifier for the entire dotfiles tree. Run after install/pull to detect tampering or partial installs:
- `claw integrity generate` — writes `config/integrity/manifest.sha256`, sorted byte-wise for deterministic output. Honors `config/integrity/.integrityignore` (gitignore-style globs; auto-created with sane defaults).
- `claw integrity verify` — diffs on-disk hashes against the manifest, reports `CHANGED` / `MISSING` / `EXTRA` paths, exits 1 on drift.
- `claw integrity audit` — verify plus provenance: git commit/branch, manifest age, hasher version.
- Auto-generated at the end of `bootstrap.sh` as Step 9b. Portable across macOS (`shasum -a 256`) and Linux (`sha256sum`).

### SSH Tunnel Manager

`scripts/utils/tunnel-manager.sh` — Interactive FZF-based tunnel manager:
- YAML config at `config/ssh/tunnels.yml` (see `tunnels.yml.example`)
- ASCII topology visualization showing hop chain with boxes, arrows, key indicators
- Local (-L), Remote (-R), SOCKS (-D) tunnels with multi-hop ProxyJump
- SSH ControlMaster lifecycle (connect/disconnect/status)
- Aliases: `tun`, `tunls`, `tunkill`, `tuntopo`

### AI Services Manager

`scripts/utils/ai-services.sh` — unified manager for self-hosted AI web stacks, dispatched via `claw ai-services <cmd>` (aliases `aisvc`, plus `aisup`/`aisdown`/`aisst`/`owui` in the `ai` profile). Registry-driven over two install shapes:
- **local** — compose file shipped in the repo at `config/<svc>/docker-compose.yml`: `open-webui` (:3000, ChatGPT-style UI auto-wired to host Ollama at :11434), `langfuse` (:3000, observability).
- **upstream** — shallow `git clone` of the project's repo into `$XDG_DATA_HOME/claw/ai-services/<svc>` (NOT the dotfiles tree); runs *their* version-coupled compose with port/GPU tweaks driven through their `.env`: `dify` (:8080 via `EXPOSE_NGINX_PORT`), `ragflow` (:8081 via `SVR_WEB_HTTP_PORT`, GPU via `DEVICE=gpu`).
- Each stack runs under a `claw-<svc>` compose project (namespaced containers). Commands: `list`, `status`, `up`, `down`, `restart`, `pull`, `logs`, `prepare`, `url`. With no service args, `up`/`down`/`status`/`pull` act on all. `claw validate` shows live reachability of each stack.
- Port map (collision-free): open-webui/langfuse :3000, dify :8080, ragflow :8081.

### Installation Scripts

Two entry points:
- **`bootstrap.sh`** — Primary installer (9 steps: symlink, backup, brew, essentials, zsh+OMZ+P10k, modern CLI+gum+yq, Nerd Fonts, Stow, extras)
- **`install.sh`** — One-liner curl wrapper that clones repo then runs bootstrap.sh
- **`scripts/install/master-setup.sh`** — Alternative orchestrator for domain toolchains

Domain toolchain scripts (`scripts/install/`): `ai-toolchain.sh`, `cloud-toolchain.sh`, `devops-toolchain.sh`, `security-toolchain.sh`, `research-toolchain.sh`, `cortex-toolchain.sh`

### Interactive TUI

- `shell/welcome-tui.zsh` — FZF login dashboard with 20+ options, grouped into Profiles / Tools / System sections. Default profile is highlighted as daily driver. ESC = default shell.
- `scripts/utils/toolkit.sh` — "Open Claw Toolkit" FZF menu for Git, Docker, K8s, Cloud, Security, System workflows
- `scripts/utils/tunnel-manager.sh` — SSH tunnel manager with ASCII topology
- `scripts/utils/ai-services.sh` — unified manager for self-hosted AI web stacks (open-webui, dify, ragflow, langfuse) via `claw ai-services`
- `scripts/utils/homelab.sh` — SSH topology manager (parses ~/.ssh/config)
- `scripts/utils/mcp-manager.sh` — MCP server manager (list/register/scaffold)
- `scripts/utils/system-update.sh` — Cumulative updater with gum spinners (graceful fallback)
- `scripts/utils/tool-updater.sh` — Background auto-updater with staggered intervals

## Conventions

- **Cross-platform first:** All shell code uses `platform.zsh` shims, never raw `pbcopy`/`ipconfig`/`open`
- **Modern CLI tools replace legacy ones:** `eza` (ls), `bat` (cat), `ripgrep` (grep), `fd` (find), `zoxide` (cd), `btop` (top), `delta` (diff). `colorls` (Ruby gem) supplements `eza` with Font Awesome / Nerd Font icons via `lc`/`lcl`/`lca`/`lct`/`lcd` aliases (guarded on `command -v colorls`), themed by `config/.config/colorls/dark_colors.yaml`. Font Awesome installs alongside the Nerd Fonts in `bootstrap.sh` Step 7 for colorls glyphs.
- **Color theme:** GitHub macOS Dark throughout — Blue `#58a6ff`, Green `#3fb950`, Purple `#bc8cff`, Orange `#d29922`, Red `#ff7b72`, Muted `#8b949e`
- **Logging pattern:** Color-coded `log_info`, `log_success`, `log_warning`, `log_error` (blue/green/yellow/red)
- **Idempotent installs:** All scripts check `command -v` before installing
- **SSH safety:** Welcome TUI never runs in non-interactive/piped shells. load-env.zsh is silent. No stdout pollution.
- **Machine-local config goes in `~/.zshrc.local`, not the repo:** `~/.zshrc` is a stow symlink *into* the repo (`shell/.zshrc`), so any tool that does `echo >> ~/.zshrc` writes host-specific data (absolute paths, secrets, machine env) straight into the tracked, portable dotfiles. `.zshrc` sources `~/.zshrc.local` (untracked) near the end — put per-machine `export`s there instead. Periodically check `git status` on `shell/.zshrc` for stray appended lines.
- **Shell scripts use `set -e`** (exit on error); master-setup also uses `set -u`
- **Safety aliases:** Destructive ops always prompt (`rm -i`, `mv -i`, `cp -i`)
- **FZF integration:** Fuzzy selection in git branches, k8s contexts, AWS profiles, process killing, tunnel manager

## Key File Paths

| File | Purpose |
|------|---------|
| `.zshrc` | Main shell config, sources all modules |
| `shell/.p10k.zsh` | Pre-themed Powerlevel10k prompt (GitHub-dark, Nerd Font); stowed to `~/.p10k.zsh` |
| `shell/platform.zsh` | Cross-platform shims (clipboard, open, IP, VPN) |
| `shell/path.zsh` | PATH setup (brew macOS/Linux, cargo, go) |
| `shell/exports.zsh` | Environment variables (FZF, BAT, GIT_PAGER, XDG) |
| `shell/aliases.zsh` | Core aliases and functions (~680 lines) |
| `shell/security.zsh` | Safety aliases + network recon |
| `shell/obsidian.zsh` | Obsidian vault integration |
| `shell/profiles/*.zsh` | 8 workflow-specific environments |
| `shell/welcome-tui.zsh` | Login dashboard + default quick-ref |
| `config/.config/fastfetch/config-*.jsonc` | Profile-specific fastfetch configs (9 total) |
| `config/.config/colorls/dark_colors.yaml` | colorls GitHub-dark theme (icons via Font Awesome) |
| `scripts/utils/gen-fastfetch.py` | Generator for the 9 icon-rich fastfetch dashboards |
| `config/.config/fastfetch/logo-*.txt` | Profile-specific ASCII logos (9 total) |
| `config/ssh/tunnels.yml` | SSH tunnel definitions |
| `scripts/utils/tunnel-manager.sh` | SSH tunnel manager TUI |
| `scripts/utils/ai-services.sh` | Unified manager for self-hosted AI web stacks (open-webui/dify/ragflow/langfuse) |
| `config/open-webui/docker-compose.yml` | Open WebUI stack (ChatGPT-style Ollama UI, :3000) |
| `scripts/utils/toolkit.sh` | Interactive workflow launcher |
| `scripts/utils/system-update.sh` | Package updater with gum spinners |
| `scripts/utils/homelab.sh` | SSH topology manager |
| `scripts/utils/logger.sh` | Shared logging utilities |
| `scripts/utils/detect-os.sh` | OS detection (macOS, Ubuntu, Kali, etc.) |
| `scripts/setup/symlinks.sh` | GNU Stow symlink deployment |
| `tmux/.tmux.conf` | Tmux config (GitHub dark, cross-platform clipboard) |
| `terminal/.config/starship.toml` | Starship prompt config |
| `bootstrap.sh` | Primary cross-platform setup (9 steps) |
| `install.sh` | One-liner curl installer |

## Shell Script Guidelines

- Use `#!/usr/bin/env bash` for portability
- Guard ALL tool initialization with `command -v tool &> /dev/null` checks
- Use `$HOMEBREW_PREFIX` (set by platform.zsh) instead of hardcoded `/opt/homebrew`
- Never print to stdout during non-interactive shell init (breaks scp/rsync)
- Use `platform.zsh` shims (`clip_copy`, `local_ip`, `claw_open`) instead of macOS-only commands
- Support macOS (ARM/Intel), Ubuntu, Debian, Kali, Parrot via `detect-os.sh`
- Homebrew paths: `/opt/homebrew` (macOS ARM), `/usr/local` (macOS Intel), `/home/linuxbrew/.linuxbrew` (Linux)
