# Open Claw — Cross-Platform CLI Environment

> Modular shell configuration system for macOS and Ubuntu/Debian. Profile-based workflows, modern CLI tools, interactive TUI, SSH tunnel management, and full Neovim IDE — all from one `bootstrap.sh`.

## Quick Install

```bash
# One-liner (clones repo + runs bootstrap)
curl -fsSL https://raw.githubusercontent.com/hankthebldr/dot-files/master/install.sh | bash

# Or manual
git clone https://github.com/hankthebldr/dot-files.git ~/.dotfiles
cd ~/.dotfiles && ./bootstrap.sh
```

### Options

```
./bootstrap.sh              # Full install (9 steps)
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
| 1 | Symlink repo to `~/.dotfiles` | ln -sf | ln -sf |
| 2 | Backup existing configs | .zshrc, .gitconfig, .tmux.conf | same |
| 3 | Package manager | Homebrew | apt + Linuxbrew |
| 4 | Essentials | git, zsh, tmux, stow, curl | same |
| 5 | Zsh + Oh-My-Zsh + Powerlevel10k | chsh + OMZ + P10k | same |
| 6 | Modern CLI tools | eza, bat, fzf, rg, fd, gum, yq | same |
| 7 | Nerd Fonts | brew --cask | curl + fc-cache |
| 8 | Symlinks | GNU Stow (shell, git, vim, tmux, config) | same |
| 9 | Extras | dev-tools, macOS defaults | dev-tools, xclip |

---

## Features

### Welcome TUI

Interactive FZF-powered login dashboard with fastfetch system info, 20+ launchable actions, and profile switching. Default profile selected on Enter, ESC drops to bare shell.

### Workflow Profiles

| Profile | Focus | Help Command |
|---------|-------|-------------|
| **Default** | Daily driver with cheatsheet | `default-help` |
| **Security** | Pentesting, scanners, OSINT | `sec-help` |
| **Cloud** | AWS, K8s, Terraform, GCP | `cloud-help` |
| **DevOps** | CI/CD, monitoring, IaC | `devops-help` |
| **AI** | LLMs, embeddings, MLOps | `ai-help` |
| **Research** | Datasets, scraping, NLP | `research-help` |
| **Cortex** | XSOAR, XSIAM, PAN-OS | `cortex-help` |
| **Local** | Custom built CLI tools | — |

Each profile provides: themed fastfetch dashboard, domain-specific aliases, `{profile}-help` reference card, and `_{profile}_tool_check` validation.

### Modern CLI

| Legacy | Modern | What Changes |
|--------|--------|-------------|
| ls | **eza** | Icons, git status, tree view |
| cat | **bat** | Syntax highlighting, line numbers |
| grep | **ripgrep** | 10x faster, respects .gitignore |
| find | **fd** | Simpler syntax, colors |
| cd | **zoxide** | Learns your habits, fuzzy jump |
| top | **btop** | Beautiful system monitor |
| diff | **delta** | Side-by-side, syntax aware |
| du | **dust** | Visual disk usage |
| df | **duf** | Colored disk free |

### SSH Tunnel Manager

```bash
tun          # Interactive TUI with ASCII topology diagrams
tunls        # List active tunnels
tunkill      # Disconnect all
tuntopo      # Show topology for a tunnel
```

Supports Local (-L), Remote (-R), SOCKS (-D) tunnels with multi-hop ProxyJump and per-hop SSH keys. YAML config at `config/ssh/tunnels.yml`.

### SSH Auto-Provisioning

```bash
ssh-deploy myserver          # Push portable dev env to remote
ssh-deploy --dry-run myserver  # Preview changes
```

Deploys a zero-dependency shell config + vim config to any remote machine via SSH heredoc. Works through jump hosts. Integrated into the Homelab TUI (Connect / Deploy / Both).

### Neovim IDE

Full lazy.nvim setup with 20+ plugins:

- **GitHub Dark** colorscheme matching Open Claw palette
- **LSP** with 9 language servers (Python, Go, TypeScript, Bash, Terraform, YAML, JSON, Docker, Lua) auto-installed via Mason
- **Telescope** fuzzy finder, **nvim-tree** file explorer, **harpoon** file marks
- **Treesitter** syntax highlighting (18 languages)
- **nvim-cmp** completion with LSP, buffer, path, snippets
- **conform** formatting, **nvim-lint** linting
- **gitsigns** + **fugitive** for git
- **toggleterm** floating terminal with lazygit integration

Key bindings: `<Space>` leader, `<leader>ff` find files, `<leader>e` file tree, `gd` go-to-def, `<C-\>` terminal.

### Network Tools

```bash
netcheck     # Full diagnostic dashboard (IP, gateway, DNS, internet, VPN, ports)
ports        # Listening services
conns        # All connections
headers URL  # HTTP headers
timing URL   # Full curl timing breakdown
dns DOMAIN   # Quick DNS lookup
bw           # Per-process bandwidth (bandwhich)
```

### System Update

```bash
update       # From TUI menu, or run directly
```

Updates Homebrew, npm, yarn, pnpm, uv, pipx, pip, gem, rustup, Go, and Oh-My-Zsh with gum spinners (graceful fallback to styled echo).

---

## Structure

```
~/.dotfiles/
├── bootstrap.sh                  # Primary installer (9 steps)
├── install.sh                    # One-liner curl wrapper
├── shell/
│   ├── .zshrc                    # Main config (cross-platform)
│   ├── platform.zsh              # Cross-platform shims
│   ├── path.zsh                  # PATH management (macOS/Linux brew)
│   ├── exports.zsh               # Environment variables
│   ├── aliases.zsh               # 680+ aliases & functions
│   ├── security.zsh              # Safety aliases + network recon
│   ├── obsidian.zsh              # Obsidian vault integration
│   ├── welcome-tui.zsh           # Interactive login dashboard
│   └── profiles/                 # 8 workflow profiles
├── vim/config/nvim/              # Neovim config (lazy.nvim)
│   ├── init.lua
│   └── lua/{core,plugins}/       # 17 config files
├── config/
│   ├── .config/fastfetch/        # 9 profile-specific dashboards
│   ├── ssh/                      # Tunnel configs + remote-env
│   └── .config/themes/           # iTerm + Terminal.app themes
├── scripts/
│   ├── install/                  # Package & toolchain installers
│   ├── utils/                    # tunnel-manager, toolkit, homelab, ssh-deploy
│   └── setup/                    # GNU Stow symlink deployment
├── git/.gitconfig                # Git config with delta
├── tmux/.tmux.conf               # Tmux (GitHub Dark, cross-platform clipboard)
└── terminal/.config/starship.toml
```

---

## Daily Usage

```bash
# Help
default-help     # Full command reference
netcheck         # Network diagnostics
halp <cmd>       # Simplified man pages (tldr)

# Navigation
z <dir>          # Smart cd (zoxide)
Ctrl+R           # Fuzzy history (atuin)
Ctrl+T           # Fuzzy file finder (fzf)

# Tools
tun              # SSH tunnel manager
glg              # Lazygit
lzd              # Lazydocker
nvim             # Neovim IDE
tk               # Toolkit TUI
reload           # Reload shell config
```

---

## Customization

- **Local overrides:** Create `~/.zshrc.local` (not tracked)
- **Environment variables:** Copy `.env.example` to `.env`
- **Profiles:** Add custom aliases in `shell/profiles/<name>.zsh`
- **SSH tunnels:** Edit `config/ssh/tunnels.yml` (see `.example`)

---

## Platform Support

| Platform | Status |
|----------|--------|
| macOS (Apple Silicon) | Full support |
| macOS (Intel) | Full support |
| Ubuntu / Debian | Full support |
| Kali / Parrot | Full support + security tools |

---

### Built with Open Claw
