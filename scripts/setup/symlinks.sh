#!/usr/bin/env bash
# scripts/setup/symlinks.sh

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="$HOME"

# Modules to stow by default
MODULES=(
    shell
    git
    vim
    tmux
    terminal
    tools
)

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
