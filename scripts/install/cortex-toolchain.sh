#!/usr/bin/env bash

################################################################################
# Cortex Toolchain Installer (Palo Alto Networks Curriculum)
# Description: demisto-sdk, pan-os-python, panapi, panos-cli, Cortex CLI hint.
# Cross-platform: macOS (brew) + Linux (apt + pipx + Go).
################################################################################

set -e
# Note: NOT using `set -u` — some upstream tool init uses unset vars.

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

log_info "── Cortex Toolchain install (OS: $OS_TYPE, pkg: $PKG_MANAGER) ──"

CORTEX_WORKSPACE="$HOME/.cortex"
mkdir -p "$CORTEX_WORKSPACE"

# ─────────────────────────────────────────────
# 1. pipx — preferred for global Python CLI tools on either platform
# ─────────────────────────────────────────────
if ! command -v pipx &>/dev/null; then
    log_info "Installing pipx..."
    case "$PKG_MANAGER" in
        brew) brew install pipx ;;
        apt)  sudo apt-get update -qq && sudo apt-get install -y pipx || python3 -m pip install --user pipx ;;
        dnf)  sudo dnf install -y pipx || python3 -m pip install --user pipx ;;
        *)    python3 -m pip install --user pipx || log_error "pipx install failed" ;;
    esac
    command -v pipx &>/dev/null && pipx ensurepath
fi

# Ensure python3 + venv are present on Linux (apt splits venv into its own pkg).
if [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt-get install -y python3 python3-venv python3-pip 2>/dev/null || true
fi

# ─────────────────────────────────────────────
# 2. demisto-sdk + pan-os-python venv
# ─────────────────────────────────────────────
log_info "Installing demisto-sdk via pipx..."
pipx install demisto-sdk 2>/dev/null || pipx upgrade demisto-sdk 2>/dev/null \
    || log_warning "demisto-sdk install/upgrade failed"

log_info "Setting up pan-os-python venv at $CORTEX_WORKSPACE/venv..."
if [[ ! -d "$CORTEX_WORKSPACE/venv" ]]; then
    python3 -m venv "$CORTEX_WORKSPACE/venv"
    "$CORTEX_WORKSPACE/venv/bin/pip" install --upgrade pip
    "$CORTEX_WORKSPACE/venv/bin/pip" install pan-os-python panapi \
        || log_warning "pan-os-python / panapi install failed"
    log_success "PAN-OS Python venv ready"
else
    log_info "PAN-OS Python venv already exists. (delete $CORTEX_WORKSPACE/venv to recreate)"
fi

# ─────────────────────────────────────────────
# 3. Go-based panos-cli
# ─────────────────────────────────────────────
# Ensure Go is available before attempting. On Linux, apt's golang is often
# acceptable for `go install`; for newer versions, prefer the binary tarball
# from go.dev (manual). On macOS, brew install go.
if ! command -v go &>/dev/null; then
    log_info "Go not found — attempting install..."
    case "$PKG_MANAGER" in
        brew) brew install go ;;
        apt)  sudo apt-get install -y golang ;;
        *)    log_warning "Cannot auto-install Go for $PKG_MANAGER — skipping panos-cli" ;;
    esac
fi

if command -v go &>/dev/null; then
    log_info "Installing panos-cli via go install..."
    go install github.com/PaloAltoNetworks/panos-cli@latest \
        || log_warning "panos-cli install failed"
    # Surface GOPATH/bin for this session so the next log line can find it.
    GOPATH_BIN="$(go env GOPATH)/bin"
    export PATH="$PATH:$GOPATH_BIN"
    if [[ -x "$GOPATH_BIN/panos-cli" ]]; then
        log_success "panos-cli installed at $GOPATH_BIN/panos-cli"
    fi
else
    log_warning "Go unavailable — skipping panos-cli"
fi

# ─────────────────────────────────────────────
# 4. Cortex CLI — tenant-specific download
# ─────────────────────────────────────────────
log_info "Cortex CLI..."
if command -v cortexcli &>/dev/null; then
    log_info "Cortex CLI already installed: $(cortexcli -v 2>/dev/null || echo 'present')"
else
    log_warning "Cortex CLI requires a tenant-specific binary."
    log_warning "Grab it from: Cortex console → Settings → Code Security → Integrations → Cortex CLI"
fi

log_success "Cortex Toolchain install complete."
