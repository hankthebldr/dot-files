#!/bin/bash

################################################################################
# macOS Security Hardening Script
# Description: Applies security configurations to macOS
# Usage: bash security-hardening.sh
# WARNING: Review settings before running - some may affect usability
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
log_info "macOS Security Hardening Script"
log_warning "This script will modify system security settings"
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# ============================================================================
# FIREWALL SETTINGS
# ============================================================================

log_info "Configuring firewall..."

# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
log_success "Firewall enabled"

# Enable stealth mode (don't respond to ICMP ping requests)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
log_success "Stealth mode enabled"

# Prevent built-in software and signed apps from being auto-allowed
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp off
log_success "Automatic allow for signed apps disabled"

# Enable logging
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setloggingmode on
log_success "Firewall logging enabled"

# ============================================================================
# SYSTEM SECURITY
# ============================================================================

log_info "Configuring system security..."

# Require password immediately after sleep/screensaver
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
log_success "Require password immediately after sleep"

# Disable automatic login
sudo defaults delete /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true
log_success "Automatic login disabled"

# Enable secure keyboard entry in Terminal
defaults write com.apple.terminal SecureKeyboardEntry -bool true
log_success "Secure keyboard entry enabled in Terminal"

# Disable remote apple events
sudo systemsetup -setremoteappleevents off
log_success "Remote apple events disabled"

# Disable remote login (SSH)
# Uncomment if you don't need SSH access
# sudo systemsetup -setremotelogin off
# log_success "Remote login (SSH) disabled"

# Disable wake on network access
sudo systemsetup -setwakeonnetworkaccess off 2>/dev/null || true
log_success "Wake on network access disabled"

# Disable printer sharing
cupsctl --no-share-printers 2>/dev/null || true
log_success "Printer sharing disabled"

# ============================================================================
# PRIVACY SETTINGS
# ============================================================================

log_info "Configuring privacy settings..."

# Disable Spotlight indexing for volumes (optional - adjust as needed)
# sudo mdutil -i off -d /Volumes/* 2>/dev/null || true

# Disable Spotlight suggestions in Look Up
defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true
log_success "Spotlight suggestions disabled"

# Disable Siri
defaults write com.apple.assistant.support "Assistant Enabled" -bool false
defaults write com.apple.Siri StatusMenuVisible -bool false
defaults write com.apple.Siri UserHasDeclinedEnable -bool true
log_success "Siri disabled"

# Disable Handoff
defaults write ~/Library/Preferences/ByHost/com.apple.coreservices.useractivityd ActivityAdvertisingAllowed -bool false
defaults write ~/Library/Preferences/ByHost/com.apple.coreservices.useractivityd ActivityReceivingAllowed -bool false
log_success "Handoff disabled"

# Disable personalized ads
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
log_success "Personalized ads disabled"

# ============================================================================
# FILE SYSTEM SECURITY
# ============================================================================

log_info "Configuring file system security..."

# Secure umask (new files are only readable/writable by owner)
# Add to shell profile
if ! grep -q "umask 077" ~/.zshrc 2>/dev/null; then
    echo "umask 077" >> ~/.zshrc
    log_success "Secure umask added to .zshrc"
fi

# Disable core dumps
if ! grep -q "ulimit -c 0" ~/.zshrc 2>/dev/null; then
    echo "ulimit -c 0" >> ~/.zshrc
    log_success "Core dumps disabled in .zshrc"
fi

# Set secure permissions on home directory
chmod 700 ~
log_success "Home directory permissions secured"

# ============================================================================
# NETWORK SECURITY
# ============================================================================

log_info "Configuring network security..."

# Disable Bonjour multicast advertising
sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true
log_success "Bonjour multicast advertising disabled"

# Disable IPv6 (optional - uncomment if needed)
# networksetup -listallnetworkservices | grep -v '*' | while read interface; do
#     sudo networksetup -setv6off "$interface" 2>/dev/null || true
# done
# log_success "IPv6 disabled"

# Enable secure DNS (optional - requires configuration)
# sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 1.0.0.1

# ============================================================================
# BROWSER SECURITY
# ============================================================================

log_info "Configuring browser security..."

# Safari settings
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true
defaults write com.apple.Safari WebKitDNSPrefetchingEnabled -bool false
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
log_success "Safari security settings configured"

# ============================================================================
# DIAGNOSTIC DATA
# ============================================================================

log_info "Disabling diagnostic data collection..."

# Disable crash reporter
defaults write com.apple.CrashReporter DialogType none
log_success "Crash reporter disabled"

# Disable diagnostic data submission
sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.SubmitDiagInfo.plist 2>/dev/null || true
log_success "Diagnostic data submission disabled"

# ============================================================================
# TIME MACHINE
# ============================================================================

log_info "Configuring Time Machine..."

# Don't prompt to use new hard drives as backup volume
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
log_success "Time Machine auto-prompt disabled"

# ============================================================================
# GATEKEEPER & XProtect
# ============================================================================

log_info "Configuring Gatekeeper..."

# Enable Gatekeeper
sudo spctl --master-enable
log_success "Gatekeeper enabled"

# Check XProtect status
if sudo /usr/libexec/XProtectCheck 2>&1 | grep -q "XProtect is up to date"; then
    log_success "XProtect is up to date"
else
    log_warning "XProtect may need updating"
fi

# ============================================================================
# ADDITIONAL SECURITY TOOLS CONFIGURATION
# ============================================================================

log_info "Configuring security tools..."

# Create .gnupg directory with secure permissions
if [ ! -d ~/.gnupg ]; then
    mkdir -p ~/.gnupg
    chmod 700 ~/.gnupg
    log_success "GPG directory created with secure permissions"
fi

# Create .ssh directory with secure permissions
if [ ! -d ~/.ssh ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    log_success "SSH directory created with secure permissions"
fi

# Secure SSH config
if [ -f ~/.ssh/config ]; then
    chmod 600 ~/.ssh/config
    log_success "SSH config permissions secured"
fi

# Secure authorized_keys
if [ -f ~/.ssh/authorized_keys ]; then
    chmod 600 ~/.ssh/authorized_keys
    log_success "SSH authorized_keys permissions secured"
fi

# ============================================================================
# FILE VAULT CHECK
# ============================================================================

log_info "Checking FileVault status..."

if fdesetup status | grep -q "FileVault is On"; then
    log_success "FileVault is enabled"
else
    log_warning "FileVault is NOT enabled - consider enabling it in System Preferences > Security & Privacy"
fi

# ============================================================================
# SECURITY AUDIT
# ============================================================================

log_info "Running security audit..."

echo ""
echo "=== Security Status Summary ==="
echo ""

echo "Firewall: $(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate)"
echo "FileVault: $(fdesetup status)"
echo "Gatekeeper: $(spctl --status)"
echo "Remote Login: $(sudo systemsetup -getremotelogin)"
echo "Remote Apple Events: $(sudo systemsetup -getremoteappleevents)"

echo ""
log_success "Security hardening complete!"
echo ""
log_info "Recommended next steps:"
echo "  1. Enable FileVault if not already enabled"
echo "  2. Review and configure VPN settings"
echo "  3. Set up password manager (1Password, Bitwarden)"
echo "  4. Enable 2FA on all critical accounts"
echo "  5. Review Privacy settings in System Preferences"
echo "  6. Restart your system to apply all changes"
echo ""

log_warning "Some settings may require a restart to take effect"
read -p "Restart now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Restarting system..."
    sudo shutdown -r now
fi
