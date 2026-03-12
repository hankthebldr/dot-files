# 🐱 Open Claw — Production-Ready CLI for macOS

> A modular, best-in-class shell configuration system optimized for security, performance, and aesthetics.

## ✨ Features

### Welcome TUI
Interactive login dashboard powered by `fzf` with 17 launchable actions — profile switching, system monitor, file manager, AI toolkit, MCP manager, and more.

### Dynamic Profiles
Switch your entire shell personality on login:

| Profile | Focus |
|---------|-------|
| **Default** | Standard development |
| **Security** | Pentesting & scanners |
| **Cloud** | AWS / K8s / Terraform |
| **DevOps** | CI/CD / Monitoring / IaC |
| **Research** | Datasets & scraping |
| **AI** | LLMs / Embeddings / MLOps |
| **Cortex** | XSOAR / XSIAM / PAN-OS |
| **Local** | Custom built CLI tools |

### Toolkit TUI
8-category interactive workflow launcher:
- Git & Development · Docker Management · Kubernetes · Cloud & IaC
- Security Scanning · System Utilities · Knowledge (Obsidian) · Agentic AI

### Modern CLI Replacements

| Legacy | Modern | Alias |
|--------|--------|-------|
| `ls` | **eza** | `l`, `ll`, `la`, `lt` |
| `cat` | **bat** | `cat`, `catp`, `catn` |
| `grep` | **ripgrep** | `grep`, `gi`, `rga` |
| `find` | **fd** | via fzf integration |
| `cd` | **zoxide** | `cd` (after init) |
| `top` | **btop** | `top`, `cpu` |
| `du` | **dust** | `du` |
| `df` | **duf** | `df` |
| `diff` | **delta** | `diff` |
| `man` | **tldr** | `halp`, `cheat` |

### Integrated Tools
- **Starship** prompt (GitHub Dark theme)
- **Atuin** shell history with sync
- **fzf** fuzzy finder throughout (branch switching, k8s contexts, AWS profiles)
- **Obsidian** vault integration (search, create, open notes from terminal)
- **MCP Manager** for Model Context Protocol servers
- **Homelab SSH Manager** with interactive host selection
- **System Update** script (Homebrew, npm, yarn, pnpm, pip, rustup, Go, OMZ)

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/hankthebldr/dot-files.git ~/.dotfiles
cd ~/.dotfiles

# Run the master bootstrap script
./bootstrap.sh

# Or install specific categories
bash scripts/install/master-setup.sh shell
bash scripts/install/master-setup.sh dev
bash scripts/install/master-setup.sh domains
```

### Bootstrap Options

```
./bootstrap.sh [options]
  --minimal      Install only essentials
  --no-backup    Skip backup
  --dry-run      Show what would happen
  --security     Install security/pentest tools
```

---

## 📁 Structure

```
├── bootstrap.sh              # Master entry point
├── .zshrc                    # Main shell config (sources everything)
├── shell/
│   ├── aliases.zsh           # 400+ aliases & smart functions
│   ├── exports.zsh           # Environment variables, history, FZF
│   ├── path.zsh              # PATH management
│   ├── security.zsh          # Security aliases & safety nets
│   ├── obsidian.zsh          # Obsidian vault integration
│   ├── load-env.zsh          # .env file loader
│   ├── welcome-tui.zsh       # Interactive login dashboard
│   └── profiles/             # Dynamic profile configs
├── scripts/
│   ├── install/              # Package & toolchain installers
│   ├── utils/                # Toolkit TUI, MCP manager, homelab, etc.
│   └── backup/               # Backup & restore
├── config/
│   ├── starship/             # Starship prompt config
│   ├── fastfetch/            # System info display
│   └── themes/               # Terminal color themes
├── git/                      # .gitconfig with delta integration
├── tmux/                     # .tmux.conf (GitHub Dark theme)
└── tests/                    # Test runner & shellcheck
```

---

## 📖 Daily Usage

### Getting Help
```bash
dothelp          # List all available custom aliases
halp <command>   # Quick help via tldr
cht <topic>      # Cheat.sh integration
```

### Key Shortcuts
```bash
tk               # Launch Toolkit TUI
claw             # Launch Open Claw
reload           # Reload shell config
brewup           # Update all Homebrew packages
```

---

## 🔧 Customization

To override settings without changing the repo, create `~/.zshrc.local`.

For environment variables, copy `.env.example` to `.env` and customize.

---

## 📚 Documentation

- [CLI Optimization Summary](docs/cli-optimization-summary.md)
- [Quick Commands Reference](docs/quick-commands-reference.md)
- [macOS Power User Setup](docs/macbook-pro-poweruser-setup.md)
- [Quick Start Guide](docs/quick-start-guide.md)

---

### Built with Open Claw 🐾
