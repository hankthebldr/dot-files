# shell/profiles/tunnels/common.zsh
# Cross-platform tunnel orchestration. Wraps scripts/utils/tunnel-manager.sh
# for the interactive flow, and provides standalone aliases for muscle-memory
# operations (quick local forward, SOCKS proxy, multi-hop).


# Where ControlMaster sockets live. Match tunnel-manager.sh's CONTROL_DIR.
export TUNNEL_CONTROL_DIR="${TUNNEL_CONTROL_DIR:-/tmp/ssh-tunnels}"
mkdir -p "$TUNNEL_CONTROL_DIR" 2>/dev/null

# ==========================================
# INTERACTIVE MANAGER
# ==========================================

# tn  — launch the interactive tunnel manager TUI (FZF-driven).
tn() {
    local mgr="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/tunnel-manager.sh"
    if [[ -x "$mgr" ]]; then
        bash "$mgr" "$@"
    else
        echo "tunnel-manager not found at $mgr" >&2
        return 1
    fi
}

# ==========================================
# QUICK ONE-SHOTS (no tunnels.yml needed)
# ==========================================

# tlocal <local-port>:<remote-host>:<remote-port> <ssh-target>  — forward
# a local port to a remote service via the SSH target. Uses ControlMaster so
# subsequent commands to the same target reuse the connection.
#
# Example: tlocal 9090:localhost:9090 bd790i
tlocal() {
    local spec="${1:?usage: tlocal <local:remote_host:remote_port> <ssh-target>}"
    local target="${2:?missing ssh-target}"
    local sock="${TUNNEL_CONTROL_DIR}/${target}-$$"
    echo "▸ forward $spec via $target"
    ssh -N -L "$spec" \
        -o ControlMaster=auto \
        -o ControlPath="$sock" \
        -o ControlPersist=10m \
        -f "$target"
    echo "  socket: $sock"
}

# tremote <remote-port>:<local-host>:<local-port> <ssh-target>  — REVERSE
# tunnel; expose a local service on the remote host. Useful for letting the
# BD790i hit something on your Mac.
#
# Example: tremote 8080:localhost:3000 bd790i   (BD790i can hit local :3000 on :8080)
tremote() {
    local spec="${1:?usage: tremote <remote_port:local_host:local_port> <ssh-target>}"
    local target="${2:?missing ssh-target}"
    local sock="${TUNNEL_CONTROL_DIR}/${target}-rev-$$"
    echo "▸ reverse-forward $spec via $target"
    ssh -N -R "$spec" \
        -o ControlMaster=auto \
        -o ControlPath="$sock" \
        -o ControlPersist=10m \
        -f "$target"
    echo "  socket: $sock"
}

# tsocks <local-port> <ssh-target>  — open a SOCKS5 proxy on $local-port
# that tunnels through the ssh target. Useful for browsing a remote intranet.
#
# Example: tsocks 1080 jump-host   then set Firefox to SOCKS 127.0.0.1:1080
tsocks() {
    local port="${1:?usage: tsocks <local-port> <ssh-target>}"
    local target="${2:?missing ssh-target}"
    local sock="${TUNNEL_CONTROL_DIR}/${target}-socks-$$"
    echo "▸ SOCKS5 on localhost:$port via $target"
    ssh -N -D "$port" \
        -o ControlMaster=auto \
        -o ControlPath="$sock" \
        -o ControlPersist=10m \
        -f "$target"
    if typeset -f _tn_copy_proxy &>/dev/null; then
        _tn_copy_proxy "$port"
    fi
}

