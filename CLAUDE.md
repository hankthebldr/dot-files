# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cross-platform CLI configuration system ("dot-files") that bootstraps a complete developer environment on macOS and Ubuntu/Debian. Supports 18 workflow profiles — 8 core (Default, Cloud, Security, DevOps, AI, Research, Cortex, Local) plus specialized ones (Claude, Blackwell, Brainstorm, Deck, Demo, Design, Homelab, PMO, Tunnels, Vault) — with modern CLI tool replacements, profile-specific fastfetch dashboards, and an interactive FZF-based welcome TUI.

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

### The Spine (consolidation contracts — keep these invariants)

Everything hangs off three contracts. When adding a capability, wire it into
the spine — do not add a parallel dispatcher, palette, or dashboard.

1. **One dispatcher.** `shell/claw-fn.zsh` defines the ONLY `claw()` shell
   function (in-shell work: no-args TUI relaunch, `load`/`off`, bare-profile
   shorthand `claw security` ≡ `claw load security`); everything else passes
   through to `bin/claw` (bash), which routes to `scripts/`. Never define a
   second `claw()` — a previous one in aliases.zsh was dead-shadowed for weeks.
2. **One theme engine.** `scripts/utils/theme.sh` is the single source of
   truth. Palettes: `config/themes/<slug>.theme`. Precedence: `CLAW_THEME` env
   (session override, set by profile loads via `PROFILE_THEME_DEFAULT` in
   meta.zsh) → `$XDG_STATE_HOME/claw/theme` (persisted `claw theme set`) →
   refined-dark. `.zshrc` step 2b sources it; ALL surfaces consume
   `CLAW_RGB_*` / `CLAW_C_*` / `claw_theme_fzf` with refined-dark fallbacks —
   never hardcode hex/ANSI colors in a new surface (the rust TUI reads the
   same state in `tui/claw-tui/src/theme.rs`).
3. **One render path.** Login + default profile render
   `scripts/utils/claw-dashboard.py` (framed, centered, crisp fastfetch system
   logo + dense grid + btop-style bars; `--quickref` appends the Daily Driver
   card on the same width engine). fastfetch `config-*.jsonc` is the
   per-profile art + explicit fallback; the zsh quickref box is the
   no-python fallback only. Data comes from `ff-readout.sh fields` (incl.
   `<res>_pct` for the bars).

Also: `claw update` is the one updater front door, and it is **phased**:
phase 1 `scripts/utils/repo-sync.sh` (conservative ff-only pull of the
dotfiles repo — a dirty tree or diverged branch skips with a reason, never
auto-stash/merge — then regen of only the derived artifacts the pull touched:
gen-fastfetch, `stow -R shell`, link-claude, integrity manifest); phase 2
`scripts/utils/system-update.sh`, the ONE package engine — topgrade-first,
run as a single streamed `claw_step` under the repo-shipped
`config/topgrade.toml` when `topgrade` is installed, with the hand-rolled
sweep surviving only as the fallback. Flags: `--repo` / `--packages` run one
phase, `--dry-run` previews without executing, `--last` pretty-prints recent
receipts, `--tools` → tool-updater fast lane, `--schedule` → selfupdate
(whose weekly timer runs `bin/claw update --non-interactive`, so scheduled ≡
manual; `claw pkg update` delegates to the engine too). Every run appends one
receipt row (ISO ts, trigger, duration, ok|fail, detail) to
`~/.cache/claw/updates.tsv`. The fast lane reads the ONE tool registry:
`config/manifest/tools.list` rows carry an optional third field
`id|source|cadence` (daily|weekly|biweekly|monthly) and only cadence-tagged
rows update in the background (hardcoded categories are the manifest-less
fallback only). Update state is data: `scripts/utils/update-status.sh` probes
pending counts into `~/.cache/claw/updates.json` (atomic, ≥6h throttle unless
`--force`; absent manager = null), read by `situation.sh` (`.updates`,
info-notify on the rising edge of repo-behind), `ff-readout.sh` (`updates`
field), `claw doctor`, and refreshed in the background at login by the
welcome TUI. Superseded/uncalled scripts live in `legacy/` (see
`legacy/README.md`) — archive there, don't delete or leave strays.

Also: `scripts/utils/notify.sh` is the one desktop-notification engine
(`claw notify`, macOS terminal-notifier→osascript / Linux notify-send, stderr
fallback). `platform.zsh` `claw_notify` and `situation.sh`'s interrupt tier both
route through it so crit alerts behave identically on macOS and Linux — never
hand-roll an `osascript`/`notify-send` call in a new surface.

