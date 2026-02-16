#!/usr/bin/env bash
# bootstrap.sh
# Master setup script for dot-files

set -e

# 1. Source Utilities
source "scripts/utils/logger.sh"
source "scripts/utils/detect-os.sh"
source "scripts/utils/validators.sh"

# 2. Default Configuration
INSTALL_MODE="full"
BACKUP_ENABLED=true
DRY_RUN=false
SECURITY_MODE=false

# 3. Parse Arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --minimal) INSTALL_MODE="minimal" ;;
        --no-backup) BACKUP_ENABLED=false ;;
        --dry-run) DRY_RUN=true ;;
        --security) SECURITY_MODE=true ;;
        --help)
            echo "Usage: ./bootstrap.sh [options]"
            echo "Options:"
            echo "  --minimal      Install only essentials"
            echo "  --no-backup    Skip backup"
            echo "  --dry-run      Show what would happen"
            echo "  --security     Install security/pentest tools"
            exit 0
            ;;
        *) log_error "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# 4. Main Workflow
main() {
    log_info "Starting Dot-Files Setup ($OS_TYPE)..."
    
    # Pre-flight
    check_internet || log_warning "Internet check failed. Some installs may fail."
    check_disk_space || exit 1
    detect_os
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN MODE: No changes will be made."
        exit 0
    fi

    # Backup
    if [[ "$BACKUP_ENABLED" == "true" ]]; then
        source "scripts/backup/backup.sh"
        backup_configs
    fi

    # Package Installation
    log_info "Installing packages..."
    
    # 1. Package Manager (Brew)
    source "scripts/install/brew.sh"

    # 2. Common & Essentials
    source "scripts/install/packages/common.sh"
    
    # 3. Modern CLI & Productivity
    source "scripts/install/packages/modern-cli.sh"
    
    if [[ "$INSTALL_MODE" == "full" ]]; then
        # 4. Dev Tools
        [[ -f "scripts/install/packages/dev-tools.sh" ]] && source "scripts/install/packages/dev-tools.sh"
        
        # 5. DevOps Tools
        [[ -f "scripts/install/packages/devops-tools.sh" ]] && source "scripts/install/packages/devops-tools.sh"
    fi

    # 6. macOS Defaults
    if [[ "$OS_TYPE" == "macos" ]]; then
        source "scripts/install/macos.sh"
    fi

    if [[ "$SECURITY_MODE" == "true" || "$OS_TYPE" == "parrot" || "$OS_TYPE" == "kali" ]]; then
        log_info "Security/Pentest mode active."
        source "scripts/install/packages/security.sh"
    fi

    # Symlinks
    source "scripts/setup/symlinks.sh"
    stow_modules

    # Post-Install
    log_success "Setup Complete!"
    echo ""
    log_info "Next Steps:"
    echo "  1. Restart your terminal: exec zsh"
    echo "  2. Install fonts manually if icons are missing."
    if [[ "$SECURITY_MODE" == "true" ]]; then
        echo "  3. Verify security tools with: nmap --version"
    fi
}

main
