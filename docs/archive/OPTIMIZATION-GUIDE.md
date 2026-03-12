# CLI Optimization Guide
**Generated:** 2025-10-16
**For:** macOS Production Laptop & ParrotOS Interoperability

## What Was Done

### 1. Installed Tools (20 new packages)
- **Modern CLI:** eza, zoxide, fd, dust, duf, procs, sd
- **Development:** neovim, lazygit, lazydocker
- **Productivity:** starship, navi, atuin, direnv, just, hyperfine, glow, stow

### 2. Created Configuration Files
- `aliases.zsh` - 150+ optimized aliases and functions
- `install-missing-tools.sh` - Automated installer script
- `activate-optimizations.sh` - Integration activator

### 3. Updated .zshrc
Your .zshrc now includes:
- Source for `aliases.zsh` (150+ shortcuts)
- Zoxide integration (smart cd)
- Starship integration (commented, optional)
- Direnv integration (per-directory env vars)
- Atuin integration (shell history sync)
- Eza aliases (modern ls with icons)

**Backup created:** `~/.zshrc.backup-20251016-161532`

---

## Quick Start Guide

### Activate Now
```bash
source ~/.zshrc
```

### Essential New Commands

**Navigation:**
```bash
z ~/Documents        # Jump to frequently used directories
z doc                # Partial match works too
zi                   # Interactive directory picker
```

**File Operations:**
```bash
ls                   # Beautiful ls with icons (eza)
ll                   # Detailed list with icons
lt                   # Tree view (2 levels)
tree                 # Full tree with icons
```

**Git Workflows:**
```bash
lazygit              # Full-screen Git TUI (amazing!)
gs                   # Quick git status
gcap "message"       # Add, commit, push in one command
gcof                 # Checkout branch with fzf picker
ghpr                 # Create GitHub PR from CLI
```

**Docker:**
```bash
lazydocker           # Full-screen Docker TUI
dps                  # docker ps
dex container sh     # docker exec -it
dclean               # Clean everything
```

**Kubernetes:**
```bash
k get pods           # kubectl get pods
kl pod-name -f       # Tail logs
kctx-switch          # Switch context with picker
kns-switch           # Switch namespace with picker
```

**Productivity:**
```bash
navi                 # Interactive cheatsheets (Ctrl+C to exit)
h command            # tldr help (faster than man pages)
glow README.md       # Render markdown beautifully
serve 8080           # Quick HTTP server
```

---

## Most Useful Aliases

### DevOps & Cloud
| Alias | Command | Description |
|-------|---------|-------------|
| `k` | kubectl | Kubernetes CLI |
| `tf` | terraform | Terraform CLI |
| `awsp` | (function) | Switch AWS profile with fzf |
| `gcset` | (gcloud) | Switch GCP project with fzf |
| `kctx-switch` | (function) | Switch K8s context |
| `kns-switch` | (function) | Switch K8s namespace |

### Git Shortcuts
| Alias | Command | Description |
|-------|---------|-------------|
| `gs` | git status -sb | Short status |
| `gd` | git diff | Diff (with delta) |
| `gcm` | git commit -m | Quick commit |
| `gcap` | (function) | Add, commit, push |
| `gcof` | (function) | Checkout with fzf |
| `gp` | git push | Push |
| `gpf` | git push --force-with-lease | Safe force push |

### File Operations
| Alias | Command | Description |
|-------|---------|-------------|
| `cat` | bat | Syntax highlighted cat |
| `grep` | rg | Fast ripgrep |
| `top` | btop | Beautiful system monitor |
| `..` | cd .. | Up one directory |
| `...` | cd ../.. | Up two directories |

### Smart Functions
| Function | Usage | Description |
|----------|-------|-------------|
| `mkcd` | mkcd newdir | Create and enter directory |
| `extract` | extract file.zip | Extract any archive |
| `fkill` | fkill | Find and kill process |
| `awsp` | awsp | Switch AWS profile |
| `psgrep` | psgrep nginx | Find process by name |

---

## Tool Highlights

### 🎨 Eza (Better ls)
```bash
ls           # Icons, colors, git status
ll           # Long format with metadata
la           # Include hidden files
lt           # Tree view (2 levels)
```

### 🚀 Zoxide (Smarter cd)
```bash
z docs       # Jump to ~/Documents
z proj web   # Jump to ~/projects/website
zi           # Interactive mode
```
*Learns your most-used directories and jumps there with partial matches*

### 💎 LazyGit
```bash
lazygit
```
**TUI with:**
- Visual commit history
- Stage/unstage files with space
- Interactive rebase
- Cherry-pick, stash, branches
- Press `?` for help

