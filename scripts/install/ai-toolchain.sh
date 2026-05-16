#!/usr/bin/env bash

################################################################################
# AI / LLM Toolchain Installer
# Installs GenAI models, vector dbs, inference CLIs and orchestrators.
# Cross-platform: macOS (brew) + Linux (apt + curl-based fallbacks).
# Spec: docs/superpowers/specs/2026-05-06-hermes-openrouter-design.md
################################################################################

set -e
# Note: NOT using `set -u` here — some upstream tool init scripts use unset vars.

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── AI Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

# ─────────────────────────────────────────────
# Native packages
# ─────────────────────────────────────────────
case "$PKG_MANAGER" in
    brew)
        brew_tools=(
            "llama.cpp"
            "whisper-cpp"
            "ffmpeg"
            "qdrant-cli"
            "ollama"
            "cliclick"
            "jq"
            "yq"
            "dasel"
            "aichat"
        )
        for tool in "${brew_tools[@]}"; do
            if brew list "$tool" &>/dev/null; then
                log_info "$tool already installed."
            else
                log_info "Installing $tool..."
                brew install "$tool" || log_error "Failed to install $tool"
            fi
        done
        ;;
    apt)
        # Linux: ollama + aichat handled by their dedicated install scripts below.
        # Here we just install what apt has natively.
        apt_tools=(
            ffmpeg
            jq
            curl
            build-essential
        )
        log_info "Refreshing apt cache..."
        sudo apt-get update -qq || log_warning "apt update failed (continuing)"
        for tool in "${apt_tools[@]}"; do
            if dpkg -s "$tool" &>/dev/null; then
                log_info "$tool already installed."
            else
                log_info "Installing $tool..."
                sudo apt-get install -y "$tool" || log_error "Failed to install $tool"
            fi
        done

        # yq via snap or direct binary (apt's yq is a different tool on some distros)
        if ! command -v yq &>/dev/null; then
            log_info "Installing yq from GitHub releases..."
            local_arch=$(uname -m); yq_arch="amd64"
            [[ "$local_arch" == "aarch64" || "$local_arch" == "arm64" ]] && yq_arch="arm64"
            sudo curl -fsSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch}" \
                -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq \
                || log_warning "yq install failed"
        fi

        # whisper.cpp / llama.cpp / qdrant-cli aren't in apt — recommend manual
        # build from source if needed; out of scope for the default install.
        log_info "Skipped: llama.cpp, whisper-cpp, qdrant-cli (build from source if needed)"
        ;;
    *)
        log_warning "Unknown package manager ($PKG_MANAGER); skipping native packages"
        ;;
esac

# ─────────────────────────────────────────────
# pipx (cross-platform Python tooling)
# ─────────────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    log_info "Installing pipx..."
    case "$PKG_MANAGER" in
        brew) brew install pipx ;;
        apt)  sudo apt-get install -y pipx || python3 -m pip install --user pipx ;;
        *)    python3 -m pip install --user pipx || log_error "pipx install failed" ;;
    esac
    command -v pipx &>/dev/null && pipx ensurepath
fi

if command -v pipx &>/dev/null; then
    pipx_tools=(
        "openai"
        "anthropic"
        "cohere"
        "huggingface-hub"
        "langchain-cli"
        "dvc"
        "mlflow"
        "aider-chat"
        "google-adk"
    )
    for tool in "${pipx_tools[@]}"; do
        log_info "Ensuring pipx install for $tool..."
        pipx install "$tool" 2>/dev/null || pipx upgrade "$tool" 2>/dev/null \
            || log_warning "Failed to install/upgrade $tool via pipx"
    done
fi

# ─────────────────────────────────────────────
# Node-based AI tools (Claude Agent SDK)
# ─────────────────────────────────────────────
if command -v npm &>/dev/null; then
    log_info "Installing Node AI Tools..."
    for pkg in "@anthropic-ai/claude-agent-sdk"; do
        if npm list -g "$pkg" &>/dev/null 2>&1; then
            log_info "$pkg already installed globally."
        else
            log_info "Installing $pkg globally..."
            npm install -g "$pkg" || log_error "Failed to install $pkg"
        fi
    done
else
    log_warning "npm not found — skipping Node AI tools (install Node.js first)"
fi

# ─────────────────────────────────────────────
# Hermes agent (local Ollama-backed)
# ─────────────────────────────────────────────
log_info "→ Hermes agent"
bash "$DOTFILES_DIR/scripts/install/hermes.sh" || log_warning "hermes install reported errors"

# ─────────────────────────────────────────────
# OpenRouter (aichat-backed)
# ─────────────────────────────────────────────
log_info "→ OpenRouter (aichat)"
bash "$DOTFILES_DIR/scripts/install/openrouter.sh" || log_warning "openrouter install reported errors"

log_success "AI Toolchain installed."
