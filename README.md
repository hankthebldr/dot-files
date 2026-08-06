# Open Claw — Cross-Platform CLI Environment

> Modular shell configuration system for macOS and Ubuntu/Debian. Single-command surface (`claw`), 18 workflow profiles with brand-accurate fastfetch dashboards, a single theme engine every surface follows, a native Rust welcome TUI, an agent-agnostic launcher, profile-aware Obsidian vault routing, age/sops-encrypted secrets, a versioned Claude Code harness, modern CLI tools, SSH tunnel management, and a full Neovim IDE — all from one `bootstrap.sh`.

### The spine (three consolidation contracts)

Everything hangs off three invariants — add a capability by wiring it into the spine, never a parallel dispatcher/palette/dashboard:

1. **One dispatcher** — `shell/claw-fn.zsh` owns the only `claw()` shell function (in-shell work: TUI relaunch, `load`/`off`); everything else passes through to `bin/claw` (bash) → `scripts/`.
2. **One theme engine** — `scripts/utils/theme.sh` is the single color source. Palettes live in `config/themes/<slug>/palette.theme`; every surface (prompt, dashboards, fzf, the Rust TUI, clin) consumes `CLAW_C_*` / `CLAW_RGB_*`.
3. **One render path** — login + default profile render `scripts/utils/claw-dashboard.py` (framed dashboard); fastfetch is the per-profile art + fallback.

## Quick Install

```bash
# One-liner (clones repo + runs bootstrap)
curl -fsSL https://raw.githubusercontent.com/hankthebldr/dot-files/master/install.sh | bash

# Or manual
git clone https://github.com/hankthebldr/dot-files.git ~/.dotfiles
cd ~/.dotfiles && ./bootstrap.sh
```

After install, open a new shell and try `claw help`.

### Options

```
./bootstrap.sh              # Full install (9 steps + claw verification)
./bootstrap.sh --minimal    # Essentials only (zsh, modern CLI, symlinks)
./bootstrap.sh --security   # Include pentesting tools
./bootstrap.sh --dry-run    # Preview without changes
```

### Documentation

- **[User Guide](docs/claw.md)** — single-page reference for the `claw` command (profile loading, agents, doctor)
- **[Architecture](docs/ARCHITECTURE.md)** — system topology and module map (auto-generated)
- **[Aliases](docs/ALIASES.md)** — full alias reference (auto-generated)
- **[Changelog](CHANGELOG.md)** — release notes

### What Bootstrap Does

| Step | What | macOS | Ubuntu |
|------|------|-------|--------|
| 1 | Symlink repo to `~/.dotfiles` | `ln -sf` | `ln -sf` |
| 2 | Backup existing configs | `.zshrc`, `.gitconfig`, `.tmux.conf` | same |
| 3 | Package manager | Homebrew | apt + Linuxbrew |
| 4 | Essentials | git, zsh, tmux, stow, curl | same |
| 5 | Zsh + Oh-My-Zsh + Powerlevel10k | chsh + OMZ + P10k | same |
| 6 | Modern CLI tools | eza, bat, fzf, rg, fd, gum, yq, chafa | same |
| 7 | Nerd Fonts | brew --cask | curl + fc-cache |
| 8 | Symlinks | GNU Stow (shell, git, vim, tmux, config) | same |
| 8b | **`bin/claw` chmod + smoke test** | yes | yes |
| 9 | Extras | dev-tools, macOS defaults | dev-tools, xclip |

Step 8b ensures the `claw` dispatcher is executable and verifies it runs before printing the success card.

---

## The `claw` Command