### Shell Configuration Loading Order (.zshrc)

Mirrors the numbered steps in `shell/.zshrc` (see its header comment):

1. **PATH + `DOTFILES_DIR`** — set **inline** (homebrew, `$HOME/.local/bin`, cargo, go, `scripts/utils`, `bin/claw`). Deliberately inline and FIRST — **there is no `shell/path.zsh`** — so every tool resolves before the welcome TUI runs at step 3.
2. `shell/platform.zsh` (cross-platform shims) → `ghostty-terminfo.zsh` → `scripts/utils/theme.sh` (theme engine, single color source) → `shell/fastfetch.zsh`
3. Welcome TUI (`claw_welcome_tui`) — runs BEFORE p10k, while the shell still owns the terminal; interactive-only, SSH-safe
4. P10k instant prompt — **disabled on purpose** (the TUI provides the immediate visual feedback instant prompt was designed for)
5. Oh-My-Zsh framework + conditional plugins (macOS/Ubuntu/Debian)
6. Modular sources: `exports.zsh`, `load-env.zsh` (`.env`, silent/guarded), `aliases.zsh` (~680 lines), `profile-helpers.zsh`, `claw-fn.zsh`, `claw-completion.zsh`, `security.zsh`, `obsidian.zsh`, `clin.zsh` (after obsidian — rides its vault resolvers), `progress.zsh`, `delight.zsh`, vault-os aliases
7. Tool init (all guarded): zoxide, direnv, atuin, thefuck, zsh-syntax-highlighting, gcloud SDK
8. P10k theme config — sources the tuned prompt straight from `shell/.p10k.zsh` in the repo (not `~/.p10k.zsh`), profile-aware; then symlink-drift guard, terraform completion, FZF keybindings, `~/.zshrc.local` overrides, appended external-tool PATH

### Cross-Platform Layer

`shell/platform.zsh` provides shims used by all other modules:
- `clip_copy` / `clip_paste` — pbcopy on macOS, xclip on Linux, wl-copy on Wayland
- `claw_open` — open on macOS, xdg-open on Linux
- `local_ip` — ipconfig on macOS, hostname -I on Linux
- `os_version` — sw_vers on macOS, /etc/os-release on Linux
- `vpn_status` — scutil on macOS, ip link on Linux
- `HOMEBREW_PREFIX` — auto-detected for macOS ARM/Intel and Linux

### Profile System

