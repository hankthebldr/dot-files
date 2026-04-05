# shell/platform.zsh
# Cross-platform compatibility shims for macOS and Linux
# Source this from any shell script that needs clipboard, network, or open commands

# ── Platform Detection ───────────────────────────────────
export CLAW_OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    CLAW_OS="macos"
elif [[ -f /etc/os-release ]]; then
    CLAW_OS="linux"
fi

# ── Homebrew Prefix ──────────────────────────────────────
# Resolves to the correct brew prefix on macOS (Intel/ARM) and Linux
if command -v brew &>/dev/null; then
    export HOMEBREW_PREFIX="$(brew --prefix)"
elif [[ -d /opt/homebrew ]]; then
    export HOMEBREW_PREFIX="/opt/homebrew"
elif [[ -d /home/linuxbrew/.linuxbrew ]]; then
    export HOMEBREW_PREFIX="/home/linuxbrew/.linuxbrew"
elif [[ -d /usr/local/Homebrew ]]; then
    export HOMEBREW_PREFIX="/usr/local"
fi

# ── Clipboard ────────────────────────────────────────────
# Usage: echo "text" | clip_copy    /    clip_paste
if [[ "$CLAW_OS" == "macos" ]]; then
    clip_copy()  { pbcopy; }
    clip_paste() { pbpaste; }
elif command -v xclip &>/dev/null; then
    clip_copy()  { xclip -selection clipboard; }
    clip_paste() { xclip -selection clipboard -o; }
elif command -v xsel &>/dev/null; then
    clip_copy()  { xsel --clipboard --input; }
    clip_paste() { xsel --clipboard --output; }
elif command -v wl-copy &>/dev/null; then
    # Wayland
    clip_copy()  { wl-copy; }
    clip_paste() { wl-paste; }
else
    clip_copy()  { cat > /dev/null; echo "No clipboard tool found (install xclip)"; }
    clip_paste() { echo "No clipboard tool found (install xclip)"; }
fi

# ── Open URLs/Files ──────────────────────────────────────
# Usage: sysopen "https://example.com"  /  sysopen file.pdf
if [[ "$CLAW_OS" == "macos" ]]; then
    sysopen() { open "$@"; }
elif command -v xdg-open &>/dev/null; then
    sysopen() { xdg-open "$@"; }
else
    sysopen() { echo "No opener found (install xdg-utils)"; }
fi

# ── Local IP ─────────────────────────────────────────────
# Usage: local_ip
if [[ "$CLAW_OS" == "macos" ]]; then
    local_ip() { ipconfig getifaddr en0 2>/dev/null || echo 'offline'; }
else
    local_ip() { hostname -I 2>/dev/null | awk '{print $1}' || ip -4 addr show scope global | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1 || echo 'offline'; }
fi

# ── OS Version String ────────────────────────────────────
# Usage: os_version
if [[ "$CLAW_OS" == "macos" ]]; then
    os_version() { echo "$(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null)"; }
else
    os_version() { . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr; }
fi

# ── VPN Status ───────────────────────────────────────────
# Usage: vpn_status  → "connected" or "off"
if [[ "$CLAW_OS" == "macos" ]]; then
    vpn_status() { if scutil --nwi 2>/dev/null | grep -q utun; then echo 'connected'; else echo 'off'; fi; }
else
    vpn_status() { if ip link show 2>/dev/null | grep -qE 'tun0|wg0|vpn'; then echo 'connected'; else echo 'off'; fi; }
fi

# ── Network Speed Test ───────────────────────────────────
if [[ "$CLAW_OS" == "macos" ]] && command -v networkQuality &>/dev/null; then
    alias speed='networkQuality'
elif command -v speedtest &>/dev/null; then
    alias speed='speedtest'
elif command -v speedtest-cli &>/dev/null; then
    alias speed='speedtest-cli'
else
    alias speed='echo "Install speedtest-cli: pip install speedtest-cli"'
fi

# ── Clipboard Aliases ────────────────────────────────────
alias copy='clip_copy'
alias paste='clip_paste'
