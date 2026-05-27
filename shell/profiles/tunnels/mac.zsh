# shell/profiles/tunnels/mac.zsh
# macOS-only niceties for tunnel orchestration.

# Copy SOCKS proxy URL to clipboard after opening a tunnel — saves switching
# to System Preferences to paste it manually into Firefox/Chrome network settings.
_tn_copy_proxy() {
    local port="$1"
    if command -v pbcopy &>/dev/null; then
        printf "socks5://127.0.0.1:%s" "$port" | pbcopy
        echo "  ✓ copied SOCKS URL to clipboard"
    fi
}

# tnet  — concise summary of macOS network state. Helpful before opening tunnels.
tnet() {
    printf "\n  \e[36m▸\e[0m \e[1mNetwork\e[0m\n"
    printf "  \e[2mssid:\e[0m       %s\n" "$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')"
    printf "  \e[2mlocal IP:\e[0m   %s\n" "$(local_ip 2>/dev/null)"
    printf "  \e[2mpublic IP:\e[0m  %s\n" "$(curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || echo '?')"
    if command -v tailscale &>/dev/null; then
        printf "  \e[2mts IP:\e[0m      %s\n" "$(tailscale ip -4 2>/dev/null | head -1)"
    fi
    printf "  \e[2mVPN:\e[0m        %s\n\n" "$(vpn_status 2>/dev/null)"
}

# tn-known  — list ssh known_hosts entries (helpful when configuring jumps).
tn-known() {
    [[ -f ~/.ssh/known_hosts ]] || { echo "no known_hosts"; return 1; }
    awk '{print $1}' ~/.ssh/known_hosts | tr ',' '\n' | sort -u | head -40
}

# ts-route  — show current Tailscale subnet routes accepted by this Mac.
ts-route() {
    if command -v tailscale &>/dev/null; then
        tailscale status --json 2>/dev/null \
            | jq -r '.Self.AllowedIPs // [] | .[]' 2>/dev/null \
            || tailscale status 2>/dev/null | head -10
    else
        echo "tailscale not installed" >&2
    fi
}
