# shell/profiles/tunnels/linux.zsh
# Linux-only niceties for tunnel orchestration.

# Copy SOCKS URL via wl-copy (Wayland) or xclip (X11) when opening one.
_tn_copy_proxy() {
    local port="$1"
    if [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy &>/dev/null; then
        printf "socks5://127.0.0.1:%s" "$port" | wl-copy
        echo "  ✓ copied SOCKS URL to clipboard (wayland)"
    elif command -v xclip &>/dev/null; then
        printf "socks5://127.0.0.1:%s" "$port" | xclip -selection clipboard
        echo "  ✓ copied SOCKS URL to clipboard (x11)"
    fi
}

# tnet  — concise Linux network summary.
tnet() {
    printf "\n  \e[36m▸\e[0m \e[1mNetwork\e[0m\n"
    printf "  \e[2mhostname:\e[0m   %s\n" "$(hostname -f 2>/dev/null || hostname)"
    printf "  \e[2mlocal IP:\e[0m   %s\n" "$(local_ip 2>/dev/null)"
    printf "  \e[2mpublic IP:\e[0m  %s\n" "$(curl -fsS --max-time 2 https://api.ipify.org 2>/dev/null || echo '?')"
    if command -v tailscale &>/dev/null; then
        printf "  \e[2mts IP:\e[0m      %s\n" "$(tailscale ip -4 2>/dev/null | head -1)"
    fi
    if command -v wg &>/dev/null && sudo -n wg show 2>/dev/null | head -1 >/dev/null; then
        printf "  \e[2mWG ifaces:\e[0m  %s\n" "$(sudo wg show interfaces 2>/dev/null | tr '\n' ' ')"
    fi
    printf "  \e[2mVPN:\e[0m        %s\n\n" "$(vpn_status 2>/dev/null)"
}

# tn-known  — list ssh known_hosts entries.
tn-known() {
    [[ -f ~/.ssh/known_hosts ]] || { echo "no known_hosts"; return 1; }
    awk '{print $1}' ~/.ssh/known_hosts | tr ',' '\n' | sort -u | head -40
}

# ts-route  — show Tailscale subnet routes + check if IP forwarding is enabled
# (required for subnet routers / exit nodes on Linux).
ts-route() {
    if command -v tailscale &>/dev/null; then
        tailscale status 2>/dev/null | head -10
        echo ""
        local fwd_v4 fwd_v6
        fwd_v4=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
        fwd_v6=$(sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null)
        printf "  \e[2mip_forward (v4):\e[0m %s   \e[2m(v6):\e[0m %s\n" "${fwd_v4:-?}" "${fwd_v6:-?}"
        [[ "$fwd_v4" != "1" ]] && echo "  \e[33m!\e[0m subnet router requires v4 forwarding: sudo sysctl -w net.ipv4.ip_forward=1"
    else
        echo "tailscale not installed" >&2
    fi
}

# wgup <interface>  — wg-quick up shortcut for a configured WireGuard interface.
wgup() {
    local iface="${1:?usage: wgup <interface> (e.g. wg0)}"
    sudo wg-quick up "$iface"
}

# wgdown <interface>  — wg-quick down.
wgdown() {
    local iface="${1:?usage: wgdown <interface>}"
    sudo wg-quick down "$iface"
}
