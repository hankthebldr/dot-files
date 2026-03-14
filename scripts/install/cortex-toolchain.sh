#!/bin/bash

################################################################################
# Cortex Toolchain Installer (Palo Alto Networks Curriculum)
# Description: Automated installation of Cortex CLI, panos-cli, demisto-sdk, 
#              and pan-os-python for macOS.
################################################################################

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! command -v brew &> /dev/null; then
    log_error "Homebrew is required. Please install it first."
    exit 1
fi

CORTEX_WORKSPACE="$HOME/.cortex"
mkdir -p "$CORTEX_WORKSPACE"

# 1. Install pipx if missing (preferred for global python CLI tools on macOS)
if ! command -v pipx &> /dev/null; then
    log_info "Installing pipx for Python CLI tool management..."
    brew install pipx
    pipx ensurepath
fi

# 2. Install Python SDKs and CLI tools (demisto-sdk, panapi)
log_info "Installing Cortex XSOAR demisto-sdk..."
pipx install demisto-sdk || log_warning "Failed to install demisto-sdk via pipx"

log_info "Setting up local Python venv for pan-os-python..."
if [ ! -d "$CORTEX_WORKSPACE/venv" ]; then
    python3 -m venv "$CORTEX_WORKSPACE/venv"
    "$CORTEX_WORKSPACE/venv/bin/pip" install --upgrade pip
    "$CORTEX_WORKSPACE/venv/bin/pip" install pan-os-python panapi
    log_success "PAN-OS Python venv created at $CORTEX_WORKSPACE/venv"
else
    log_info "PAN-OS Python venv already exists."
fi

# 3. Install panos-cli (Go-based tool)
log_info "Installing panos-cli (Go-based)..."
if command -v go &> /dev/null; then
    # Use go install if go is available
    go install github.com/PaloAltoNetworks/panos-cli@latest || log_warning "Failed to install panos-cli"
    # Ensure Go bin is in path for this session if it isn't
    GOPATH_BIN="$(go env GOPATH)/bin"
    export PATH="$PATH:$GOPATH_BIN"
else
    log_warning "Go is not installed. Skipping panos-cli installation."
fi

# 4. Install Cortex CLI
log_info "Installing Cortex CLI..."
if ! command -v cortexcli &> /dev/null; then
    log_warning "Cortex CLI typically requires downloading the binary specifically for your tenant from the Prisma Cloud / Cortex console."
    log_warning "Please run the standard curl command provided in your Cortex Interface (e.g. Settings > Code Security > Integrations > Cortex CLI)."
    # Optional fallback to known public release pattern could be placed here:
    # curl -sL "https://pan.dev/cortex-cli/download" -o /usr/local/bin/cortexcli && chmod +x /usr/local/bin/cortexcli
else
    log_info "Cortex CLI is already installed: $(cortexcli -v 2>/dev/null || echo 'installed')"
fi

log_success "Cortex Toolchain Installation Complete!"
