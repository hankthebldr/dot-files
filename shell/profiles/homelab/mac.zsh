# shell/profiles/homelab/mac.zsh
# Cockpit mode: Mac SSHes into the BD790i for every operation.
# Common.zsh calls _hl_* helpers — defined here as SSH wrappers.

# SSH base — uses ControlMaster (see ~/.ssh/config) for connection reuse.
# All wrappers use this prefix so latency stays low across rapid commands.
_hl_ssh() {
    ssh -o ControlMaster=auto \
        -o ControlPath="/tmp/ssh-bd790i-%r@%h:%p" \
        -o ControlPersist=10m \
        "${BD790I_USER}@${BD790I_HOST}" "$@"
}

# Daemon delegates — each runs the matching command on the remote host.
_hl_kubectl() { _hl_ssh kubectl "$@"; }
_hl_ollama()  { _hl_ssh ollama "$@"; }
_hl_docker()  { _hl_ssh docker "$@"; }

# Status helpers — quick single-line readouts.
_hl_status_tailscale() {
    local out; out=$(_hl_ssh "tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null" 2>/dev/null)
    if [[ "$out" == "Running" ]]; then
        printf "  \e[32m●\e[0m tailscale  \e[2mrunning\e[0m\n"
    else
        printf "  \e[33m○\e[0m tailscale  \e[2m%s\e[0m\n" "${out:-unreachable}"
    fi
}

_hl_status_docker() {
    local n; n=$(_hl_ssh "docker ps -q 2>/dev/null | wc -l" 2>/dev/null | tr -d ' ')
    if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then
        printf "  \e[32m●\e[0m docker     \e[2m%s container(s)\e[0m\n" "$n"
    else
        printf "  \e[33m○\e[0m docker     \e[2munreachable\e[0m\n"
    fi
}

_hl_status_k3s() {
    local ready; ready=$(_hl_ssh "kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}'" 2>/dev/null)
    if [[ "$ready" == "Ready" ]]; then
        printf "  \e[32m●\e[0m k3s        \e[2mnode Ready\e[0m\n"
    else
        printf "  \e[33m○\e[0m k3s        \e[2m%s\e[0m\n" "${ready:-unreachable}"
    fi
}

_hl_status_ollama() {
    local n; n=$(_hl_ssh "ollama list 2>/dev/null | tail -n +2 | wc -l" 2>/dev/null | tr -d ' ')
    if [[ -n "$n" && "$n" =~ ^[0-9]+$ ]]; then
        printf "  \e[32m●\e[0m ollama     \e[2m%s model(s)\e[0m\n" "$n"
    else
        printf "  \e[33m○\e[0m ollama     \e[2munreachable\e[0m\n"
    fi
}

# Connection commands.

# hssh  — interactive SSH into the BD790i.
hssh() { _hl_ssh; }

# hssh-tunnel <local:remote>...  — open one-shot local forwards.
# Example: hssh-tunnel 9090:9090 3000:3000
hssh-tunnel() {
    local args=(-N)
    for spec in "$@"; do args+=(-L "$spec"); done
    ssh -o ControlPath="/tmp/ssh-bd790i-tunnel-%r@%h:%p" \
        -o ControlPersist=yes \
        "${args[@]}" "${BD790I_USER}@${BD790I_HOST}"
}

# hreboot  — graceful remote reboot. Requires passwordless sudo via SSH.
hreboot() {
    echo "▸ rebooting $BD790I_HOST"
    _hl_ssh "sudo systemctl reboot" 2>&1
}

# hwake — wake-on-LAN trigger (assumes you've configured your router; mac=lan-only).
hwake() {
    if [[ -n "$BD790I_MAC" ]] && command -v wakeonlan &>/dev/null; then
        wakeonlan "$BD790I_MAC"
    else
        echo "set BD790I_MAC and install wakeonlan: brew install wakeonlan" >&2
        return 1
    fi
}

# Apply manifests by syncing the local repo, then SSH'ing kubectl apply.
_hl_apply_manifests() {
    # Run `kubectl apply -k` REMOTELY against the BD790i, with the manifests
    # already mounted on it via the gitea sync. If you push manifests from
    # Mac you'd `rsync` here first — minimal default below.
    _hl_kubectl apply -k "$HOMELAB_REPO" 2>&1 | tail -10
}