### 🐳 LazyDocker
```bash
lazydocker
```
**TUI with:**
- View all containers, images, volumes
- Real-time logs and stats
- Start/stop/restart containers
- Execute into containers
- Press `?` for help

### 📚 Navi (Interactive Cheatsheets)
```bash
navi         # Browse cheatsheets
navi --query docker    # Search for docker commands
```
*Ctrl+C to exit, Enter to run command*

### ✨ Atuin (Shell History)
```bash
# Automatically active! Press ↑ for enhanced history search
# Ctrl+R for interactive search across all history
```

### 🎯 Starship (Optional Prompt)
To switch from Powerlevel10k to Starship:
1. Edit `~/.zshrc`
2. Comment out: `ZSH_THEME="powerlevel10k/powerlevel10k"`
3. Uncomment: `eval "$(starship init zsh)"`
4. Reload: `source ~/.zshrc`

**Why Starship?**
- Cross-platform (works on ParrotOS)
- Fast (written in Rust)
- Simple TOML configuration
- Git-aware, shows context (Python venv, Node version, etc.)

---

## Configuration Locations

```
~/Github/Github_desktop/dot-files/
├── aliases.zsh                    # All aliases and functions
├── install-missing-tools.sh       # Reinstall tools
├── activate-optimizations.sh      # Re-run activation
└── OPTIMIZATION-GUIDE.md          # This file

~/.zshrc                           # Main shell config (modified)
~/.zshrc.backup-*                  # Backup of original
```

---

## ParrotOS Interoperability

### Tools that work identically on ParrotOS:
- ✅ eza, zoxide, fd, bat, ripgrep
- ✅ neovim, lazygit, lazydocker
- ✅ starship, atuin, direnv
- ✅ All git, kubectl, docker aliases

### To sync to ParrotOS:
```bash
# On ParrotOS
cd ~/dotfiles
git clone <your-repo> .

# Install tools (adjust package manager)
# apt install eza zoxide fd-find bat ripgrep neovim ...

# Or use this repo's structure:
./install-linux.sh  # Create this based on install-missing-tools.sh
source aliases.zsh
```

---

## Customization

### Add Your Own Aliases
Edit `~/Github/Github_desktop/dot-files/aliases.zsh` and add:
```bash
# My custom aliases
alias myalias='my command'
```

Then reload:
```bash
source ~/.zshrc
```

### Commit Changes
```bash
cd ~/Github/Github_desktop/dot-files
git add .
git commit -m "Update aliases"
git push
```

---

## Troubleshooting

### Issue: "Command not found"
```bash
# Reload shell
source ~/.zshrc

# Or restart terminal
```

### Issue: Aliases not working
```bash
# Check if aliases.zsh is sourced
grep "aliases.zsh" ~/.zshrc

# Manually source
source ~/Github/Github_desktop/dot-files/aliases.zsh
```

### Issue: Want to revert
```bash
# Restore backup
cp ~/.zshrc.backup-20251016-161532 ~/.zshrc
source ~/.zshrc
```

---

## Next Steps

### 1. Learn the Tools
- Run `lazygit` in a git repo
- Try `z` command for navigation
- Use `navi` for cheatsheets
- Press `Ctrl+R` to try atuin history

### 2. Customize
- Add project-specific aliases
- Configure starship prompt
- Set up direnv for projects

### 3. Sync to ParrotOS
- Create Linux install script
- Test aliases on ParrotOS
- Set up Gruvbox theme

### 4. Optional: Install Kitty Terminal
```bash
brew install --cask kitty

# Then configure with Gruvbox theme:
# ~/.config/kitty/kitty.conf
```

---

## Cheat Sheet

### Most Used Commands
```bash
# Navigation
z project        # Jump to project dir
..              # Up one level
ls              # List with icons

# Git
lazygit         # Git TUI
gs              # Status
gcof            # Checkout with picker
gcap "msg"      # Add, commit, push

# Docker
lazydocker      # Docker TUI
dps             # List containers
dex name sh     # Exec into container

# K8s
k get pods      # List pods
kl pod -f       # Tail logs
kctx-switch     # Change context

# Help
h command       # Quick help
navi            # Cheatsheets
```

---

## Resources

- **Eza:** https://github.com/eza-community/eza
- **Zoxide:** https://github.com/ajeetdsouza/zoxide
- **LazyGit:** https://github.com/jesseduffield/lazygit
- **LazyDocker:** https://github.com/jesseduffield/lazydocker
- **Starship:** https://starship.rs
- **Navi:** https://github.com/denisidoro/navi
- **Atuin:** https://github.com/atuinsh/atuin

---

**Happy optimizing! 🚀**
