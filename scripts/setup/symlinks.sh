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
    terminal
)

# terminal/ links only its .config/ subtree (ghostty/kitty/alacritty/wezterm/
# starship) on every platform — the macOS .terminal/iterm2 imports are excluded
# via terminal/.stow-local-ignore. detect_os kept for downstream use.
detect_os

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
            # set -e from bootstrap.sh kills the script the moment stow exits
            # non-zero, so `if [[ $? -eq 0 ]]` was dead code. Capture the exit
            # inline via `|| rc=$?` so we can actually branch on it.
            #
            # Common failure: existing $HOME/.zshrc etc. were created manually
            # (or by a prior install) and stow refuses to touch them ("not
            # owned by stow"). Those symlinks are usually already correct —
            # verify and treat as success, only warn on real conflicts.
            local stow_rc=0
            stow -R -d "$DOTFILES_DIR" -t "$TARGET_DIR" "$module" 2>/dev/null || stow_rc=$?

            if [[ $stow_rc -eq 0 ]]; then
                log_success "Linked $module"
            elif _module_already_linked "$module"; then
                log_success "$module already correctly linked (stow skipped — pre-existing symlinks)"
            else
                log_warning "Failed to link $module (check for conflicts: stow -nv -d $DOTFILES_DIR -t $TARGET_DIR $module)"
            fi
        else
            log_warning "Module $module not found, skipping."
        fi
    done
}

# Returns 0 if every top-level entry in $DOTFILES_DIR/$module has a
# corresponding correct symlink in $TARGET_DIR. Used to distinguish "stow
# refused because the work is already done" from "stow refused for a real
# reason." Only checks one level — matches stow's default folding behavior.
_module_already_linked() {
    local module="$1"
    local src_dir="$DOTFILES_DIR/$module"
    local src_file rel target_path expected_resolved actual_resolved
    local found_any=
    # Exclude stow plumbing only, NOT .gitconfig — the original `! -name '.git*'`
    # glob also swallowed .gitconfig (the entire payload of the git/ module),
    # so a real stow conflict on git/ silently reported "already linked."
    while IFS= read -r src_file; do
        rel="${src_file#$src_dir/}"
        target_path="$TARGET_DIR/$rel"
        [[ -L "$target_path" ]] || return 1
        expected_resolved="$(readlink -f "$src_file" 2>/dev/null)"
        actual_resolved="$(readlink -f "$target_path" 2>/dev/null)"
        [[ "$expected_resolved" == "$actual_resolved" ]] || return 1
        found_any=1
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 \
        \! -name '.git' \! -name '.gitignore' \! -name '.stow-local-ignore')
    # Empty walk == unverifiable, not verified-good. Force the caller to
    # treat the original stow failure as real (warn the user).
    [[ -n "$found_any" ]] || return 1
    return 0
}

# Run if executing directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    stow_modules
fi
