#!/usr/bin/env bash

################################################################################
# Research Toolchain Installer
# Description: HTTP, parsing, data wrangling, scraping, and content extraction.
# Cross-platform: macOS (brew) + Linux (apt + cargo + pipx fallbacks).
################################################################################

set -e
# NOT using set -u — pipx ensurepath may reference unset vars.

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── Research Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# ─────────────────────────────────────────────
# Native packages — same logical tools, different package names
# ─────────────────────────────────────────────
case "$PKG_MANAGER" in
    brew)
        brew_tools=(
            curl httpie jq csvkit ripgrep
            awk gnu-sed pup htmlq yt-dlp
            tldr fzf wget aria2 pandoc
        )
        for tool in "${brew_tools[@]}"; do
            if brew list "$tool" &>/dev/null; then
                log_info "$tool already installed."
            else
                log_info "Installing $tool..."
                brew install "$tool" || log_warning "Failed to install $tool"
            fi
        done
        ;;
    apt)
        # apt-native (matches Mac brew set where Linux has equivalents)
        apt_tools=(
            curl wget httpie jq ripgrep
            gawk sed pandoc aria2
            yt-dlp                # 22.04+; older releases need pipx fallback
            tldr                  # alternative to brew's tldr
            fzf
        )
        log_info "Refreshing apt cache..."
        sudo apt-get update -qq || log_warning "apt update failed (continuing)"
        for tool in "${apt_tools[@]}"; do
            if dpkg -s "$tool" &>/dev/null; then
                log_info "$tool already installed."
            else
                log_info "Installing $tool..."
                sudo apt-get install -y "$tool" 2>/dev/null \
                    || log_warning "$tool not in apt (will try fallback)"
            fi
        done

        # yt-dlp fallback for pre-22.04 Ubuntu
        if ! command -v yt-dlp &>/dev/null && command -v pipx &>/dev/null; then
            log_info "Installing yt-dlp via pipx (apt repo too old)..."
            pipx install yt-dlp || log_warning "yt-dlp pipx install failed"
        fi

        # csvkit — Python package, prefer pipx so it doesn't tangle with system python
        if ! command -v csvcut &>/dev/null; then
            log_info "Installing csvkit via pipx..."
            command -v pipx &>/dev/null && pipx install csvkit \
                || log_warning "csvkit needs pipx — install pipx first"
        fi

        # pup + htmlq — both Rust binaries, not in apt. Prefer Linuxbrew if available.
        for rust_tool in pup htmlq; do
            if ! command -v "$rust_tool" &>/dev/null; then
                if command -v brew &>/dev/null; then
                    log_info "Installing $rust_tool via Linuxbrew..."
                    brew install "$rust_tool" || log_warning "$rust_tool brew install failed"
                elif command -v cargo &>/dev/null; then
                    log_info "Installing $rust_tool via cargo..."
                    cargo install "$rust_tool" || log_warning "$rust_tool cargo install failed"
                else
                    log_warning "$rust_tool needs Linuxbrew or cargo (skipping)"
                fi
            fi
        done
        ;;
    *)
        log_warning "Unknown package manager ($PKG_MANAGER); skipping native packages"
        ;;
esac

# ─────────────────────────────────────────────
# pipx for Python research tools (cross-platform)
# ─────────────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    log_info "Installing pipx..."
    case "$PKG_MANAGER" in
        brew) brew install pipx ;;
        apt)  sudo apt-get install -y pipx || python3 -m pip install --user pipx ;;
        *)    python3 -m pip install --user pipx ;;
    esac
    command -v pipx &>/dev/null && pipx ensurepath
fi

if command -v pipx &>/dev/null; then
    pipx_tools=(
        scrapy
        wordfreq
        textract
        # polyglot dropped — requires libicu-dev + manual pip; rarely used
    )
    for tool in "${pipx_tools[@]}"; do
        log_info "Ensuring pipx install for $tool..."
        pipx install "$tool" 2>/dev/null || pipx upgrade "$tool" 2>/dev/null \
            || log_warning "$tool pipx install failed"
    done
fi

log_success "Research Toolchain install complete."
