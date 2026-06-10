#!/usr/bin/env bash
# scripts/backup/restore.sh

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"

restore_backup() {
    local backup_dir="$1"
    
    if [[ -z "$backup_dir" ]]; then
        log_error "Usage: ./restore.sh <path-to-backup-directory>"
        log_info "Available backups:"
        ls -dt "$HOME/.dotfiles-backups/"* 2>/dev/null | head -n 5
        return 1
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    log_warning "Restoring from $backup_dir..."
    log_warning "This will overwrite current configuration files in $HOME."
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Restore cancelled."
        return 0
    fi
    
    # Restore files
    cp -R "$backup_dir/." "$HOME/"
    
    log_success "Restore complete."
}

# Run if executing directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    restore_backup "$1"
fi
