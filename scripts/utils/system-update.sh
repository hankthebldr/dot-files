#!/usr/bin/env bash
# scripts/utils/system-update.sh
# Cumulative system update across every package manager available.
# Streams every step live (stream + collapse-on-success) via claw-progress.sh.

# Theme engine (CLAW_RGB_*) + streaming progress chrome (single render path).
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh" 2>/dev/null || true
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh"

# ============================================
# CLI / ENV
# ============================================
INTERACTIVE=1
[[ "${1:-}" == "--non-interactive" ]] && INTERACTIVE=0
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
claw_ui_header "🔄 SYSTEM UPDATE" "Updating ${total} package managers across all ecosystems"

# ============================================
# 0. SYSTEM PACKAGES (Linux only — apt / dnf / pacman)
# ============================================
# Foundational layer — runs before brew so kernel/libc/etc come up first.
# `apt update` is verbose by default; claw_step streams + collapses it.
if command -v apt-get &>/dev/null; then
    claw_ui_section "APT (system)"
    claw_step "Refreshing apt cache..." -- bash -c "sudo apt-get update -qq"
    claw_step "Upgrading apt packages..." -- bash -c "sudo apt-get upgrade -y"
    claw_step "Removing obsolete packages..." -- bash -c "sudo apt-get autoremove -y"
    claw_step "Cleaning apt archives..." -- bash -c "sudo apt-get autoclean -y"
elif command -v dnf &>/dev/null; then
    claw_ui_section "DNF (system)"
    claw_step "Upgrading dnf packages..." -- bash -c "sudo dnf upgrade -y"
    claw_step "Removing orphans..." -- bash -c "sudo dnf autoremove -y"
elif command -v pacman &>/dev/null; then
    claw_ui_section "Pacman (system)"
    claw_step "Syncing pacman..." -- bash -c "sudo pacman -Syu --noconfirm"
fi

# Snap (Ubuntu, some Debian)
if command -v snap &>/dev/null; then
    claw_ui_section "Snap"
    claw_step "Refreshing snap packages..." -- bash -c "sudo snap refresh"
fi

# Flatpak (Fedora, some Ubuntu)
if command -v flatpak &>/dev/null; then
    claw_ui_section "Flatpak"
    claw_step "Updating flatpak packages..." -- bash -c "flatpak update -y --noninteractive"
fi

# Firmware updates (Linux laptops/desktops with fwupd)
if command -v fwupdmgr &>/dev/null; then
    claw_ui_section "Firmware"
    claw_step "Refreshing fwupd metadata..." -- bash -c "fwupdmgr refresh --force 2>/dev/null || true"
    claw_step "Applying firmware updates..." -- bash -c "fwupdmgr update -y 2>/dev/null || true"
fi

# ============================================
# 1. HOMEBREW (macOS + Linuxbrew)
# ============================================
claw_ui_section "Homebrew"
if command -v brew &>/dev/null; then
    claw_step "Updating Homebrew formulae index..." -- bash -c "brew update"
    claw_step "Upgrading outdated packages..." -- bash -c "brew upgrade"
    claw_step "Cleaning up old versions..." -- bash -c "brew cleanup --prune=7"
else
    claw_ui_skip "brew"
fi

# ============================================
# 2. NODE.JS
# ============================================
claw_ui_section "Node.js"
if command -v npm &>/dev/null; then
    claw_step "Updating global npm packages..." -- bash -c "npm update -g"
else
    claw_ui_skip "npm"
fi
if command -v yarn &>/dev/null; then
    claw_step "Updating global yarn packages..." -- bash -c "yarn global upgrade"
else
    claw_ui_skip "yarn"
fi
if command -v pnpm &>/dev/null; then
    claw_step "Updating global pnpm packages..." -- bash -c "pnpm update -g"
else
    claw_ui_skip "pnpm"
fi

# ============================================
# 3. PYTHON
# ============================================
claw_ui_section "Python"
if command -v uv &>/dev/null; then
    claw_step "Updating uv itself..." -- bash -c "uv self update"
    claw_step "Upgrading uv-managed tools..." -- bash -c "uv tool upgrade --all 2>/dev/null || true"
else
    claw_ui_skip "uv"
fi
if command -v pipx &>/dev/null; then
    claw_step "Upgrading pipx tools..." -- bash -c "pipx upgrade-all"
else
    claw_ui_skip "pipx"
fi
if command -v pip3 &>/dev/null; then
    claw_step "Upgrading pip itself..." -- bash -c "python3 -m pip install --upgrade pip"
else
    claw_ui_skip "pip3"
fi

# ============================================
# 4. RUBY
# ============================================
claw_ui_section "Ruby"
if command -v gem &>/dev/null; then
    claw_step "Updating RubyGems system..." -- bash -c "gem update --system"
else
    claw_ui_skip "gem"
fi

# ============================================
# 5. RUST
# ============================================
claw_ui_section "Rust"
if command -v rustup &>/dev/null; then
    claw_step "Updating Rust toolchains..." -- bash -c "rustup update"
else
    claw_ui_skip "rustup"
fi

# ============================================
# 6. GO
# ============================================
claw_ui_section "Go"
if command -v go &>/dev/null; then
    claw_step "Cleaning Go module cache..." -- bash -c "go clean -modcache"
    printf "  %s○ Go binary managed by brew/system package manager%s\n" "$(_c muted)" "$(_creset)"
else
    claw_ui_skip "go"
fi

# ============================================
# 7. SHELL
# ============================================
claw_ui_section "Shell"
if [[ -d "$HOME/.oh-my-zsh" ]] && command -v omz &>/dev/null; then
    claw_step "Updating Oh My Zsh..." -- bash -c "omz update --unattended 2>/dev/null"
else
    claw_ui_skip "Oh My Zsh"
fi

# ============================================
# DONE
# ============================================
claw_ui_footer "Update complete"
claw_ui_pause
