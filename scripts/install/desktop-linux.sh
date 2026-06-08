#!/usr/bin/env bash
# scripts/install/desktop-linux.sh
#
# Install the apps that make Ubuntu/GNOME feel like a tight dev workstation:
#   - Ghostty (terminal)
#   - Caffeine (Amphetamine-equivalent: keep system awake)
#   - GNOME Extension Manager (GUI for browsing/installing extensions)
#   - Recommended extensions: Just Perfection, Dash to Panel, Vitals, Caffeine,
#     Pop Shell, Blur My Shell, AppIndicator
#   - Peripherals: TESmart KVM udev rule (fixes USB-autosuspend input drops)
#
# Companion: scripts/utils/gnome-optimize.sh applies dconf settings.

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"
source "$DOTFILES_DIR/scripts/utils/detect-os.sh"
detect_os

if [[ "$PKG_MANAGER" != "apt" ]]; then
    log_warning "desktop-linux.sh is for Ubuntu/Debian (apt). Detected: $PKG_MANAGER"
    exit 1
fi

log_info "── Desktop apps for GNOME (Ubuntu) ──"

sudo apt-get update -qq

# ── Caffeine — keep-awake ───────────────────────────────────────────
# We use the GNOME Shell extension (caffeine@patapon.info, installed below via
# gext), NOT the apt `caffeine` package. The standalone app is deprecated on
# GNOME 46+ (its caffeine-indicator tray app errors/misbehaves), and running
# both fights over screensaver inhibition. If the apt app is present, remove it:
#   sudo apt-get remove -y caffeine
if dpkg -s caffeine &>/dev/null; then
    log_warning "Legacy apt 'caffeine' detected — remove it (we use the GNOME extension):"
    log_warning "  sudo apt-get remove -y caffeine"
fi

# ── GNOME Extension Manager ─────────────────────────────────────────
if ! dpkg -s gnome-shell-extension-manager &>/dev/null; then
    log_info "Installing GNOME Extension Manager..."
    sudo apt-get install -y gnome-shell-extension-manager \
        || log_warning "extension-manager install failed"
fi

# ── pipx + gnome-extensions-cli (for headless extension installs) ──
if ! command -v gext &>/dev/null; then
    log_info "Installing gnome-extensions-cli (gext) via pipx..."
    if ! command -v pipx &>/dev/null; then
        sudo apt-get install -y pipx || python3 -m pip install --user pipx
        command -v pipx &>/dev/null && pipx ensurepath
    fi
    pipx install gnome-extensions-cli || log_warning "gext install failed"
fi

# ── AppIndicator (system tray support for older apps incl. Caffeine) ─
if ! dpkg -s gnome-shell-extension-appindicator &>/dev/null; then
    log_info "Installing AppIndicator support..."
    sudo apt-get install -y gnome-shell-extension-appindicator \
        || log_warning "appindicator install failed"
fi

# ── Ghostty (snap classic) ──────────────────────────────────────────
if ! command -v ghostty &>/dev/null; then
    log_info "Installing Ghostty via snap..."
    sudo snap install ghostty --classic || log_warning "ghostty install failed"
fi

# ── Make Ghostty the default terminal (preferred over GNOME Terminal) ──
if command -v ghostty &>/dev/null; then
    log_info "Setting Ghostty as the default terminal..."
    # GNOME default-applications (Files "Open Terminal", gnome-shell, etc.).
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.default-applications.terminal exec 'ghostty' 2>/dev/null || true
        gsettings set org.gnome.desktop.default-applications.terminal exec-arg '-e' 2>/dev/null || true
    fi
    # Debian alternative used by `x-terminal-emulator` and some apps (needs root).
    _gpath="$(command -v ghostty)"
    sudo update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$_gpath" 60 2>/dev/null || true
    sudo update-alternatives --set x-terminal-emulator "$_gpath" 2>/dev/null || true
fi

# ── GNOME extensions (installed for current user via gext) ──────────
if command -v gext &>/dev/null; then
    log_info "Installing GNOME Shell extensions for $USER..."
    # IDs from extensions.gnome.org
    EXTENSIONS=(
        just-perfection-desktop@just-perfection                 # granular UI control
        dash-to-panel@jderose9.github.com                       # Windows-style taskbar
        Vitals@CoreCoding.com                                   # CPU/GPU/temp in panel
        caffeine@patapon.info                                   # Amphetamine equivalent (per-app)
        pop-shell@system76.com                                  # auto-tiling window manager
        blur-my-shell@aunetx                                    # visual polish
        tactile@lundal.io                                       # keyboard-driven window tiling
    )
    for ext in "${EXTENSIONS[@]}"; do
        gext install "$ext" 2>&1 | tail -1 || log_warning "Failed: $ext"
    done

    log_info "Enabling installed extensions..."
    for ext in "${EXTENSIONS[@]}"; do
        gext enable "$ext" 2>/dev/null || true
    done
fi

# ── Peripherals: TESmart KVM input-drop fix (USB autosuspend) ───────
KVM_RULE="$DOTFILES_DIR/config/udev/99-tesmart-kvm.rules"
if [[ -f "$KVM_RULE" ]]; then
    log_info "Deploying TESmart KVM udev rule (disable USB autosuspend on the hub)..."
    if sudo install -m 0644 "$KVM_RULE" /etc/udev/rules.d/99-tesmart-kvm.rules \
        && sudo udevadm control --reload && sudo udevadm trigger; then
        log_success "KVM udev rule deployed (config/udev/99-tesmart-kvm.rules)"
    else
        log_warning "KVM udev rule deploy failed"
    fi
fi

log_success "Desktop apps installed."
log_info ""
log_info "Next steps:"
log_info "  1. Log out and back in (or reboot) so GNOME picks up the new extensions."
log_info "  2. Run: bash $DOTFILES_DIR/scripts/utils/gnome-optimize.sh"
log_info "  3. Open 'Extension Manager' to fine-tune per-extension settings."
log_info ""
log_info "Caffeine 'per-window' Amphetamine feature lives at:"
log_info "  Extension Manager → Caffeine → Settings → 'Inhibit when running'"
