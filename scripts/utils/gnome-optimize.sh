#!/usr/bin/env bash
# scripts/utils/gnome-optimize.sh
#
# Apply a compact, granular, tech-oriented GNOME desktop preset.
# Pure user-level dconf/gsettings — no sudo needed.
#
# Run:  bash scripts/utils/gnome-optimize.sh
#   or: claw desktop optimize

set -e

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
source "$DOTFILES_DIR/scripts/utils/logger.sh"

if ! command -v gsettings &>/dev/null; then
    log_error "gsettings not found — this script is GNOME-only."
    exit 1
fi

log_info "── GNOME compact-dev preset ──"

# ── Appearance ───────────────────────────────────────────────────────
log_info "Appearance: dark theme, accent colors"
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-blue-dark' 2>/dev/null || \
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Yaru-blue' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'Yaru' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size 20

# ── Fonts: tight + monospace-first ───────────────────────────────────
log_info "Fonts: smaller UI, monospace = JetBrainsMono Nerd Font Mono"
gsettings set org.gnome.desktop.interface font-name 'Inter 10' 2>/dev/null || \
gsettings set org.gnome.desktop.interface font-name 'Ubuntu 10'
gsettings set org.gnome.desktop.interface document-font-name 'Inter 10' 2>/dev/null || \
gsettings set org.gnome.desktop.interface document-font-name 'Ubuntu 10'
gsettings set org.gnome.desktop.interface monospace-font-name 'JetBrainsMono Nerd Font Mono 10'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Inter Bold 10' 2>/dev/null || \
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Ubuntu Bold 10'
gsettings set org.gnome.desktop.interface text-scaling-factor 1.0
gsettings set org.gnome.desktop.interface font-hinting 'slight'
gsettings set org.gnome.desktop.interface font-antialiasing 'rgba'

# ── Clock & top bar ──────────────────────────────────────────────────
log_info "Clock: 24h, seconds, weekday + date"
gsettings set org.gnome.desktop.interface clock-format '24h'
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface clock-show-date true

# ── Power & battery ──────────────────────────────────────────────────
log_info "Power: show battery percentage, never auto-suspend on AC"
gsettings set org.gnome.desktop.interface show-battery-percentage true
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 1800

# ── Window manager: tight, dev-friendly ──────────────────────────────
log_info "WM: minimize/maximize/close buttons, mouse focus is click-only"
gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
gsettings set org.gnome.desktop.wm.preferences focus-mode 'click'
gsettings set org.gnome.desktop.wm.preferences action-double-click-titlebar 'toggle-maximize'
gsettings set org.gnome.desktop.wm.preferences action-middle-click-titlebar 'lower'
gsettings set org.gnome.desktop.wm.preferences action-right-click-titlebar 'menu'
gsettings set org.gnome.desktop.wm.preferences resize-with-right-button true
gsettings set org.gnome.mutter center-new-windows true
gsettings set org.gnome.mutter dynamic-workspaces false
gsettings set org.gnome.desktop.wm.preferences num-workspaces 6
gsettings set org.gnome.mutter workspaces-only-on-primary false
gsettings set org.gnome.mutter edge-tiling true
gsettings set org.gnome.mutter attach-modal-dialogs false

# ── Animations: subtle, fast (not disabled — disabling can break extensions) ──
log_info "Animations: enabled but speed-tuned"
gsettings set org.gnome.desktop.interface enable-animations true

# ── Hot corners ──────────────────────────────────────────────────────
log_info "Hot corners: disabled (Activities triggers from key only)"
gsettings set org.gnome.desktop.interface enable-hot-corners false

# ── Files (Nautilus): list view, hidden files, sort folders first ────
log_info "Files: list view, show hidden, sort folders first"
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'
gsettings set org.gnome.nautilus.preferences show-hidden-files true
gsettings set org.gnome.nautilus.preferences default-sort-order 'type'
gsettings set org.gnome.nautilus.preferences click-policy 'double'
gsettings set org.gnome.nautilus.list-view default-zoom-level 'small'
gsettings set org.gnome.nautilus.list-view default-visible-columns "['name','size','type','date_modified','date_modified_with_time']"