`shell/profiles/` contains context-specific environments loaded via the welcome TUI. Each profile is a **directory**, not a single file: a thin 5-line dispatcher `shell/profiles/<name>.zsh` sources `<name>/{meta,common,mac|linux}.zsh` (platform-split so macOS/Linux-only aliases don't leak cross-platform):
- `default/` — Daily driver with help function, tool check, Apple logo fastfetch
- 8 core: `cloud/`, `security/`, `devops/`, `ai/`, `research/`, `cortex/`, `local/` (+ default)
- 10 specialized: `claude/`, `blackwell/`, `brainstorm/`, `deck/`, `demo/`, `design/`, `homelab/`, `pmo/`, `tunnels/`, `vault/` (18 profiles total)

Each profile directory provides:
- `meta.zsh` — `CLAW_PROFILE_THEME` / `PROFILE_THEME_DEFAULT`, `PROFILE_START_DIR`, and other profile metadata
- `common.zsh` — domain-specific aliases and functions shared across platforms
- `mac.zsh` / `linux.zsh` — platform-specific overrides, sourced conditionally by the dispatcher
- `{profile}-help` — styled quick-reference card
- `_{profile}_tool_check` — tool presence validation
- Profile-specific fastfetch config (`config-{profile}.jsonc`) with themed logo

**Start directories — one applier, declared per profile.** WHERE a profile drops
you is data, not code: `PROFILE_START_DIR` in `meta.zsh` (e.g. `vault` →
`@vault`, the Obsidian vault root; `devops` → `${DEVOPS_WORKSPACE:-$HOME/devops}`),
resolved and applied by `_claw_profile_cd` in `shell/profile-helpers.zsh` — the
ONE applier every load path calls (`claw load`, the fzf welcome TUI, the
rust-TUI outcome applier). Never hand-roll a top-level `cd` in a profile file.
Spec grammar: plain paths (`$VAR`/`~` expanded), `@vault` (vault root),
`@vault-folder` (the profile's mapped folder via `obsidian.zsh`, vault root if
absent), `@vault:<Folder>`, `a|b|c` (first candidate that exists), `""` (stay
put — what `default` uses). Precedence: `$CLAW_START_DIR` (this shell) →
`~/.config/claw/start-dirs.conf` (per-machine, untracked; template in
`config/claw/start-dirs.conf.example`) → `PROFILE_START_DIR`. Escape hatches:
`CLAW_PROFILE_CD=0` (never), `=home` (only from `$HOME`), `cd -` (always goes
back), and non-interactive shells are never relocated. `claw profiles paths`
prints the resolved table.

`claw profiles lint` (`scripts/utils/profiles-lint.sh`) validates the directory-per-profile contract — every profile has the expected files, declares `PROFILE_START_DIR` with a known `@token`, exports the required symbols, and hand-rolls no top-level `cd`.

### Fastfetch Profile Configs

`config/.config/fastfetch/` contains:
- `config.jsonc` + `logo.txt` — Generic pre-menu OPEN CLAW header
- `config-{profile}.jsonc` + `logo-{profile}.txt` — 8 profile-specific dashboards
- Each profile config: a shared, icon-rich **System / Desktop / Hardware / Network** base (Nerd Font / Font Awesome glyph per key, GitHub-dark colors) plus a domain-specific **Tooling** section of `command` modules (live tool status, k8s context, docker containers, etc.). fastfetch silently skips modules with no data, so each machine (macOS or Linux, desktop or headless) auto-populates only what it has.
- There are 19 fastfetch configs total: the generic `config.jsonc` plus one `config-<profile>.jsonc` per profile. **9 are generated** (`config.jsonc`, `config-default.jsonc`, `config-{cloud,security,devops,ai,research,cortex,local}.jsonc`) from a single source of truth — `scripts/utils/gen-fastfetch.py`. Edit the icon map / layout / per-profile tooling there and re-run `python3 scripts/utils/gen-fastfetch.py`; do not hand-edit those 9 files. The other **10 are hand-maintained** (`config-{claude,blackwell,brainstorm,deck,demo,design,homelab,pmo,tunnels,vault}.jsonc`) and are NOT touched by the generator — edit those directly.
- Logo variants: same OPEN CLAW geometry, different color palettes and banner text per profile
- Default profile uses Apple-inspired logo instead of OPEN CLAW face

### Gamified Onboarding & Integrity Check

`scripts/utils/onboarding.sh` — 80s arcade-themed character-creation flow that asks 6 personality questions (work hours, weapon of choice, prod-incident style, dream homelab, etc.), tallies points against the 8 core workflow profiles, announces an RPG-style "class" (e.g. `SKYSURFER` for cloud, `NIGHTHACKER` for security, `NEUROMANCER` for ai), and offers to install the matching toolchain + activate the profile. Surfaced via `claw onboard`, the welcome TUI ("Onboarding" entry), and the bootstrap end-of-install banner. Visual palette: hot pink / neon cyan / synthwave purple. Uses gum if available, falls back to plain `read`.

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
- **local** — compose file shipped in the repo at `config/<svc>/docker-compose.yml`: `open-webui` (:3000, ChatGPT-style UI auto-wired to host Ollama at :11434), `langfuse` (:3000, observability), `portainer` (:9443 HTTPS, Docker management web UI — mounts the Docker socket).
- **upstream** — shallow `git clone` of the project's repo into `$XDG_DATA_HOME/claw/ai-services/<svc>` (NOT the dotfiles tree); runs *their* version-coupled compose with port/GPU tweaks driven through their `.env`: `dify` (:8080 via `EXPOSE_NGINX_PORT`), `ragflow` (:8081 via `SVR_WEB_HTTP_PORT`, GPU via `DEVICE=gpu`).
- Each stack runs under a `claw-<svc>` compose project (namespaced containers). Commands: `list`, `status`, `up`, `down`, `restart`, `pull`, `logs`, `prepare`, `url`. With no service args, `up`/`down`/`status`/`pull` act on all. `claw validate` shows live reachability of each stack.
- Port map (collision-free): open-webui/langfuse :3000, dify :8080, ragflow :8081, portainer :9443.

### Docker container overview

`scripts/utils/docker-overview.sh` (`claw docker`, alias `dover`) — read-only, gruvbox-themed snapshot of every container grouped by compose project, with state dot, status, published host ports, and live CPU/MEM. Complements the interactive tools: `lzd` (lazydocker TUI — logs/exec/graphs), `cto` (ctop — live per-container metrics), and Portainer (web UI via `claw ai-services up portainer`). lazydocker + ctop are flagged in `devops-toolchain.sh`.

### Claude Code Integration (`claude/`)

The `claude/` tree is Henry's Claude Code config, deployed into `~/.claude/` by `scripts/setup/link-claude.sh` (run automatically as bootstrap Step 8c, or on demand via `claw harness deploy`). It is **not** GNU-Stowed — stow would splatter files into `$HOME` and clobber the managed-skill marketplace. The linker is item-level: it backs up real-file collisions, skips managed marketplace symlinks it didn't create, is idempotent, and honors `--dry-run`. It also registers the default-deny scope hooks (`claude/hooks/pre_tool_use.py`) into `~/.claude/settings.json` via `install-hooks.sh`.

Contents: `CLAUDE.md` (global rules), `scope.txt` (recon scope allowlist), `hooks/` (pre/post-tool-use), `commands/` (slash commands), `skills/` (security skills), `agent-skills/` (vendored third-party), and `harness/`.

- **`claude/harness/`** — dedicated workspace for Henry's **custom agentic harness tools**: `skills/`, `commands/`, `agents/`, `plugins/`. Managed via `claw harness {list|new <name>|deploy|path}`. `_template/` and `_`-prefixed dirs are scaffolding and are skipped by the deployer. See `claude/harness/README.md`.

### Clin Plugin (Obsidian sub-profile)

`clin` ([reekta92/clin-rs](https://github.com/reekta92/clin-rs)) is a TUI note manager inspired by Obsidian. The "clin plugin" packages it as a self-contained module **inside the Obsidian sub-profile** rather than scattering it across the tree — it rides on `shell/obsidian.zsh`'s resolvers so clin inherits the exact same profile-scoped vault routing as `o`/`on`/`os`/`ov`. Two halves:

- **`shell/clin.zsh`** (interactive, sourced in `.zshrc` immediately after `obsidian.zsh`) — reuses `_claw_obsidian_vault` / `_claw_obsidian_folder` / `_claw_obsidian_dir`:
  - `cl` — open clin in the **active profile's folder** (`CORTEX`, `Secops`, `_agents`…). Renders a per-shell ephemeral config and launches `clin --config`, so it never clobbers the persistent config and two shells on different profiles don't fight.
  - `cln "Title"` — create a note in that folder (mirrors `on`), then open clin.
  - `clin-sync` — re-render the persistent config; `clin-help` — quick-reference card. All guarded — missing clin just prints an install hint.
- **`scripts/utils/clin.sh`** (POSIX engine, mirrors `theme.sh`) — `install` (`cargo install clin-rs`), `render <out> [vault] [folder]`, `sync`, `setup`. Renders clin's `~/.config/clin/config.toml` from the **two existing sources of truth**: the active palette (`theme.sh` → `CLAW_C_*`, written to clin's `[ui]` per-color keys) and the Obsidian vault/folder (`[core] storage_path`/`default_folder`). Slugs map to clin's built-in themes where one exists (`catppuccin-mocha`→`catppuccin_mocha`, `tokyo-night`→`tokyo_night`, `rose-pine`→`rose_pine`, `gruvbox-material`→`gruvbox`), else `default` + the per-color overlay.
- **Theme-synced**: `claw theme set <slug>` re-renders clin's config so the note TUI tracks the active palette. The persistent config is a **managed file** (sentinel on line 1); `sync` refuses to overwrite a hand-tuned config unless `CLAW_CLIN_MANAGED=force`, and `CLAW_CLIN_MANAGED=0` opts out entirely.
- **Surfaced**: `claw clin {sync|install|setup}` dispatch, a "Clin Notes" entry in the welcome TUI (Direct Actions), and install rows in the `cortex` + `research` toolchains (`cargo:clin-rs`).

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
- `scripts/utils/system-update.sh` — The one package-update engine (topgrade-first via `config/topgrade.toml`, streamed `claw_step`; hand-rolled sweep as fallback)
- `scripts/utils/tool-updater.sh` — Background fast-lane updater driven by cadence-tagged rows of `config/manifest/tools.list` (per-category cache; hardcoded categories only as manifest-less fallback)

## Conventions

- **Cross-platform first:** All shell code uses `platform.zsh` shims, never raw `pbcopy`/`ipconfig`/`open`
- **Modern CLI tools replace legacy ones:** `eza` (ls), `bat` (cat), `ripgrep` (grep), `fd` (find), `zoxide` (cd), `btop` (top), `delta` (diff). `colorls` (Ruby gem) supplements `eza` with Font Awesome / Nerd Font icons via `lc`/`lcl`/`lca`/`lct`/`lcd` aliases (guarded on `command -v colorls`), themed by `config/.config/colorls/dark_colors.yaml`. Font Awesome installs alongside the Nerd Fonts in `bootstrap.sh` Step 7 for colorls glyphs.
- **Color theme:** GitHub macOS Dark throughout — Blue `#58a6ff`, Green `#3fb950`, Purple `#bc8cff`, Orange `#d29922`, Red `#ff7b72`, Muted `#8b949e`
- **Logging pattern:** Color-coded `log_info`, `log_success`, `log_warning`, `log_error` (blue/green/yellow/red)
- **Idempotent installs:** All scripts check `command -v` before installing
- **SSH safety:** Welcome TUI never runs in non-interactive/piped shells, and skips the fzf picker on interactive SSH logins too (loads the default profile instead) — a pre-prompt full-screen menu deadlocks SSH clients that wait for the first prompt ("setting up session…" hangs). `CLAW_SSH_TUI=1` opts back in for plain ssh. load-env.zsh is silent. No stdout pollution.
- **Machine-local config goes in `~/.zshrc.local`, not the repo:** `~/.zshrc` is a stow symlink *into* the repo (`shell/.zshrc`), so any tool that does `echo >> ~/.zshrc` writes host-specific data (absolute paths, secrets, machine env) straight into the tracked, portable dotfiles. `.zshrc` sources `~/.zshrc.local` (untracked) near the end — put per-machine `export`s there instead. Periodically check `git status` on `shell/.zshrc` for stray appended lines.
- **Shell scripts use `set -e`** (exit on error); master-setup also uses `set -u`
- **Safety aliases:** Destructive ops always prompt (`rm -i`, `mv -i`, `cp -i`)
- **FZF integration:** Fuzzy selection in git branches, k8s contexts, AWS profiles, process killing, tunnel manager

## Key File Paths

| File | Purpose |
|------|---------|
| `.zshrc` | Main shell config; sets PATH **inline** (step 1: brew, `~/.local/bin`, cargo, go, `bin/claw`) and sources all modules |
| `shell/.p10k.zsh` | Pre-themed Powerlevel10k prompt (GitHub-dark, Nerd Font); stowed to `~/.p10k.zsh` |
| `shell/platform.zsh` | Cross-platform shims (clipboard, open, IP, VPN) |
| `shell/exports.zsh` | Environment variables (FZF, BAT, GIT_PAGER, XDG) |
| `shell/aliases.zsh` | Core aliases and functions (~680 lines) |
| `shell/security.zsh` | Safety aliases + network recon |
| `shell/obsidian.zsh` | Obsidian vault integration |
| `shell/clin.zsh` | Clin plugin — interactive `cl`/`cln` (reuses obsidian resolvers) |
| `scripts/utils/clin.sh` | Clin plugin engine — install + theme/vault-synced config render |
| `shell/profiles/*.zsh` | 18 workflow-specific environments (8 core + 10 specialized) |
| `shell/welcome-tui.zsh` | Login dashboard + default quick-ref |
| `config/.config/fastfetch/config-*.jsonc` | Profile fastfetch configs (19 total: 9 generated + 10 hand-maintained) |
| `config/.config/colorls/dark_colors.yaml` | colorls GitHub-dark theme (icons via Font Awesome) |
| `scripts/utils/gen-fastfetch.py` | Generator for the 9 icon-rich fastfetch dashboards |
| `config/.config/fastfetch/logo-*.txt` | Profile-specific ASCII logos (one per file-logo profile) |
| `config/ssh/tunnels.yml` | SSH tunnel definitions |
| `scripts/utils/tunnel-manager.sh` | SSH tunnel manager TUI |
| `scripts/utils/ai-services.sh` | Unified manager for self-hosted AI web stacks (open-webui/dify/ragflow/langfuse) |
| `config/open-webui/docker-compose.yml` | Open WebUI stack (ChatGPT-style Ollama UI, :3000) |
| `scripts/utils/toolkit.sh` | Interactive workflow launcher |
| `scripts/utils/system-update.sh` | One package-update engine (topgrade-first, sweep fallback) |
| `scripts/utils/homelab.sh` | SSH topology manager |
| `scripts/utils/logger.sh` | Shared logging utilities |
| `scripts/utils/notify.sh` | One cross-platform desktop-notification engine (`claw notify`); backs `platform.zsh` `claw_notify` + `situation.sh` alerts |
| `scripts/utils/detect-os.sh` | OS detection (macOS, Ubuntu, Kali, etc.) |
| `scripts/setup/symlinks.sh` | GNU Stow symlink deployment |
| `scripts/setup/link-claude.sh` | Item-level deployer for `claude/` → `~/.claude` (hooks, skills, harness) |
| `claude/harness/` | Custom agentic harness tools (skills/commands/agents/plugins) — `claw harness` |
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
