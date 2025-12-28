#!/usr/bin/env bash
# scripts/utils/detect-os.sh

detect_os() {
    OS_TYPE="unknown"
    PKG_MANAGER="unknown"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        PKG_MANAGER="brew"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|parrot|kali)
                OS_TYPE="$ID"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos)
                OS_TYPE="$ID"
                PKG_MANAGER="dnf"
                ;;
            arch|manjaro)
                OS_TYPE="$ID"
                PKG_MANAGER="pacman"
                ;;
            *)
                OS_TYPE="linux-generic"
                ;;
        esac
    fi
    
    export OS_TYPE PKG_MANAGER
}
