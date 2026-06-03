#!/usr/bin/env bash
# scripts/install/packages/modern-cli.sh
# Install modern CLI replacements and productivity tools

source "$(dirname "${BASH_SOURCE[0]}")/../../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../../utils/detect-os.sh"

TOOLS=(
    bat         # cat replacement
    ripgrep     # grep replacement
    fd          # find replacement (fd-find)
    eza         # ls replacement
    zoxide      # cd replacement
    fzf         # fuzzy finder
    htop        # top replacement
    btop        # better top
    tldr        # man replacement
    jq          # json processor
    yq          # yaml processor
    lazygit     # git tui
    neovim      # vim replacement
    starship    # prompt
    glow        # markdown reader
    navi        # interactive cheatsheet
    zellij      # modern terminal multiplexer (tmux alternative)
    nvtop       # GPU process viewer
)

install_modern_cli() {
    log_info "Installing modern CLI tools..."
    
    detect_os
    
    for tool in "${TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_success "$tool is already installed"
        else
            log_info "Installing $tool..."
            
            # Handle package name differences
            local pkg_name="$tool"
            if [[ "$tool" == "fd" && ("$PKG_MANAGER" == "apt" || "$PKG_MANAGER" == "dnf") ]]; then
                pkg_name="fd-find"
            fi
            
            # Many of these tools (lazygit, eza, zoxide, glow, navi, starship,
            # btop, tldr) aren't in Ubuntu < 24.04 / Debian < 13 stock repos.
            # Fail-soft so a missing package doesn't trip `set -e` upstream —
            # the brew_extras block in bootstrap.sh picks them up afterwards.
            if [[ "$PKG_MANAGER" == "brew" ]]; then
                brew install "$pkg_name" 2>/dev/null || log_warning "brew couldn't install $pkg_name"
            elif [[ "$PKG_MANAGER" == "apt" ]]; then
                sudo apt install -y "$pkg_name" 2>/dev/null || log_warning "$pkg_name not in apt repo (will retry via brew)"
            elif [[ "$PKG_MANAGER" == "dnf" ]]; then
                sudo dnf install -y "$pkg_name" 2>/dev/null || log_warning "$pkg_name not in dnf repo"
            fi
        fi
    done
}

# ── yazi (TUI file manager) ──────────────────────────────────────────────────
# Not in Ubuntu/Debian apt repos, and `cargo install yazi-fm` is slow + brittle
# (fails on some toolchains). Use brew where it's the primary manager, otherwise
# drop in the official prebuilt binary — no compiler required either way.
install_yazi() {
    if command -v yazi &>/dev/null; then
        log_success "yazi is already installed"
        return 0
    fi
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        brew install yazi 2>/dev/null && { log_success "yazi installed (brew)"; return 0; } \
            || log_warning "brew couldn't install yazi — falling back to prebuilt binary"
    fi

    local arch tgt tmp
    case "$(uname -m)" in
        x86_64|amd64)  arch="x86_64" ;;
        aarch64|arm64) arch="aarch64" ;;
        *) log_warning "yazi: no prebuilt binary for $(uname -m) — skipping"; return 0 ;;
    esac
    if [[ "$(uname -s)" == "Darwin" ]]; then tgt="${arch}-apple-darwin"; else tgt="${arch}-unknown-linux-gnu"; fi

    log_info "Installing yazi from prebuilt binary ($tgt)..."
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/sxyazi/yazi/releases/latest/download/yazi-${tgt}.zip" -o "$tmp/yazi.zip"; then
        if command -v unzip &>/dev/null; then unzip -q "$tmp/yazi.zip" -d "$tmp"; else python3 -m zipfile -e "$tmp/yazi.zip" "$tmp"; fi
        mkdir -p "$HOME/.local/bin"
        install -m755 "$(find "$tmp" -type f -name yazi | head -1)" "$HOME/.local/bin/yazi" 2>/dev/null \
            && install -m755 "$(find "$tmp" -type f -name ya | head -1)" "$HOME/.local/bin/ya" 2>/dev/null \
            && log_success "yazi installed to ~/.local/bin" \
            || log_warning "yazi: install step failed"
    else
        log_warning "yazi: prebuilt download failed (check network/GitHub)"
    fi
    rm -rf "$tmp"
}

install_modern_cli
install_yazi
