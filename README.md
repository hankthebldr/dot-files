# Open Claw — Cross-Platform CLI Environment

> Modular shell configuration system for macOS and Ubuntu/Debian. Single-command surface (`claw`), 9 workflow profiles with brand-accurate fastfetch dashboards, agent-agnostic launcher, profile-aware Obsidian vault routing, modern CLI tools, SSH tunnel management, and full Neovim IDE — all from one `bootstrap.sh`.

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

One entry point. All workflows.

```
claw                  open the welcome menu (FZF picker)
claw help             list every subcommand
claw doctor           system + active-profile health
claw update           full system update (brew/npm/pip/etc)
claw tools            interactive curated CLI tool refresh
claw tun              SSH tunnel manager
claw mcp              MCP server manager
claw homelab          homelab SSH topology
claw toolkit          Open Claw workflow launcher
claw skills           browse Claude skills (FZF over ~/.claude/skills)
claw obsidian         vault helpers (profile-aware)  [aliased: claw vault]
claw load <profile>   source a profile in current shell
claw off              unset active profile
claw <agent>          launch a registered agent (claude, hermes, …)
claw agent list       list registered agents
claw agent add        register a new agent in agents.toml
claw install <tc>     opt-in toolchain installer (cloud/security/…)
```

`bin/claw` is added to PATH via `shell/path.zsh`. A zsh wrapper at `shell/claw-fn.zsh` intercepts `claw load`/`claw off` so they actually mutate the parent shell (the bash binary alone can't).

Full reference: [`docs/claw.md`](docs/claw.md).

---

## Workflow Profiles

Nine profiles, each with a hand-tuned fastfetch dashboard rendering a real brand logo (chafa half-block, 24-bit color).

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

Each profile provides:
- Themed fastfetch dashboard (`config/.config/fastfetch/config-<profile>.jsonc`)
- Domain-specific aliases (short, **unprefixed** — no `cloud-k`, just `k`)
- `<profile>-help` quick-reference card
- `_<profile>_tool_check` install-status validator
- Optional `_claw_guard` wrappers that print install hints when a tool is missing

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

`claw <agent>` resolves the registry, optionally renders the matching profile's fastfetch dashboard, then `exec`s the binary. Adding a new agent is a TOML edit, never a code change.

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

---

## Repository Structure

```
~/.dotfiles/
├── bootstrap.sh                  # Primary installer (9 steps + claw verify)
├── install.sh                    # One-liner curl wrapper
├── bin/
│   └── claw                      # Single dispatcher (~250 lines)
├── shell/
│   ├── .zshrc                    # Main config (cross-platform)
│   ├── platform.zsh              # Cross-platform shims (clip/open/IP)
│   ├── path.zsh                  # PATH (brew, cargo, go, bin/claw)
│   ├── exports.zsh               # Environment variables
│   ├── aliases.zsh               # ~680 lines of aliases & functions
│   ├── security.zsh              # Safety aliases + network recon
│   ├── obsidian.zsh              # Profile-aware folder routing + helpers
│   ├── claw-fn.zsh               # zsh fn for claw load/off (parent shell)
│   ├── profile-helpers.zsh       # _claw_guard for install-hint aliases
│   ├── welcome-tui.zsh           # Interactive login dashboard
│   └── profiles/                 # 9 workflow profiles
├── vim/config/nvim/              # Neovim config (lazy.nvim)
├── config/
│   ├── .config/fastfetch/        # 9 profile-specific dashboards + logos
│   ├── ssh/                      # Tunnel configs + remote-env
│   └── .config/themes/           # iTerm + Terminal.app themes
├── scripts/
│   ├── install/                  # Package & toolchain installers
│   ├── utils/                    # tunnel-manager, toolkit, homelab,
│   │                             # mcp-manager, system-update, tool-updater,
│   │                             # tui-style, logo-from-image
│   └── setup/                    # GNU Stow symlink deployment
├── docs/
│   ├── claw.md                   # Full claw user guide
│   └── superpowers/specs/        # Design specs for major changes
├── git/.gitconfig                # Git config with delta
├── tmux/.tmux.conf               # Tmux (GitHub Dark, cross-platform clip)
└── terminal/.config/starship.toml
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
```

---

## Customization

- **Local overrides:** create `~/.zshrc.local` (not tracked)
- **Environment variables:** copy `.env.example` to `.env`
- **Profiles:** add aliases to `shell/profiles/<name>.zsh`; new profile = new file
- **Logos:** swap with `bash scripts/utils/logo-from-image.sh <profile> <url>`
- **Agents:** edit `~/.config/claw/agents.toml` (TOML edit, no code changes)
- **Vault routing:** override per-shell with `export OBSIDIAN_VAULT_OVERRIDE=<name-or-path>`
- **SSH tunnels:** `config/ssh/tunnels.yml` (see `.example`)
- **Profile-load breadcrumbs:** `export CLAW_VAULT_BREADCRUMBS=1`

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
