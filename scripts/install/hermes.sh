#!/usr/bin/env bash
# scripts/install/hermes.sh — install Ollama + pull Hermes model + register agent
#
# Idempotent: safe to re-run. Uses $CLAW_HERMES_MODEL (default: hermes3:8b).
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
HERMES_MODEL="${CLAW_HERMES_MODEL:-hermes3:8b}"

# ─────────────────────────────────────────────
# 1. Install Ollama if missing
# ─────────────────────────────────────────────
install_ollama() {
    if command -v ollama &>/dev/null; then
        log_success "ollama present: $(ollama --version 2>/dev/null | head -1)"
        return 0
    fi

    log_info "Installing Ollama..."
    case "$OS_TYPE" in
        macos)
            if command -v brew &>/dev/null; then
                brew install ollama || { log_error "brew install ollama failed"; return 1; }
            else
                log_error "Homebrew not installed; install brew first or run bootstrap.sh"
                return 1
            fi
            ;;
        ubuntu|debian|parrot|kali|linux-generic)
            # Official upstream installer — handles systemd unit on Linux.
            curl -fsSL https://ollama.com/install.sh | sh \
                || { log_error "Ollama install script failed"; return 1; }
            ;;
        *)
            log_error "Unsupported OS for ollama install: $OS_TYPE"
            return 1
            ;;
    esac
    log_success "ollama installed"
}

# ─────────────────────────────────────────────
# 2. Ensure ollama daemon is reachable
# ─────────────────────────────────────────────
ensure_daemon() {
    # Quick reachability probe (3s timeout)
    if curl -fsS --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
        log_success "ollama daemon reachable at :11434"
        return 0
    fi

    log_warning "ollama daemon not reachable at :11434"
    case "$OS_TYPE" in
        ubuntu|debian|parrot|kali|linux-generic)
            if command -v systemctl &>/dev/null; then
                log_info "starting ollama systemd service..."
                sudo systemctl enable --now ollama || \
                    log_warning "could not start systemd ollama unit; start manually: ollama serve"
            else
                log_info "no systemd; start manually: ollama serve &"
            fi
            ;;
        macos)
            log_info "start ollama with: ollama serve  (or: brew services start ollama)"
            ;;
    esac

    # Re-probe (best-effort; do not fail install)
    if curl -fsS --max-time 3 http://localhost:11434/api/tags &>/dev/null; then
        log_success "ollama daemon reachable after start"
    else
        log_warning "daemon still unreachable — model pull may fail; you can re-run later"
    fi
}

# ─────────────────────────────────────────────
# 3. Pull Hermes model (idempotent)
# ─────────────────────────────────────────────
pull_model() {
    local model="$HERMES_MODEL"

    if ollama list 2>/dev/null | awk 'NR>1 {print $1}' | grep -Fxq "$model"; then
        log_success "Hermes model already pulled: $model"
        return 0
    fi

    log_info "Pulling Hermes model: $model (this may take a while)"
    if ollama pull "$model"; then
        log_success "model ready: $model"
    else
        log_warning "pull failed for $model — set CLAW_HERMES_MODEL or retry later"
        return 1
    fi
}

# ─────────────────────────────────────────────
# 4. Register agent in claw registry
# ─────────────────────────────────────────────
register_agent() {
    mkdir -p "$CLAW_CONFIG_DIR"

    # Bootstrap agents.toml if missing (mirrors bin/claw ensure_agents_toml)
    if [[ ! -f "$AGENTS_TOML" ]]; then
        cat > "$AGENTS_TOML" <<'EOF'
# Open Claw agent registry — managed by bin/claw and scripts/install/*

[claude]
command = "claude"
profile = "claude"
description = "Anthropic Claude Code"
EOF
    fi

    if grep -q '^\[hermes\]$' "$AGENTS_TOML"; then
        log_success "[hermes] already registered in $AGENTS_TOML"
        return 0
    fi

    cat >> "$AGENTS_TOML" <<EOF

[hermes]
command = "hermes"
profile = "ai"
description = "Local Hermes (Nous Research) via Ollama — model: $HERMES_MODEL"
EOF
    log_success "registered [hermes] in $AGENTS_TOML"
}

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────
main() {
    log_info "── Hermes agent install (model: $HERMES_MODEL) ──"
    install_ollama
    ensure_daemon
    pull_model || true   # non-fatal — install can still register the agent
    register_agent
    log_success "Hermes setup complete. Try: claw hermes \"hello\""
}

main "$@"
