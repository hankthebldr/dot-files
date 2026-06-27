# shell/profiles/homelab/linux.zsh
# Native mode: this IS the BD790i (or another Linux homelab head).
# Common.zsh calls _hl_* helpers — defined here as direct daemon invocations.

# Daemon delegates — these run locally on the homelab head.
_hl_kubectl() { kubectl "$@"; }
_hl_ollama()  { ollama "$@"; }
_hl_docker()  { docker "$@"; }

# Theme tokens for status dots (CLAW_RGB_* with refined-dark fallbacks).
_hl_c() {
    _HL_RESET=$'\e[0m'
    _HL_GREEN=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    _HL_RED=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    _HL_AMBER=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    _HL_DIM=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
}

# Status helpers — quick local readouts.
_hl_status_tailscale() {
    _hl_c
    if command -v tailscale &>/dev/null; then
        local state; state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null)
        if [[ "$state" == "Running" ]]; then
            local ip; ip=$(tailscale ip -4 2>/dev/null | head -1)
            printf "  ${_HL_GREEN}●${_HL_RESET} tailscale  ${_HL_DIM}running · %s${_HL_RESET}\n" "$ip"
        else
            printf "  ${_HL_RED}●${_HL_RESET} tailscale  ${_HL_DIM}%s${_HL_RESET}\n" "${state:-down}"
        fi
    else
        printf "  ${_HL_RED}●${_HL_RESET} tailscale  ${_HL_DIM}not installed${_HL_RESET}\n"
    fi
}
_hl_status_docker() {
    _hl_c
    if command -v docker &>/dev/null && systemctl is-active docker &>/dev/null; then
        local n; n=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
        printf "  ${_HL_GREEN}●${_HL_RESET} docker     ${_HL_DIM}%s container(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} docker     ${_HL_DIM}inactive${_HL_RESET}\n"
    fi
}
_hl_status_k3s() {
    _hl_c
    if command -v kubectl &>/dev/null && kubectl get nodes &>/dev/null; then
        local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}')
        printf "  ${_HL_GREEN}●${_HL_RESET} k3s        ${_HL_DIM}node %s${_HL_RESET}\n" "${ready:-?}"
    else
        printf "  ${_HL_RED}●${_HL_RESET} k3s        ${_HL_DIM}not reachable${_HL_RESET}\n"
    fi
}
_hl_status_ollama() {
    _hl_c
    if command -v ollama &>/dev/null && systemctl is-active ollama &>/dev/null; then
        local n; n=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
        printf "  ${_HL_GREEN}●${_HL_RESET} ollama     ${_HL_DIM}%s model(s)${_HL_RESET}\n" "$n"
    else
        printf "  ${_HL_RED}●${_HL_RESET} ollama     ${_HL_DIM}inactive${_HL_RESET}\n"
    fi
}

# Native connection / lifecycle commands.

# hssh  — no-op when already on the homelab head, but useful for muscle memory.
hssh() {
    echo "(already on $BD790I_HOST — no SSH needed)"
}

# hssh-tunnel <local:remote>...  — same syntax as the Mac variant, but
# the only use-case on the lab head itself is reverse tunnels to dev machines.
hssh-tunnel() {
    echo "tunnels on the lab head are usually outbound — use:" >&2
    echo "  ssh -R <port>:localhost:<port> <dev-machine>" >&2
}

# hreboot  — local reboot.
hreboot() {
    echo "▸ rebooting (you're on the host)"
    sudo systemctl reboot
}

# Apply manifests directly from the local repo (no rsync needed).
_hl_apply_manifests() {
    kubectl apply -k "$HOMELAB_REPO" 2>&1 | tail -10
}

# hupdate  — full system update on the lab head: apt + Tailscale + K3s + Ollama.
# Useful for the BD790i's regular maintenance cycle.
hupdate() {
    echo "▸ apt update / upgrade"
    sudo apt-get update -qq && sudo apt-get upgrade -y 2>&1 | tail -5
    echo "▸ tailscale update"
    sudo tailscale update 2>&1 | tail -3 || true
    echo "▸ k3s (skipping — uses installer script for major versions)"
    echo "▸ ollama"
    curl -fsSL https://ollama.com/install.sh | sh 2>&1 | tail -3 || true
    echo "✓ done"
}

# hjournal <unit>  — quick journal tail for a homelab daemon
hjournal() {
    local unit="${1:?usage: hjournal <unit-name> (e.g. docker, ollama, tailscaled, k3s)}"
    sudo journalctl -u "$unit" -f
}
