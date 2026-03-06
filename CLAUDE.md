# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Modular macOS CLI configuration system ("dot-files") that bootstraps a complete developer environment from scratch. Supports multiple workflow profiles (Cloud, Security, DevOps, AI, Research, Cortex) with modern CLI tool replacements and an interactive FZF-based welcome TUI.

Dotfiles are symlinked from `~/.dotfiles` into the home directory. The expected clone path is `~/.dotfiles`.

## Setup & Installation

```bash
./bootstrap.sh              # Full installation
./bootstrap.sh --minimal    # Essentials only
./bootstrap.sh --security   # Include pentesting tools
./bootstrap.sh --dry-run    # Preview without changes
```

`master-setup.sh` is a separate orchestrator with category arguments:
```bash
bash scripts/install/master-setup.sh all      # Everything
bash scripts/install/master-setup.sh base     # Shell + dev + network + extras
bash scripts/install/master-setup.sh domains  # All domain toolchain scripts
bash scripts/install/master-setup.sh shell    # Shell tools only
```

## Architecture

### Shell Configuration Loading Order (.zshrc)

1. `shell/exports.zsh` - Environment variables
2. `shell/aliases.zsh` - All aliases and shell functions (~780 lines)
3. `shell/security.zsh` - Safe file ops, network recon, scanning aliases
4. `shell/obsidian.zsh` - Obsidian vault integration (`on`, `os`, `ov`)
5. Tool init: zoxide, starship, fzf, atuin, zsh-syntax-highlighting, zsh-autosuggestions
6. `~/.zshrc.local` - User-local overrides (not tracked)

**Note:** `aliases.zsh` is sourced twice in the current `.zshrc` (line 8 and 9) - this is a bug.

### Profile System

`shell/profiles/` contains context-specific environments loaded via the welcome TUI:
- `default.zsh`, `cloud.zsh`, `security.zsh`, `devops.zsh`, `ai.zsh`, `research.zsh`, `cortex.zsh`

Each profile sets `CLAW_PROFILE_THEME` and provides domain-specific aliases/functions.

### Installation Scripts

Two entry points exist:
- **`bootstrap.sh`** - Sources `scripts/utils/{logger,detect-os,validators}.sh`, then runs package installers from `scripts/install/packages/` and creates symlinks via `scripts/setup/symlinks.sh`
- **`scripts/install/master-setup.sh`** - Standalone orchestrator that calls domain toolchain scripts (`*-toolchain.sh`) and has its own brew/logging setup

Domain toolchain scripts (`scripts/install/`): `ai-toolchain.sh`, `cloud-toolchain.sh`, `devops-toolchain.sh`, `security-toolchain.sh`, `research-toolchain.sh`, `cortex-toolchain.sh`

### Interactive TUI

- `shell/welcome-tui.zsh` - FZF-based login dashboard showing system info and 15+ workflow options (profile loading, tool launching, system management)
- `scripts/utils/toolkit.sh` - "Open Claw Toolkit" FZF menu for Git, Docker, K8s, Cloud, Security, and System workflows

## Conventions

- **Modern CLI tools replace legacy ones:** `eza` (ls), `bat` (cat), `ripgrep` (grep), `fd` (find), `zoxide` (cd), `btop` (top), `delta` (diff)
- **Color theme:** GitHub macOS Dark throughout (TUI menus, tmux, toolkit)
- **Logging pattern:** Color-coded `log_info`, `log_success`, `log_warning`, `log_error` functions (blue/green/yellow/red)
- **Idempotent installs:** All scripts check `command -v` before installing
- **Shell scripts use `set -e`** (exit on error); master-setup also uses `set -u` (exit on undefined)
- **Safety aliases:** Destructive ops always prompt (`rm -i`, `mv -i`, `cp -i`)
- **FZF integration:** Used for fuzzy selection in git branches, k8s contexts, AWS profiles, process killing

## Key File Paths

| File | Purpose |
|------|---------|
| `.zshrc` | Main shell config, sources all modules |
| `shell/aliases.zsh` | Core aliases and functions (largest file) |
| `shell/profiles/*.zsh` | Workflow-specific environments |
| `shell/welcome-tui.zsh` | Login dashboard |
| `scripts/utils/toolkit.sh` | Interactive workflow launcher |
| `scripts/utils/logger.sh` | Shared logging utilities |
| `scripts/utils/detect-os.sh` | OS detection (macOS, Ubuntu, Kali, Parrot, etc.) |
| `scripts/setup/symlinks.sh` | Dotfile symlinking |
| `tmux/.tmux.conf` | Tmux config (GitHub dark theme, mouse, clipboard) |
| `git/.gitconfig` | Git config with delta integration |
| `bootstrap.sh` | Primary setup entry point |
| `scripts/install/master-setup.sh` | Alternative setup orchestrator |

## Shell Script Guidelines

- Use `#!/usr/bin/env bash` for portability (bootstrap.sh pattern) or `#!/bin/bash` (master-setup.sh pattern)
- Guard tool initialization with `command -v tool &> /dev/null` checks
- Support both Apple Silicon (`/opt/homebrew`) and Intel (`/usr/local`) Homebrew paths
- Cross-platform awareness: OS detection supports macOS, Ubuntu, Debian, Fedora, Arch, Kali, Parrot
