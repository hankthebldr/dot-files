# Ubuntu/Kali/Parrot Installer Design

Date: 2026-03-05

## Goal

Extend the dot-files bootstrap to support Ubuntu 22.04+, Kali, and Parrot with a unified `./bootstrap.sh` entry point and an interactive FZF configuration wizard. The end-user experience: clone the repo, run one command, pick your components from a menu, and get a fully configured developer environment.

## Decisions

- **Target distros:** Ubuntu 22.04+ LTS, Kali, Parrot
- **Approach:** Unified bootstrap (extend existing `bootstrap.sh`, not a separate entry point)
- **Package strategy:** Hybrid — apt for system packages, Linuxbrew for modern CLI tools
- **Wizard UX:** FZF multi-select menu (consistent with existing TUI design language)
- **System config:** Full workstation setup (firewall, SSH hardening, GNOME tweaks, sysctl tuning)

## Installation Flow

```
./bootstrap.sh
    │
    ├── detect_os → OS_TYPE=ubuntu|kali|parrot, PKG_MANAGER=apt
    ├── pre-flight checks (internet, disk space, sudo access)
    ├── install bootstrap deps: apt install -y curl git zsh fzf
    │
    ├── FZF CONFIGURATION WIZARD (--wizard flag, or first install)
    │   │  Multi-select component picker:
    │   │   ✓ Core Shell (zsh, starship, fzf, zoxide, atuin)     [always on]
    │   │   ✓ Modern CLI (eza, bat, ripgrep, fd, btop, lazygit)  [default on]
    │   │   ☐ Development (node, python, go, rust, databases)
    │   │   ☐ DevOps (docker, kubectl, helm, k9s, terraform)
    │   │   ☐ Cloud (awscli, gcloud, azure-cli)
    │   │   ☐ Security (nmap, trivy, grype, metasploit)
    │   │   ☐ AI/ML (ollama, pipx AI tools, huggingface-cli)
    │   │   ☐ Research (csvkit, pandoc, yt-dlp)
    │   │   ☐ Cortex (demisto-sdk, panos-cli)
    │   └── Selections saved to ~/.config/claw/install-manifest.json
    │
    ├── Phase 1: apt base packages
    ├── Phase 2: Install Linuxbrew
    ├── Phase 3: brew install modern CLI tools
    ├── Phase 4: Install selected toolchains
    ├── Phase 5: System configuration (ubuntu.sh)
    ├── Phase 6: Symlink dotfiles via stow
    └── Phase 7: chsh -s $(which zsh), print next steps
```

On repeat runs, the wizard is skipped (reads saved manifest) unless `--wizard` is passed.
Kali/Parrot auto-enable Security components.

## Package Strategy

### Phase 1 — apt base layer

```
build-essential curl wget git zsh tmux unzip tar tree stow
python3 python3-pip python3-venv pipx
software-properties-common apt-transport-https ca-certificates gnupg
fastfetch xclip
```

Distro-specific apt additions:
- Ubuntu: Official repos for Docker, GitHub CLI, kubectl, gcloud, azure-cli
- Kali/Parrot: Security tools already in repos (nmap, sqlmap, hydra, john, aircrack-ng, etc.)

### Phase 2 — Linuxbrew (modern CLI)

```
eza bat ripgrep fd zoxide fzf starship btop lazygit neovim
jq yq glow navi tldr k9s helm terraform gh atuin git-delta
```

Rationale: Ubuntu apt packages for these are missing, ancient, or have different binary names (batcat, fdfind). Brew provides consistent names matching macOS aliases.

### Phase 3 — Toolchain-specific (wizard-selected)

- **DevOps:** Docker (apt), kubectl (k8s apt repo), helm+k9s+terraform (brew)
- **Cloud:** awscli (pipx), gcloud (Google apt repo), azure-cli (MS apt repo)
- **AI:** ollama (curl installer), pipx tools (openai, anthropic, langchain, etc.)
- **Security on Ubuntu:** trivy (aquasec repo), grype (brew), nmap (apt)

## Shell Portability Layer

New file `shell/platform.zsh` provides OS-conditional shim variables:

