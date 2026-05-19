#!/usr/bin/env bash
# scripts/utils/system-update.sh
# Cumulative system update across every package manager available.
# Uses gum spinners when present, falls back to styled inline echo otherwise.

# Shared TUI helpers (theme + run_step + section + header/footer + pause)
source "$(dirname "${BASH_SOURCE[0]}")/tui-style.sh"

# ============================================
# CLI / ENV
# ============================================
INTERACTIVE=1
[[ "$1" == "--non-interactive" ]] && INTERACTIVE=0
[[ $INTERACTIVE -eq 1 ]] && clear

count_managers() {
    local count=0
    for cmd in brew apt-get dnf pacman snap flatpak npm yarn pnpm uv pipx pip3 gem rustup go; do
        command -v "$cmd" &>/dev/null && ((count++))
    done
    echo "$count"
}

# ============================================
# HEADER
# ============================================
total=$(count_managers)
tui_header "🔄 SYSTEM UPDATE" "Updating ${total} package managers across all ecosystems"

# ============================================
# 0. SYSTEM PACKAGES (Linux only — apt / dnf / pacman)
# ============================================
# Foundational layer — runs before brew so kernel/libc/etc come up first.
# `apt update` is verbose by default; pipe to /dev/null inside tui_run_step.
if command -v apt-get &>/dev/null; then
    tui_section "APT (system)"
    tui_run_step "Refreshing apt cache..."        "sudo apt-get update -qq"
    tui_run_step "Upgrading apt packages..."      "sudo apt-get upgrade -y"
    tui_run_step "Removing obsolete packages..."  "sudo apt-get autoremove -y"
    tui_run_step "Cleaning apt archives..."       "sudo apt-get autoclean -y"
elif command -v dnf &>/dev/null; then
    tui_section "DNF (system)"
    tui_run_step "Upgrading dnf packages..." "sudo dnf upgrade -y"
    tui_run_step "Removing orphans..."       "sudo dnf autoremove -y"
elif command -v pacman &>/dev/null; then
    tui_section "Pacman (system)"
    tui_run_step "Syncing pacman..." "sudo pacman -Syu --noconfirm"
fi

# Snap (Ubuntu, some Debian)
if command -v snap &>/dev/null; then
    tui_section "Snap"
    tui_run_step "Refreshing snap packages..." "sudo snap refresh"
fi

# Flatpak (Fedora, some Ubuntu)
if command -v flatpak &>/dev/null; then
    tui_section "Flatpak"
    tui_run_step "Updating flatpak packages..." "flatpak update -y --noninteractive"
fi

# Firmware updates (Linux laptops/desktops with fwupd)
if command -v fwupdmgr &>/dev/null; then
    tui_section "Firmware"
    tui_run_step "Refreshing fwupd metadata..." "fwupdmgr refresh --force 2>/dev/null || true"
    tui_run_step "Applying firmware updates..." "fwupdmgr update -y 2>/dev/null || true"
fi

# ============================================
# 1. HOMEBREW (macOS + Linuxbrew)
# ============================================
tui_section "Homebrew"
if command -v brew &>/dev/null; then
    tui_run_step "Updating Homebrew formulae index..." "brew update"
    tui_run_step "Upgrading outdated packages..." "brew upgrade"
    tui_run_step "Cleaning up old versions..." "brew cleanup --prune=7"
else
    tui_skip "brew"
fi

# ============================================
# 2. NODE.JS
# ============================================
tui_section "Node.js"
if command -v npm &>/dev/null; then
    tui_run_step "Updating global npm packages..." "npm update -g"
else
    tui_skip "npm"
fi
if command -v yarn &>/dev/null; then
    tui_run_step "Updating global yarn packages..." "yarn global upgrade"
else
    tui_skip "yarn"
fi
if command -v pnpm &>/dev/null; then
    tui_run_step "Updating global pnpm packages..." "pnpm update -g"
else
    tui_skip "pnpm"
fi

# ============================================
# 3. PYTHON
# ============================================
tui_section "Python"
if command -v uv &>/dev/null; then
    tui_run_step "Updating uv itself..." "uv self update"
    tui_run_step "Upgrading uv-managed tools..." "uv tool upgrade --all 2>/dev/null || true"
else
    tui_skip "uv"
fi
if command -v pipx &>/dev/null; then
    tui_run_step "Upgrading pipx tools..." "pipx upgrade-all"
else
    tui_skip "pipx"
fi
if command -v pip3 &>/dev/null; then
    tui_run_step "Upgrading pip itself..." "python3 -m pip install --upgrade pip"
else
    tui_skip "pip3"
fi

# ============================================
# 4. RUBY
# ============================================
tui_section "Ruby"
if command -v gem &>/dev/null; then
    tui_run_step "Updating RubyGems system..." "gem update --system"
else
    tui_skip "gem"
fi

# ============================================
# 5. RUST
# ============================================
tui_section "Rust"
if command -v rustup &>/dev/null; then
    tui_run_step "Updating Rust toolchains..." "rustup update"
else
    tui_skip "rustup"
fi

# ============================================
# 6. GO
# ============================================
tui_section "Go"
if command -v go &>/dev/null; then
    tui_run_step "Cleaning Go module cache..." "go clean -modcache"
    printf "  ${c_dim}○ Go binary managed by brew/system package manager${c_reset}\n"
else
    tui_skip "go"
fi

# ============================================
# 7. SHELL
# ============================================
tui_section "Shell"
if [[ -d "$HOME/.oh-my-zsh" ]] && command -v omz &>/dev/null; then
    tui_run_step "Updating Oh My Zsh..." "omz update --unattended 2>/dev/null"
else
    tui_skip "Oh My Zsh"
fi

# ============================================
# DONE
# ============================================
tui_footer "✓ Update complete"
tui_pause
