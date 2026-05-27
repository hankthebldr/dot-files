#!/usr/bin/env bash
# scripts/install/openrouter.sh — install aichat + symlink config + register agent
#
# Idempotent: safe to re-run. aichat is open-source MIT, multi-provider Rust CLI.
# Linux-first (BD790i target); macOS parallel path.
#
# Spec: docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

CLAW_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claw"
AGENTS_TOML="$CLAW_CONFIG_DIR/agents.toml"
AICHAT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/aichat"
AICHAT_CONFIG="$AICHAT_CONFIG_DIR/config.yaml"
AICHAT_TEMPLATE="$DOTFILES_DIR/config/.config/aichat/config.yaml.example"

# ─────────────────────────────────────────────
# 1. Install aichat
# ─────────────────────────────────────────────
install_aichat() {
    if command -v aichat &>/dev/null; then
        log_success "aichat present: $(aichat --version 2>/dev/null)"
        return 0
    fi

    log_info "Installing aichat..."
    case "$OS_TYPE" in
        macos)
            if command -v brew &>/dev/null; then
                brew install aichat || { log_error "brew install aichat failed"; return 1; }
            else
                log_error "Homebrew not installed; install brew first or run bootstrap.sh"
                return 1
            fi
            ;;
        ubuntu|debian|parrot|kali|linux-generic)
            install_aichat_linux_release || install_aichat_cargo_fallback
            ;;
        *)
            log_error "Unsupported OS for aichat install: $OS_TYPE"
            return 1
            ;;
    esac
    command -v aichat &>/dev/null && log_success "aichat installed: $(aichat --version 2>/dev/null)"
}

install_aichat_linux_release() {
    local arch ac_target latest tmp
    arch=$(uname -m)
    case "$arch" in
        x86_64)  ac_target="x86_64-unknown-linux-musl" ;;
        aarch64|arm64) ac_target="aarch64-unknown-linux-musl" ;;
        *) log_warning "unknown arch $arch — falling back to cargo install"; return 1 ;;
    esac

    latest=$(curl -fsSL https://api.github.com/repos/sigoden/aichat/releases/latest \
        | grep -m1 '"tag_name"' | cut -d'"' -f4) || return 1
    [[ -z "$latest" ]] && return 1

    log_info "Fetching aichat $latest ($ac_target)..."
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' RETURN

    if ! curl -fsSL \
        "https://github.com/sigoden/aichat/releases/download/${latest}/aichat-${latest}-${ac_target}.tar.gz" \
        -o "$tmp/aichat.tgz"; then
        log_warning "release download failed"; return 1
    fi

    tar -xzf "$tmp/aichat.tgz" -C "$tmp" aichat 2>/dev/null \
        || tar -xzf "$tmp/aichat.tgz" -C "$tmp"

    local bin="$tmp/aichat"
    [[ ! -x "$bin" ]] && bin=$(find "$tmp" -name aichat -type f -perm -u+x | head -1)
    [[ -z "$bin" || ! -x "$bin" ]] && { log_warning "aichat binary not found in archive"; return 1; }

    # Prefer ~/.local/bin (no sudo); fall back to /usr/local/bin
    if [[ -d "$HOME/.local/bin" ]] || mkdir -p "$HOME/.local/bin" 2>/dev/null; then
        install -m 0755 "$bin" "$HOME/.local/bin/aichat"
        log_success "installed to $HOME/.local/bin/aichat"
    else
        sudo install -m 0755 "$bin" /usr/local/bin/aichat
        log_success "installed to /usr/local/bin/aichat"
    fi
}

install_aichat_cargo_fallback() {
    if ! command -v cargo &>/dev/null; then
        log_error "cargo not found; install rustup first or pre-install aichat manually"
        return 1
    fi
    log_info "Falling back to: cargo install aichat (slow, builds from source)"
    cargo install aichat
}

# ─────────────────────────────────────────────
# 2. Symlink aichat config from template (never overwrite user config)
# ─────────────────────────────────────────────
link_config() {
    mkdir -p "$AICHAT_CONFIG_DIR"

    if [[ -e "$AICHAT_CONFIG" || -L "$AICHAT_CONFIG" ]]; then
        log_success "aichat config already in place: $AICHAT_CONFIG"
        return 0
    fi

    if [[ ! -f "$AICHAT_TEMPLATE" ]]; then
        log_warning "template not found: $AICHAT_TEMPLATE"
        return 1
    fi

    ln -s "$AICHAT_TEMPLATE" "$AICHAT_CONFIG"
    log_success "linked aichat config: $AICHAT_CONFIG → template"
    log_info "set OPENROUTER_API_KEY in ~/.dotfiles/.env (or export in shell)"
}

# ─────────────────────────────────────────────
# 3. Register agent in claw registry
# ─────────────────────────────────────────────
register_agent() {
    mkdir -p "$CLAW_CONFIG_DIR"

    if [[ ! -f "$AGENTS_TOML" ]]; then
        cat > "$AGENTS_TOML" <<'EOF'
# Open Claw agent registry — managed by bin/claw and scripts/install/*

[claude]
command = "claude"
profile = "claude"
description = "Anthropic Claude Code"
EOF
    fi

    if grep -q '^\[openrouter\]$' "$AGENTS_TOML"; then
        log_success "[openrouter] already registered in $AGENTS_TOML"
        return 0
    fi

    cat >> "$AGENTS_TOML" <<'EOF'

[openrouter]
command = "openrouter"
profile = "ai"
description = "OpenRouter via aichat (default: anthropic/claude-sonnet-4.6)"
EOF
    log_success "registered [openrouter] in $AGENTS_TOML"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
    log_info "── OpenRouter (aichat) install ──"
    install_aichat || { log_error "aichat install failed; aborting"; return 1; }
    link_config
    register_agent
    log_success "OpenRouter setup complete. Try: claw openrouter \"hello\""
}

main "$@"
