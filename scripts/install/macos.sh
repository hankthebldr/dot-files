#!/usr/bin/env bash
# scripts/install/macos.sh
# macOS-specific configuration and defaults

source "$(dirname "${BASH_SOURCE[0]}")/../utils/logger.sh"

if [[ "$(uname)" != "Darwin" ]]; then
    log_info "Not macOS, skipping macos.sh"
    exit 0
fi

setup_macos() {
    log_info "Setting macOS defaults..."
    
    # Close System Preferences to prevent overriding
    osascript -e 'tell application "System Preferences" to quit'

    # Finder: show hidden files by default
    defaults write com.apple.finder AppleShowAllFiles -bool true

    # Finder: show all filename extensions
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true

    # Finder: show path bar
    defaults write com.apple.finder ShowPathbar -bool true

    # Finder: show status bar
    defaults write com.apple.finder ShowStatusBar -bool true

    # Avoid creating .DS_Store files on network or USB volumes
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Dock: set the icon size of Dock items to 36 pixels
    defaults write com.apple.dock tilesize -int 36

    # Dock: automatically hide and show the Dock
    defaults write com.apple.dock autohide -bool true
    
    # Keyboard: fast repeat rate
    defaults write NSGlobalDomain KeyRepeat -int 1
    defaults write NSGlobalDomain InitialKeyRepeat -int 10

    # Restart affected apps
    killall Finder
    killall Dock
    
    log_success "macOS defaults applied."
}

setup_macos
