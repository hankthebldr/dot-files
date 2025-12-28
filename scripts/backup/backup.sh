#!/usr/bin/env bash
# scripts/backup/backup.sh

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"

BACKUP_ROOT="$HOME/.dotfiles-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/backup-$TIMESTAMP"

# Files to backup if they exist in HOME
FILES_TO_BACKUP=(
    .zshrc .bashrc .zprofile .zshenv
    .gitconfig .gitignore_global
    .vimrc .vim
    .tmux.conf
    .config/nvim
    .config/starship.toml
    .config/alacritty
    .config/kitty
)

backup_configs() {
    log_info "Starting backup process..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
    fi
    
    local count=0
    
    for file in "${FILES_TO_BACKUP[@]}"; do
        if [[ -e "$HOME/$file" && ! -L "$HOME/$file" ]]; then
            # If it's a real file/dir (not a symlink), backup it
            # Preserve directory structure
            local dir=$(dirname "$file")
            if [[ "$dir" != "." ]]; then
                mkdir -p "$BACKUP_DIR/$dir"
            fi
            
            cp -R "$HOME/$file" "$BACKUP_DIR/$file"
            log_success "Backed up $file"
            ((count++))
        fi
    done
    
    # Create manifest
    echo "Backup created at $TIMESTAMP" > "$BACKUP_DIR/manifest.txt"
    
    if [[ $count -gt 0 ]]; then
        log_success "Backup complete. Saved to $BACKUP_DIR"
    else
        log_info "No checking existing configs found to backup (or they are already symlinks)."
        # Remove empty backup dir to keep things clean
        rm -rf "$BACKUP_DIR"
    fi
}

# Run if executing directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    backup_configs
fi