# ── Keyboard ────────────────────────────────────────────────────────
log_info "Keyboard: fast repeat, short delay"
gsettings set org.gnome.desktop.peripherals.keyboard delay 'uint32 200'
gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 'uint32 24'

# ── Touchpad / mouse ─────────────────────────────────────────────────
log_info "Touchpad: tap-to-click, natural-scroll off (dev-friendly)"
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true
gsettings set org.gnome.desktop.peripherals.touchpad natural-scroll false
gsettings set org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
gsettings set org.gnome.desktop.peripherals.mouse natural-scroll false

# ── Privacy: don't track recents in remote / file-dialog ─────────────
log_info "Privacy: short recents retention"
gsettings set org.gnome.desktop.privacy remember-recent-files true
gsettings set org.gnome.desktop.privacy recent-files-max-age 14

# ── Ubuntu Dock (24.04 default) — make it compact + auto-hide ───────
if gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.shell.extensions.dash-to-dock'; then
    log_info "Dock: compact, intelligent auto-hide, fixed icon size"
    gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 28
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'
    gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
    gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
    gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
    gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false
    gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false
    gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
    gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.6
fi

# ── Terminal default (gnome-terminal — fallback even if you mostly use Ghostty) ──
if command -v gsettings &>/dev/null && gsettings list-schemas | grep -q 'org.gnome.Terminal.Legacy.Profile'; then
    default_profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
    if [[ -n "$default_profile" ]]; then
        path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${default_profile}/"
        log_info "gnome-terminal: JetBrainsMono Nerd Font Mono 12, GitHub dark palette"
        gsettings set "$path" use-system-font false
        gsettings set "$path" font 'JetBrainsMono Nerd Font Mono 12'
        gsettings set "$path" background-color '#0D1117'
        gsettings set "$path" foreground-color '#C9D1D9'
        gsettings set "$path" use-theme-colors false
        gsettings set "$path" use-theme-transparency false
        gsettings set "$path" cursor-shape 'ibeam'
        gsettings set "$path" cursor-blink-mode 'on'
        gsettings set "$path" scrollback-unlimited true
        gsettings set "$path" audible-bell false
    fi
fi

# ── Reload extensions if any are active ──────────────────────────────
if command -v gnome-extensions &>/dev/null; then
    # If Just Perfection is installed, apply our compact defaults
    if gnome-extensions list 2>/dev/null | grep -q 'just-perfection-desktop@just-perfection'; then
        schema='org.gnome.shell.extensions.just-perfection'
        log_info "Just Perfection: panel size 24, smaller icons, hide accessibility menu"
        gsettings set "$schema" panel-size 24      2>/dev/null || true
        gsettings set "$schema" panel-icon-size 14 2>/dev/null || true
        gsettings set "$schema" notification-banner-position 1 2>/dev/null || true
        gsettings set "$schema" accessibility-menu false 2>/dev/null || true
        gsettings set "$schema" workspace true     2>/dev/null || true
        gsettings set "$schema" startup-status 0   2>/dev/null || true
        gsettings set "$schema" animation 2        2>/dev/null || true
    fi

    # Vitals — show CPU/mem/temp in panel
    if gnome-extensions list 2>/dev/null | grep -q 'Vitals@CoreCoding.com'; then
        schema='org.gnome.shell.extensions.vitals'
        log_info "Vitals: CPU temp, memory, network, top process"
        gsettings set "$schema" hot-sensors "['__network-tx_bytes__','_processor_usage_','_memory_usage_','_temperature_processor_0_']" 2>/dev/null || true
        gsettings set "$schema" position-in-panel 1 2>/dev/null || true
        gsettings set "$schema" use-higher-precision true 2>/dev/null || true
    fi
fi

log_success "GNOME compact-dev preset applied."
log_info "Some settings need a re-login or 'Alt+F2 → r' (X11) to take full effect."