| Variable | macOS | Linux |
|----------|-------|-------|
| `CLAW_PLATFORM` | `macos` | `linux` |
| `CLAW_CLIPBOARD_COPY` | `pbcopy` | `xclip -selection clipboard` |
| `CLAW_CLIPBOARD_PASTE` | `pbpaste` | `xclip -selection clipboard -o` |
| `CLAW_OPEN_CMD` | `open` | `xdg-open` |
| `CLAW_LOCAL_IP_CMD` | `ipconfig getifaddr en0` | `hostname -I \| awk '{print $1}'` |
| `CLAW_SPEED_CMD` | `networkQuality` | `speedtest-cli --simple` |

Also handles Homebrew path setup:
- macOS: `/opt/homebrew/bin/brew shellenv`
- Linux: `/home/linuxbrew/.linuxbrew/bin/brew shellenv`

`.zshrc` sources `platform.zsh` first, then uses `$HOMEBREW_PREFIX` for plugin paths:
```zsh
local _zsh_hl="${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f "$_zsh_hl" ]] && source "$_zsh_hl"
```

Aliases change from hardcoded commands to shim variables:
```zsh
alias copy='$CLAW_CLIPBOARD_COPY'
alias paste='$CLAW_CLIPBOARD_PASTE'
alias localip='eval $CLAW_LOCAL_IP_CMD'
```

## Ubuntu System Configuration (ubuntu.sh)

Mirrors `macos.sh` for Linux:

1. **Default shell:** `chsh -s $(which zsh)`
2. **UFW firewall:** deny incoming, allow outgoing, allow SSH, enable
3. **SSH hardening:** PasswordAuthentication no, PermitRootLogin no
4. **GNOME tweaks** (if desktop detected): hidden files, dark theme, keyboard repeat speed
5. **Sysctl tuning:** `net.core.somaxconn=1024`, `fs.inotify.max_user_watches=524288`
6. **Timezone/locale** confirmation prompt

Kali/Parrot: skip UFW/SSH hardening (own security posture), skip GNOME if headless.

## tmux clipboard fix

`tmux/.tmux.conf` needs an OS-conditional copy-pipe:
```
if-shell "uname | grep -q Darwin" \
    "bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'pbcopy'" \
    "bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'xclip -selection clipboard'"
```

## File Changes

### New files
| File | Purpose |
|------|---------|
| `shell/platform.zsh` | OS shims (clipboard, IP, open, brew paths) |
| `scripts/install/ubuntu.sh` | Ubuntu/Kali/Parrot system config |
| `scripts/install/wizard.sh` | FZF component selection wizard |
| `scripts/install/packages/linux-repos.sh` | Add official apt repos (Docker, kubectl, gh, gcloud) |
| `scripts/install/linuxbrew.sh` | Linuxbrew installer |

### Modified files
| File | Changes |
|------|---------|
| `bootstrap.sh` | Add wizard phase, Linux flow, Linuxbrew install |
| `.zshrc` | Source platform.zsh first, use $HOMEBREW_PREFIX for plugin paths |
| `shell/aliases.zsh` | Replace ~12 macOS-only commands with $CLAW_* shims |
| `shell/exports.zsh` | Remove macOS PATH, defer to platform.zsh |
| `shell/welcome-tui.zsh` | Use shims in fallback header |
| `shell/obsidian.zsh` | Use $CLAW_OPEN_CMD instead of `open -a` |
| `tmux/.tmux.conf` | OS-conditional clipboard pipe |
| `scripts/install/packages/dev-tools.sh` | Expand apt section |
| `scripts/install/packages/devops-tools.sh` | Expand apt section, add repo setup |
| `scripts/install/master-setup.sh` | Add apt/brew hybrid logic |
| `scripts/install/*-toolchain.sh` (6 files) | Add apt + brew fallback paths |

### No changes needed
| File | Reason |
|------|--------|
| `shell/profiles/*.zsh` | Tool-level aliases, already portable |
| `shell/security.zsh` | Generic commands |
| `scripts/setup/symlinks.sh` | Stow works identically on Linux |
| `scripts/utils/logger.sh` | Pure bash |
| `git/.gitconfig` | Fully portable |
| `config/fastfetch/*` | Cross-platform format |