One entry point. All workflows. `bin/claw` is a ~1000-line bash dispatcher on PATH (set inline in `shell/.zshrc` step 1, before the welcome TUI); `shell/claw-fn.zsh` intercepts `claw load`/`claw off` so they mutate the parent shell (the bash binary alone can't).

```
# Core
claw                  open the welcome menu (FZF picker)
claw help             list every subcommand
claw doctor           system + active-profile health
claw load <profile>   source a profile in current shell   (claw off to clear)
claw <agent>          launch a registered agent (claude · gemini · hermes · opencode · openwork · …)

# Look & feel
claw theme [set <slug>]   switch color palette — single source of truth, all surfaces follow
claw output               persist render settings (mode rich/plain · frame · banner)
claw onboard              80s arcade character-creation profile picker

# Profiles, packages, updates
claw profiles lint    mechanically validate all 18 profile contracts
claw install <tc>     opt-in toolchain installer (cloud/security/ai/devops/…)
claw tools            curated CLI tool refresh (staggered cache)
claw update           heavy hammer — every package manager
claw pkg              self-aware package manifest (track/scan/install)
claw provision        one-pass fresh-box setup

# AI
claw ai               Ollama / open-webui / n8n umbrella
claw ai-services      self-hosted AI web stacks (open-webui/dify/ragflow/langfuse)

# Infra & ops
claw tun              SSH tunnel manager           claw homelab   homelab SSH topology
claw situation        fleet awareness snapshot     claw docker    container overview
claw mcp              MCP server manager           claw toolkit   workflow launcher
claw notify           desktop notification ("Title" "Body" · --crit · --after -- <cmd>)

# Knowledge
claw obsidian         vault helpers (profile-aware)  [claw vault]
claw clin             Obsidian-style note TUI (theme/vault-synced)
claw skills           browse Claude skills (FZF over ~/.claude/skills)

# Security & integrity
claw secret           age/sops-encrypted secrets (init/encrypt/edit/env)
claw integrity        SHA-256 tamper/partial-install audit
claw validate         live reachability + config-chain checks

# Claude Code harness
claw harness          custom skills/commands/agents (list/new/deploy/sync/capture)

# Agents
claw agent list       list registered agents        claw agent add   register in agents.toml
```

Full reference: [`docs/claw.md`](docs/claw.md).

---

## Workflow Profiles

18 profiles (8 core + 10 specialized), each with a fastfetch dashboard rendering a real brand logo (chafa half-block, 24-bit color).

| Profile | Focus | Help | Logo brand |
|---------|-------|------|------------|
| **default** | Daily driver with cheatsheet | `default-help` | Apple (OS native) |
| **claude** | Anthropic Claude Code workspace | `claude-help` | Anthropic |
| **cloud** | AWS · GCP · Kubernetes · Terraform | `cloud-help` | Kubernetes |
| **security** | Pentesting · DFIR · reverse engineering | `sec-help` | Kali Linux |
| **devops** | CI/CD · monitoring · IaC | `devops-help` | Docker |
| **ai** | Ollama · LLMs · MLOps | `ai-help` | HuggingFace |
| **research** | Datasets · scraping · NLP | `research-help` | Jupyter |
| **cortex** | Palo Alto XSOAR · XSIAM · PAN-OS | `cortex-help` | Cortex orange |
| **local** | Custom-built CLI tools (auto-loaded specs) | `local-help` | Raspberry Pi |

**Specialized profiles** (same structure, narrower job):

| Profile | Focus | Help |
|---------|-------|------|
| **blackwell** | Local-LLM workstation — big models on the BD790i | `blackwell-help` |
| **brainstorm** | Capture sparks before they cool (VHS theme) | `brainstorm-help` |
| **deck** | Ship customer artifacts on a deadline (Cortex deck system) | `deck-help` |
| **demo** | Screen-share-safe — never leak a secret on stage | `demo-help` |
| **design** | Diagrams & visual storytelling | `design-help` |
| **homelab** | BD790i ops — K3s, Tailscale, alerts | `homelab-help` |
| **pmo** | Things 3 ↔ repo ↔ PR workflow (DOS-BBS theme) | `pmo-help` |
| **tunnels** | SSH tunnel manager — multi-hop port-forwards | `tunnels-help` |
| **vault** | Obsidian second-brain organization | `vault-help` |

Each profile is a **directory**, not a single file: a thin 5-line dispatcher `shell/profiles/<name>.zsh` sources `<name>/{meta,common,mac|linux}.zsh` (platform-split so macOS/Linux-only aliases don't leak cross-platform). Each provides:
- `meta.zsh` — identity (`PROFILE_CLASS`, `PROFILE_THEME_DEFAULT`, `PROFILE_TOOLCHAIN`, `PROFILE_KEY_TOOLS`)
- `common.zsh` — domain-specific aliases (short, **unprefixed** — no `cloud-k`, just `k`), the `<profile>-help` card, and `_<profile>_tool_check`
- `mac.zsh` / `linux.zsh` — platform-specific extras, sourced conditionally
- Themed fastfetch dashboard (`config/.config/fastfetch/config-<profile>.jsonc`)

`claw profiles lint` mechanically validates every profile's contract (declared toolchain resolves on disk, help + tool-check present, no dead metadata) and runs in CI, so a half-wired profile can't merge.

### Activating

```bash
# From the welcome menu — pick a profile row
# OR
claw load cloud         # sources cloud profile in current shell + renders dashboard
claw off                # clears active profile

# Per-shell override (no menu needed)
export CLAW_ACTIVE_PROFILE=cortex && exec zsh
```

### Customizing logos

Each profile's logo is generated from a real brand SVG via `chafa`. Swap any in one command:

```bash
bash scripts/utils/logo-from-image.sh ai https://cdn.simpleicons.org/openai
bash scripts/utils/logo-from-image.sh cloud ~/Downloads/aws-logo.png
```

---

## Agents

Pluggable registry at `~/.config/claw/agents.toml` (auto-created on first run with `[claude]` pre-registered):

```toml
[claude]
command = "claude"
profile = "claude"      # optional — auto-load this profile before launch
description = "Anthropic Claude Code"

# Future agents: just add a [section]
[hermes]
command = "hermes-cli"
profile = "ai"
description = "Hermes 70B local agent"

[aider]
command = "aider"
profile = "ai"
description = "Aider pair-programmer"
```

Then:

```bash
claw agent list           # see what's registered
claw agent add hermes hermes-cli ai
claw hermes               # → loads ai profile dashboard, then exec hermes-cli
```

`claw <agent>` resolves the registry, optionally renders the matching profile's fastfetch dashboard, then `exec`s the binary. Adding a new agent is a TOML edit, never a code change. Registered agents include `claude`, `gemini`, `hermes` (local Nous Hermes), `openrouter`, `aichat`, and the terminal AI coding agents **opencode** and **openwork** (headless OpenWork orchestrator on opencode).

---

## Theme Engine

One palette drives every surface. `scripts/utils/theme.sh` is the single source of truth; palettes live in `config/themes/<slug>/palette.theme` (bare `key=hex`), rendered into `CLAW_C_*` / `CLAW_RGB_*` that the prompt, dashboards, fzf, the Rust TUI, and clin all consume. No surface hardcodes color.

```bash
claw theme                # list palettes (● = active)
claw theme set tokyo-night
claw theme preview matrix
claw theme fzf            # live-swatch picker
```

Precedence: `CLAW_THEME` env (set by profile loads) → persisted `claw theme set` → refined-dark fallback. `claw theme set` re-renders the Ghostty include and clin's config so the whole environment tracks one palette. Six library themes ship (refined-dark, github-dark, catppuccin-mocha, tokyo-night, rose-pine, gruvbox-material) plus the flat classics (matrix, synthwave, vhs, dosbbs).

---

## Native Rust TUI (`claw-tui`)

An optional ratatui welcome screen at `tui/claw-tui/` — a truecolor logo, a two-column categorized profile/action picker, and a native readout — reading the same theme state as the shell (`src/theme.rs`). It emits an outcome contract (`ACTION`/`EXEC`/`PROFILE`/`NONE`) that the zsh side applies, so selecting a profile mutates the parent shell. Opt in with `CLAW_TUI=1`; the fzf welcome-TUI remains the default.

---

## Claude Code Harness

The `claude/` tree is a versioned Claude Code config, deployed into `~/.claude/` by `scripts/setup/link-claude.sh` (item-level, backup-on-collision, idempotent) — **not** GNU-Stowed. It carries:

- **Hooks** (`claude/hooks/`) — a `pre_tool_use.py` that default-denies out-of-scope recon (segment-aware, defeats `sudo`/chain/env-prefix bypass), blocks credential exfil and catastrophic ops, and guards generator-owned files; a `post_tool_use.py` that logs every call to SQLite and lints edited shell files at the CI tier.
- **Harness** (`claude/harness/`) — custom skills/commands/agents/plugins, managed via `claw harness {list|new|deploy|sync|capture}`.
- A repo-scoped agent-readable **knowledge base** (`knowledge-base/`) of verified structural facts.

---

## Secrets (age + sops)

`claw secret` is the offline-first secret store — `age` keypair, `sops` encrypting only the *values* so files stay diffable and git-safe.

```bash
claw secret init          # generate an age key (idempotent), print pubkey
claw secret env           # edit the encrypted env (config/secrets/.env.sops)
claw secret doctor        # age/sops/key/.sops.yaml presence
```

The encrypted env auto-loads at shell start (decrypted in a subprocess so `set -u`/`pipefail` never leak into the interactive shell). API keys reference `op://` 1Password paths or land here — never plaintext in the repo.

---

## Integrity & Validation

```bash
claw integrity generate   # SHA-256 manifest of the whole tree (config/integrity/)
claw integrity verify     # diff on-disk vs manifest — CHANGED/MISSING/EXTRA, exit 1 on drift
claw integrity audit      # verify + provenance (git commit/branch, manifest age)
claw validate             # live reachability of services + config-chain checks
```

Portable across macOS (`shasum`) and Linux (`sha256sum`); auto-generated at the end of `bootstrap.sh`.

---

## Self-Hosted AI Stacks

`claw ai-services` manages self-hosted AI web stacks under namespaced `claw-<svc>` compose projects:

```bash
claw ai-services up open-webui    # ChatGPT-style Ollama UI          :3000
claw ai-services up langfuse      # LLM observability / tracing
claw ai-services up dify          # LLM app-builder platform         :8080
claw ai-services up ragflow       # RAG engine w/ deep-doc parsing   :8081
claw ai-services status           # live reachability of each stack
```

`local` services ship their compose file in the repo (`config/<svc>/`); `upstream` services shallow-clone the project's repo into a per-machine data dir and run *their* version-coupled compose. Port map is collision-free.

---

## Obsidian Vault Integration (profile-aware folder routing)

One registered vault — `~/hr-vault-main-pa` — with **profile-aware routing at the folder level**: the active profile selects a top-level folder *inside* the vault that the scoped helpers target. Daily notes stay global.

```bash
o                         # cd into the active profile's folder
on "Note Title"           # create + open note in that folder
os "search term"          # ripgrep + fzf within that folder
ov                        # fzf over file names in that folder
otoday                    # open/create today's GLOBAL daily note (Daily Note/)
ocapture "thought"        # append timestamped line to today's daily
ovaults                   # show active folder + list the vault's folders
ovuse <folder>            # switch active folder for this shell
```

Or via dispatcher:

```bash
claw obsidian             # open the vault in Obsidian.app
claw obsidian today
claw obsidian search "kubernetes incident"
claw obsidian capture "stand-up notes for Q3"
```

**Profile → folder map** (unlisted profiles and no-profile shells route to the `_wip` triage folder):

| Profile | Folder |
|---------|--------|
| `cortex`, `deck` | `CORTEX` |
| `devops` | `DEVELOPMENT` |
| `pmo` | `WWTS - Projects` |
| `security` | `Secops` |
| `cloud` | `PUBLIC CLOUD PROVIDERS` |
| `ai`, `claude` | `_agents` |
| everything else | `_wip` (triage) |

Daily notes (`otoday`/`ocapture`) are **global** — always the `Daily Note/` journal, independent of the active profile.

Override per-shell:

```bash
export OBSIDIAN_FOLDER_OVERRIDE="Secops"                 # force a folder (or: ovuse Secops)
export OBSIDIAN_VAULT_OVERRIDE="$HOME/some-other-vault"  # rare: a different vault entirely
```

Optional **profile-load breadcrumbs**: `export CLAW_VAULT_BREADCRUMBS=1` to auto-log every profile load (`[HH:MM] Loaded **<profile>** profile`) under the global daily note's "Profile log" section.

---

## Modern CLI

| Legacy | Modern | What Changes |
|--------|--------|--------------|
| ls | **eza** | Icons, git status, tree view |
| cat | **bat** | Syntax highlighting, line numbers |
| grep | **ripgrep** | 10× faster, respects .gitignore |
| find | **fd** | Simpler syntax, colors |
| cd | **zoxide** | Learns your habits, fuzzy jump |
| top | **btop** | Beautiful system monitor |
| diff | **delta** | Side-by-side, syntax-aware |
| du | **dust** | Visual disk usage |
| df | **duf** | Colored disk free |
| history | **atuin** | Searchable + synced |

---

## SSH Tunnel Manager

```bash
claw tun     # interactive TUI with ASCII topology
tun          # alias
tunls        # list active tunnels
tunkill      # disconnect all
tuntopo      # show topology for a named tunnel
```

Local (-L), Remote (-R), SOCKS (-D) tunnels with multi-hop ProxyJump and per-hop SSH keys. YAML config at `config/ssh/tunnels.yml`.

---

## SSH Auto-Provisioning

```bash
ssh-deploy myserver           # push portable dev env to a remote
ssh-deploy --dry-run myserver # preview changes
```

Deploys a zero-dependency shell + vim config to any remote via SSH heredoc. Works through jump hosts. Integrated into the homelab TUI (`claw homelab`).

---

## Homelab Fleet (HR-TRUST)

The `local` and `homelab` profiles render a live board of the HR-TRUST homelab.
A background poller writes one cache; every render reads it with **zero network**,
so login stays instant and SSH-safe.

```
fleet.yml ──► situation.sh probe_homelab() ──► ~/.cache/claw/homelab.json ──► homelab-board.sh
 (inventory)      (60s timer, atomic write)          (single contract)        (local + homelab + hstatus)
```

- **Inventory** — `config/homelab/fleet.yml`: 4 machines (`ms-01` cp · `r630` ·
  `bd790i` · `pihole`), a `cluster` block (`k3s-ms01` + Traefik probe IP), and a
  `services` map where each entry declares `kind`, `group` (apps/infra/dns), and a
  brand `glyph`. Adding a box or service is a data edit — no code change. A
  machine-local `$XDG_CONFIG_HOME/claw/fleet.yml` overrides it.
- **Services** — gitea, n8n, portainer, enclave, grafana (`*.lab.local` via
  Traefik), harbor (planned), k3s, docker, ollama, tailscale, and Pi-hole DNS.
  HTTP apps are probed by `Host:` header against the Traefik IP, so status works
  on-LAN and over a routed tailnet without depending on `*.lab.local` resolution.
- **Status vocabulary** — `●` green up · `●` amber degraded · `●` red down ·
  `○` muted planned. Stale cache (>5 min) dims with a `stale Xm ago` suffix;
  absent cache renders nothing.
- **Commands** — `claw situation homelab` refreshes the cache;
  `scripts/utils/homelab-board.sh all` prints the board; `hstatus` (homelab
  profile) shows it cache-first.

---

## Neovim IDE

Full lazy.nvim setup with 20+ plugins:

- **GitHub Dark** colorscheme matching the Open Claw palette
- **LSP** with 9 language servers (Python, Go, TypeScript, Bash, Terraform, YAML, JSON, Docker, Lua), auto-installed via Mason
- **Telescope** fuzzy finder, **nvim-tree** explorer, **harpoon** file marks
- **Treesitter** highlighting (18 languages)
- **nvim-cmp** completion (LSP, buffer, path, snippets)
- **conform** formatting, **nvim-lint** linting
- **gitsigns** + **fugitive**
- **toggleterm** floating terminal with **lazygit** integration

Keys: `<Space>` leader, `<leader>ff` find files, `<leader>e` file tree, `gd` go-to-def, `<C-\>` terminal.

---

## Network Tools

```bash
netcheck     # full diagnostic dashboard (IP, gateway, DNS, VPN, ports)
ports        # listening services
conns        # all connections
headers URL  # HTTP headers
timing URL   # curl timing breakdown
dns DOMAIN   # quick DNS lookup
bw           # per-process bandwidth (bandwhich)
```

---

## System Update / Tool Refresh

Two-tier:

```bash
claw update      # heavy hammer — every package manager (brew/npm/yarn/
                 # pnpm/uv/pipx/pip/gem/rustup/go/oh-my-zsh)

claw tools       # curated tools only (eza/bat/zoxide/fd/rg/bottom/
                 # zellij/rovr/osint-d2/clawea/netwatch-tui/eilmeldung)
                 # Per-category cache: weekly brew/pipx, bi-weekly go,
                 # monthly cargo. --force overrides.
```

Both share `scripts/utils/tui-style.sh` for consistent visual polish (gum spinners, sectioned headers, summary cards).

Long-running single-process ops (`claw pkg install`/`track`/`scan`) render an inline themed **progress panel** framed in viewfinder corner brackets — rich on a TTY, degrading to clean plain log lines over SSH/CI; raw command output is captured off-screen to `${XDG_STATE_HOME}/claw/logs/`. Toggle it with `progress on|off`; tune display defaults (`mode`/`frame`/`banner`) with `claw output`.

---

## Repository Structure

```
~/.dotfiles/
├── bootstrap.sh                  # Primary installer (9 steps + claw verify)
├── install.sh                    # One-liner curl wrapper
├── bin/claw                      # Single bash dispatcher (~1000 lines)
├── shell/
│   ├── .zshrc                    # Main config; PATH set inline (brew, cargo, go, bin/claw)
│   ├── platform.zsh              # Cross-platform shims (clip/open/IP/vpn)
│   ├── exports.zsh               # Environment variables
│   ├── aliases.zsh               # Core aliases & functions
│   ├── load-env.zsh              # .env + sops secret auto-load (subprocess-guarded)
│   ├── obsidian.zsh · clin.zsh   # Vault routing + note TUI (theme/vault-synced)
│   ├── claw-fn.zsh               # zsh fn for claw load/off (parent shell) — sole claw()
│   ├── profile-helpers.zsh       # Generic tool-check + install-hint helpers
│   ├── welcome-tui.zsh           # Interactive fzf login dashboard
│   └── profiles/                 # 18 workflow profiles (directory-per-profile)
├── tui/claw-tui/                 # Native Rust ratatui welcome screen (opt-in)
├── vim/config/nvim/              # Neovim config (lazy.nvim)
├── config/
│   ├── themes/<slug>/            # Theme library — palette.theme + ghostty.conf (single color source)
│   ├── .config/fastfetch/        # 19 dashboards (9 generated + 10 hand-maintained) + logos
│   ├── homelab/fleet.yml         # Homelab inventory
│   ├── secrets/.env.sops         # sops-encrypted env (git-safe; created by `claw secret`)
│   └── ssh/                      # Tunnel configs + remote-env
├── claude/                       # Claude Code config (hooks, harness, skills) → ~/.claude
├── knowledge-base/               # Agent-readable repo-structural facts (INDEX + topics/)
├── scripts/
│   ├── install/                  # Package & toolchain installers (+ lib/toolchain-runner.sh)
│   ├── utils/                    # theme, claw-dashboard.py, gen-fastfetch, ai-services,
│   │                             # secret, integrity, pkg-manifest, profiles-lint, …
│   └── setup/                    # GNU Stow + link-claude.sh deployment
├── tests/                        # bats suites + shellcheck harness (CI-gated)
├── legacy/                       # Archived/superseded scripts (see README)
├── docs/
│   ├── claw.md                   # Full claw user guide
│   └── superpowers/specs/        # Design specs for major changes
├── git/.gitconfig · tmux/.tmux.conf · terminal/.config/starship.toml
```

---

## Daily Usage

```bash
# Single entry point
claw                  # open menu
claw doctor           # health check
claw load cloud       # context-switch in current shell

# Profile-scoped help
default-help          # daily driver cheatsheet
sec-help              # security profile commands
cortex-help           # cortex profile commands

# Navigation
z <dir>               # smart cd (zoxide)
Ctrl+R                # fuzzy history (atuin)
Ctrl+T                # fuzzy file finder (fzf)
Alt+C                 # fuzzy cd

# Tools
glg                   # lazygit
lzd                   # lazydocker
nvim                  # Neovim IDE
tun                   # SSH tunnel manager
halp <cmd>            # tldr simplified man pages
reload                # reload shell config

# Display & progress
claw output           # persist display: mode rich/plain · frame · banner
progress on / off     # live progress panel for long pkg ops (master switch)
```

---

## Customization

- **Local overrides:** create `~/.zshrc.local` (not tracked) — put machine-specific `export`s here, never in the tracked `.zshrc`
- **Environment variables:** copy `.env.example` to `.env`; secrets go through `claw secret` (sops), not plaintext
- **Theme:** `claw theme set <slug>`; add a palette at `config/themes/<slug>/palette.theme` — every surface follows automatically
- **Profiles:** a profile is a **directory** `shell/profiles/<name>/`; scaffold with the `new-profile` harness skill, then `claw profiles lint`
- **Logos:** swap with `bash scripts/utils/logo-from-image.sh <profile> <url>`
- **Agents:** edit `~/.config/claw/agents.toml` (TOML edit, no code changes)
- **Vault routing:** override per-shell with `export OBSIDIAN_VAULT_OVERRIDE=<name-or-path>`
- **SSH tunnels:** `config/ssh/tunnels.yml` (see `.example`)
- **Claude harness:** add skills/commands/agents under `claude/harness/`, then `claw harness deploy`
- **Display:** persist render settings with `claw output` (`mode` rich/plain · `frame` viewfinder/none · `banner` on/off); state in `${XDG_STATE_HOME}/claw/output`
- **Live progress:** master switch `progress on|off|status` (exports `CLAW_PROGRESS_ENABLED`); panel defaults tuned via `claw output`

---

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | Full support |
| macOS (Intel) | Full support |
| Ubuntu / Debian | Full support |
| Kali / Parrot | Full support + security tools |

Tested on stock macOS bash 3.2 and zsh 5.9. The `bin/claw` dispatcher is bash-portable; `shell/claw-fn.zsh` is zsh-only (intentional — needs to mutate parent shell).

---

## Documentation

- [`docs/claw.md`](docs/claw.md) — full claw command reference
- [`CLAUDE.md`](CLAUDE.md) — repo conventions for AI-assisted development
- [`docs/superpowers/specs/`](docs/superpowers/specs/) — design specs for major refactors

---

### Built with Open Claw
