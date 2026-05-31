#!/usr/bin/env bash
# scripts/setup/symlinks.sh

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"
source "$(dirname "${BASH_SOURCE[0]}")/../utils/detect-os.sh"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$HOME"

# Cross-platform modules. `terminal/` ships macOS-only artifacts
# (mbp-m4.terminal, iterm2/, README.md) — stowing it on Linux drops a
# $HOME/README.md symlink that collides with cargo/npm/etc. init.
# `tools/` is currently empty — list explicitly to avoid stowing nothing
# and emitting a misleading warning. Re-add when populated.
MODULES=(
    shell
    git
    vim
    tmux
    config
)

# macOS-only modules — only stow on Darwin.
detect_os
if [[ "$OS_TYPE" == "macos" ]]; then
    MODULES+=(terminal)
fi

stow_modules() {
    log_info "Creating symlinks with GNU Stow..."
    
    # Check if stow is installed
    if ! command -v stow &>/dev/null; then
        log_error "GNU Stow is not installed. Please install it first."
        return 1
    fi
    
    for module in "${MODULES[@]}"; do
        if [[ -d "$DOTFILES_DIR/$module" ]]; then
            log_info "Linking $module..."
            # -R: Restow (delete and restow) - useful for updates
            # -v: Verbose
            stow -R -d "$DOTFILES_DIR" -t "$TARGET_DIR" "$module" 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                log_success "Linked $module"
            else
                log_warning "Failed to link $module (check for conflicts)"
            fi
        else
            log_warning "Module $module not found, skipping."
        fi
    done
}

# Run if executing directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    stow_modules
fi
