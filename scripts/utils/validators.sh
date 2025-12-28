#!/usr/bin/env bash
# scripts/utils/validators.sh

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

check_internet() {
    log_info "Checking internet connection..."
    if ping -c 1 google.com &>/dev/null; then
        log_success "Internet is available."
        return 0
    else
        log_warning "No internet connection detected."
        return 1
    fi
}

check_command() {
    if command -v "$1" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

check_disk_space() {
    # Simple check if / has decent space (e.g., > 1GB)
    local min_space=1000000 # 1GB in KB
    local avail_space=$(df -k / | awk 'NR==2 {print $4}')
    
    if [[ "$avail_space" -lt "$min_space" ]]; then
        log_warning "Low disk space detected!"
        return 1
    fi
    return 0
}

check_sudo() {
    if sudo -n true 2>/dev/null; then
        return 0
    else
        log_info "Sudo access required. Please enter password if prompted."
        sudo -v
        return $?
    fi
}