# tjump <hop1> <hop2> [...] <final> — multi-hop ProxyJump shortcut.
# Builds the ssh -J chain and opens an interactive session on the final host.
#
# Example: tjump bastion vpn-gw target.internal
tjump() {
    if [[ $# -lt 2 ]]; then
        echo "usage: tjump <hop1> [<hop2> ...] <final>" >&2
        return 1
    fi
    local final="${@: -1}"
    local hops=()
    for h in "${@:1:$#-1}"; do hops+=("$h"); done
    local jumps; jumps="$(IFS=,; echo "${hops[*]}")"
    echo "▸ jumping: $jumps → $final"
    ssh -J "$jumps" "$final"
}

# ==========================================
# STATUS
# ==========================================

# tls  — list active SSH ControlMaster sockets + tailscale state.
tls() {
    printf "\n  \e[36m▸\e[0m \e[1mActive tunnels\e[0m\n\n"
    printf "  \e[2m── ssh ControlMaster sockets ──\e[0m\n"
    local found=0
    if [[ -d "$TUNNEL_CONTROL_DIR" ]]; then
        for sock in "$TUNNEL_CONTROL_DIR"/*; do
            # Skip the literal glob when no files match, and non-socket entries.
            [[ -S "$sock" ]] || continue
            found=1
            local owner_pid; owner_pid=$(ssh -O check -S "$sock" - 2>&1 | command grep -oE '[0-9]+' | head -1)
            printf "    %s  \e[2m(pid %s)\e[0m\n" "${sock##*/}" "${owner_pid:-?}"
        done
    fi
    (( found == 0 )) && printf "    \e[2m(none)\e[0m\n"

    echo ""
    printf "  \e[2m── ssh -L / -R / -D processes ──\e[0m\n"
    pgrep -af 'ssh.*(-L|-R|-D)' | head -10 | awk '{
        $1=""; sub(/^ /,""); print "    " $0
    }' || printf "    \e[2m(none)\e[0m\n"

    if command -v tailscale &>/dev/null; then
        echo ""
        printf "  \e[2m── tailscale ──\e[0m\n"
        tailscale status 2>/dev/null | head -8 | sed 's/^/    /'
    fi
    echo ""
}

# tkill [pattern]  — kill SSH tunnels matching pattern (or all if none given).
tkill() {
    local pattern="${1:-}"
    if [[ -z "$pattern" ]]; then
        echo "kill all tunnels? (y/N) "; read -k 1 ans; echo
        [[ "$ans" != "y" ]] && return 0
        pgrep -f 'ssh.*(-L|-R|-D)' | xargs -r kill -TERM 2>/dev/null
        rm -f "$TUNNEL_CONTROL_DIR"/* 2>/dev/null
        echo "✓ all tunnels stopped"
    else
        pgrep -f "ssh.*$pattern.*(-L|-R|-D)" | xargs -r kill -TERM 2>/dev/null
        rm -f "$TUNNEL_CONTROL_DIR"/*"$pattern"* 2>/dev/null
        echo "✓ tunnels matching '$pattern' stopped"
    fi
}

# ttopo  — render an ASCII topology of declared tunnels (from tunnels.yml).
# Delegates to the manager's existing topology view.
ttopo() {
    tn topology 2>/dev/null || tn --topology 2>/dev/null || \
        echo "no topology subcommand on tunnel-manager — declare tunnels in config/ssh/tunnels.yml"
}

# ==========================================
# HELP
# ==========================================

tunnels-help() {
    cat <<EOF
TUNNELS profile — PORT-RUNNER (Tier 6: hardware & ops)

  ── interactive ──────────────────────
  tn                       open the tunnel manager TUI (FZF over tunnels.yml)
  ttopo                    ASCII topology of declared tunnels

  ── quick one-shots ──────────────────
  tlocal <spec> <target>   local forward (-L)
  tremote <spec> <target>  reverse forward (-R)
  tsocks <port> <target>   SOCKS5 proxy (-D)
  tjump <hops...> <final>  multi-hop ssh -J chain

  ── status & cleanup ─────────────────
  tls                      list active tunnels + tailscale state
  tkill [pattern]          kill matching tunnels (no arg = all)

  examples:
    tlocal 9090:localhost:9090 bd790i      # grafana on localhost:9090
    tremote 8080:localhost:3000 bd790i     # lab head can hit local :3000
    tsocks 1080 bastion                    # SOCKS proxy → bastion network
    tjump bastion vpn target.internal      # 3-hop chain to target
EOF
}
