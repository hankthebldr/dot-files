#!/usr/bin/env bash
################################################################################
# workstation-blackwell.sh — AI/cloud-native workstation installer (Ubuntu)
#
# Comprehensive installer for the Blackwell-class AI workstation spec:
#   Section 1: GPU + CUDA          → defers to ai-workstation-toolchain.sh
#   Section 2: Containers + K8s    → docker, kubectl, helm, k9s, minikube, opentofu
#   Section 3: Local AI            → huggingface_hub (vLLM via ai-workstation)
#   Section 4: Dev env             → Cursor IDE, Bruno API tester
#   Section 5: OS essentials       → micro, timeshift, flatpak + flathub remote
#
# Idempotent: each step skips work that's already done. Re-running is safe.
#
# Flags:
#   --essentials   only Section 5 (OS essentials + flatpak/flathub)
#   --k8s          only Section 2 K8s tooling (no docker — assumed present)
#   --ai           only Section 3 extras (HF CLI; defers vLLM)
#   --gui          only Section 4 (Cursor + Bruno)
#   --all          everything (DEFAULT when no scope flag is passed)
#   --dry-run      print actions without executing
#   --help, -h     this header
#
# Assumes: Ubuntu 24.04+, apt, sudo. NVIDIA driver + CUDA handled separately.
################################################################################

set -e

# Augment PATH with common user-managed locations so `command -v` detects
# tools the user installed via Homebrew / cargo / pipx / uv / ~/.local/bin.
# Without this, running under `bash script.sh` (instead of `zsh -ic`) misses
# everything outside the default /usr/bin /usr/local/bin.
for _p in /home/linuxbrew/.linuxbrew/bin /opt/homebrew/bin \
          "$HOME/.cargo/bin" "$HOME/.local/bin" "$HOME/go/bin"; do
    [[ -d "$_p" ]] && PATH="$_p:$PATH"
done
export PATH

# Always resolve from this script's own location, not $DOTFILES_DIR — if the
# user is running this from a checkout that's separate from their active
# ~/.dotfiles install, the env var would point at the wrong tree.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/utils/logger.sh"
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/utils/detect-os.sh"

# ── Flag parsing ─────────────────────────────────────────────────────────────
INSTALL_ESSENTIALS=false
INSTALL_K8S=false
INSTALL_AI=false
INSTALL_GUI=false
DRY_RUN=false
ANY_SCOPE_FLAG=false

print_help() {
    awk '
        NR == 1 && /^#!/  { next }
        /^####*$/         { next }
        /^# / || /^#$/    { sub(/^# ?/, ""); print; next }
        NF == 0           { print ""; next }
        { exit }
    ' "${BASH_SOURCE[0]}"
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --essentials) INSTALL_ESSENTIALS=true; ANY_SCOPE_FLAG=true ;;
        --k8s)        INSTALL_K8S=true;        ANY_SCOPE_FLAG=true ;;
        --ai)         INSTALL_AI=true;         ANY_SCOPE_FLAG=true ;;
        --gui)        INSTALL_GUI=true;        ANY_SCOPE_FLAG=true ;;
        --all)        INSTALL_ESSENTIALS=true; INSTALL_K8S=true
                      INSTALL_AI=true;         INSTALL_GUI=true
                      ANY_SCOPE_FLAG=true ;;
        --dry-run)    DRY_RUN=true ;;
        --help|-h)    print_help; exit 0 ;;
        *) log_error "Unknown flag: $1"; print_help; exit 1 ;;
    esac
    shift
done

# Default: install everything if no scope flag was passed.
if ! $ANY_SCOPE_FLAG; then
    INSTALL_ESSENTIALS=true
    INSTALL_K8S=true
    INSTALL_AI=true
    INSTALL_GUI=true
fi

# ── OS gate ──────────────────────────────────────────────────────────────────
detect_os
if [[ "$OS_TYPE" == "macos" ]]; then
    log_error "This script targets Ubuntu/Debian (apt). On macOS, use the brew-based scripts instead."
    exit 1
fi
if [[ "$PKG_MANAGER" != "apt" ]]; then
    log_error "Only apt is supported. Detected: $PKG_MANAGER"
    exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────────────
have() { command -v "$1" &>/dev/null; }
have_dpkg() { dpkg -l "$1" 2>/dev/null | grep -q '^ii'; }

# Run a command, or just log it under --dry-run. Use for any side-effecting op.
run() {
    if $DRY_RUN; then
        printf '  \e[38;2;139;148;158m[dry-run]\e[0m %s\n' "$*"
    else
        eval "$@"
    fi
}

# Idempotent apt install. Updates the cache once per script run.
APT_UPDATED=false
apt_get_install() {
    local missing=()
    local unavailable=()
    for pkg in "$@"; do
        # Skip if already installed via apt OR present on PATH (e.g. brew).
        # Prevents reinstalling tools the user already has from another source.
        if have_dpkg "$pkg" || have "$pkg"; then
            log_info "  ✓ $pkg already installed"
        else
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} == 0 )); then return 0; fi
    if ! $APT_UPDATED; then
        run "sudo apt-get update -qq" || true
        APT_UPDATED=true
    fi
    # Filter out packages apt can't see (e.g. fastfetch isn't in Ubuntu 24.04
    # main; user usually has it via brew). Don't kill the run for those —
    # warn + skip so the rest of the script proceeds.
    local available=()
    for pkg in "${missing[@]}"; do
        if apt-cache show "$pkg" &>/dev/null; then
            available+=("$pkg")
        else
            unavailable+=("$pkg")
        fi
    done
    if (( ${#unavailable[@]} > 0 )); then
        log_warning "  ! not in apt repos, skipping: ${unavailable[*]}"
        log_warning "    install via brew/cargo/source if you need them"
    fi
    if (( ${#available[@]} == 0 )); then return 0; fi
    run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ${available[*]}"
}

# Download a .deb to a temp file and apt install it (resolves deps cleanly,
# unlike dpkg -i). Caller passes URL + a descriptive name for logging.
install_deb_from_url() {
    local url="$1"
    local name="$2"
    local tmp
    tmp="$(mktemp --suffix=.deb)"
    log_info "  ↓ downloading $name .deb"
    run "curl -fsSL '$url' -o '$tmp'"
    run "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y '$tmp'"
    run "rm -f '$tmp'"
}

# Stage a binary AppImage under ~/Applications and a user .desktop entry.
# Useful for Cursor / any other AppImage we want first-class in the app grid.
install_appimage() {
    local url="$1"
    local app_name="$2"          # filesystem name (no spaces)
    local display_name="$3"      # shown in app grid
    local categories="$4"        # e.g. "Development;IDE;"
    local extra_flags="$5"       # e.g. "--no-sandbox"
    local app_lower=$(printf '%s' "$app_name" | tr '[:upper:]' '[:lower:]')
    local dest="$HOME/Applications/${app_name}.AppImage"
    local desktop="$HOME/.local/share/applications/${app_lower}.desktop"

    run "mkdir -p '$HOME/Applications' '$HOME/.local/share/applications'"
    log_info "  ↓ downloading $display_name AppImage"
    run "curl -fsSL '$url' -o '$dest'"
    run "chmod +x '$dest'"

    if $DRY_RUN; then
        printf '  \e[38;2;139;148;158m[dry-run]\e[0m write %s\n' "$desktop"
    else
        cat > "$desktop" <<EOF
[Desktop Entry]
Name=${display_name}
Exec=${dest} ${extra_flags} %U
Terminal=false
Type=Application
Icon=${app_lower}
StartupWMClass=${app_lower}
Comment=${display_name}
Categories=${categories}
EOF
    fi
    run "update-desktop-database '$HOME/.local/share/applications/' >/dev/null 2>&1 || true"
}

# ── Section 5: OS essentials ─────────────────────────────────────────────────
install_essentials() {
    log_info ""
    log_info "── Section 5: OS essentials ──"
    apt_get_install \
        build-essential git curl wget \
        btop htop micro fzf ripgrep fastfetch \
        timeshift ufw \
        flatpak

    # Flathub remote (user scope — no sudo, no system-wide pollution).
    if have flatpak; then
        if flatpak remote-list --user 2>/dev/null | grep -q '^flathub'; then
            log_info "  ✓ flathub remote already configured (user)"
        else
            log_info "  + adding flathub remote (user scope)"
            run "flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
        fi
    fi
}

# ── Section 2: Containers + K8s ──────────────────────────────────────────────
# Docker is assumed present (you already have docker-ce). This block installs
# the orchestration layer: kubectl, helm, k9s, minikube, opentofu.
# NVIDIA Container Toolkit + K3s + device plugin are handled by
# scripts/install/ai-workstation-toolchain.sh — we don't duplicate them.
install_k8s() {
    log_info ""
    log_info "── Section 2: K8s ecosystem ──"

    # kubectl — official Kubernetes apt repo (pkgs.k8s.io)
    if have kubectl; then
        log_info "  ✓ kubectl already installed ($(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion/ {print $2; exit}'))"
    else
        log_info "  + kubectl via official apt repo"
        run "sudo mkdir -p -m 755 /etc/apt/keyrings"
        run "curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        run "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null"
        APT_UPDATED=false
        apt_get_install kubectl
    fi

    # helm — official Helm apt repo
    if have helm; then
        log_info "  ✓ helm already installed ($(helm version --short 2>/dev/null))"
    else
        log_info "  + helm via official apt repo"
        run "curl -fsSL https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor -o /usr/share/keyrings/helm.gpg"
        run "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main' | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list >/dev/null"
        APT_UPDATED=false
        apt_get_install helm
    fi

    # k9s — single binary, install from latest github release
    if have k9s; then
        log_info "  ✓ k9s already installed"
    else
        log_info "  + k9s via github release"
        local arch
        arch="$(dpkg --print-architecture)"
        local url="https://github.com/derailed/k9s/releases/latest/download/k9s_linux_${arch}.deb"
        install_deb_from_url "$url" "k9s"
    fi

    # minikube — local k8s cluster, official deb from github
    if have minikube; then
        log_info "  ✓ minikube already installed"
    else
        log_info "  + minikube via github release"
        local arch
        arch="$(dpkg --print-architecture)"
        install_deb_from_url \
            "https://storage.googleapis.com/minikube/releases/latest/minikube_latest_${arch}.deb" \
            "minikube"
    fi

    # OpenTofu — official one-liner installer (signed)
    if have tofu; then
        log_info "  ✓ opentofu already installed ($(tofu version | head -1))"
    else
        log_info "  + opentofu via official install script"
        local tmp
        tmp="$(mktemp)"
        run "curl -fsSL 'https://get.opentofu.org/install-opentofu.sh' -o '$tmp'"
        run "chmod +x '$tmp'"
        run "'$tmp' --install-method deb"
        run "rm -f '$tmp'"
    fi
}

# ── Section 3: AI extras ─────────────────────────────────────────────────────
# Core inference stack (vLLM, llama.cpp, NVIDIA Container Toolkit) lives in
# ai-workstation-toolchain.sh. This block only adds the developer CLI bits
# that fit cleanly outside that heavyweight installer.
install_ai() {
    log_info ""
    log_info "── Section 3: AI toolchain extras ──"

    # huggingface_hub — use `uv tool install` so it lands in $HOME, no sudo.
    if have huggingface-cli || have hf; then
        log_info "  ✓ huggingface_hub CLI already installed"
    elif have uv; then
        log_info "  + huggingface_hub via uv tool install"
        run "uv tool install 'huggingface_hub[cli]'"
    else
        log_warning "  ! uv missing — install uv first, then re-run --ai"
    fi

    log_info "  i vLLM / TensorRT-LLM: deferred to ai-workstation-toolchain.sh"
    log_info "    run: bash $REPO_ROOT/scripts/install/ai-workstation-toolchain.sh --inference-only"
}

# ── Section 4: Dev environment ───────────────────────────────────────────────
install_gui() {
    log_info ""
    log_info "── Section 4: Dev environment ──"

    # Cursor IDE — distributed as an AppImage. Same --no-sandbox dance as
    # Obsidian on Ubuntu 24.04 (Electron + AppArmor userns restriction).
    if [[ -x "$HOME/Applications/Cursor.AppImage" ]]; then
        log_info "  ✓ Cursor AppImage already installed"
    else
        log_info "  + Cursor IDE (AppImage)"
        install_appimage \
            "https://downloader.cursor.sh/linux/appImage/x64" \
            "Cursor" "Cursor" "Development;IDE;TextEditor;" "--no-sandbox"
    fi

    # Bruno — official .deb from github releases
    if have bruno; then
        log_info "  ✓ Bruno already installed"
    else
        log_info "  + Bruno API tester (.deb)"
        local arch
        arch="$(dpkg --print-architecture)"
        # Latest release URL — Bruno uses a predictable pattern.
        local latest_url
        # Bruno asset naming: bruno_<version>_<arch>_linux.deb (deb format last).
        latest_url="$(curl -fsSL 'https://api.github.com/repos/usebruno/bruno/releases/latest' \
            | grep "browser_download_url.*_${arch}_linux\.deb\"" \
            | head -1 | cut -d'"' -f4)"
        if [[ -n "$latest_url" ]]; then
            install_deb_from_url "$latest_url" "bruno"
        else
            log_warning "  ! could not resolve Bruno latest .deb URL — install manually from https://www.usebruno.com/downloads"
        fi
    fi
}

# ── Run ──────────────────────────────────────────────────────────────────────
log_info "════════════════════════════════════════════════════════════════"
log_info " workstation-blackwell.sh — comprehensive AI workstation install"
log_info "════════════════════════════════════════════════════════════════"
$DRY_RUN && log_warning "DRY RUN — no changes will be made"
log_info ""
log_info " scope:"
log_info "   essentials : $($INSTALL_ESSENTIALS && echo yes || echo no)"
log_info "   k8s        : $($INSTALL_K8S        && echo yes || echo no)"
log_info "   ai         : $($INSTALL_AI         && echo yes || echo no)"
log_info "   gui        : $($INSTALL_GUI        && echo yes || echo no)"

$INSTALL_ESSENTIALS && install_essentials
$INSTALL_K8S        && install_k8s
$INSTALL_AI         && install_ai
$INSTALL_GUI        && install_gui

log_info ""
log_info "════════════════════════════════════════════════════════════════"
log_success "Done."
if $DRY_RUN; then
    log_info "Re-run without --dry-run to apply."
else
    log_info "Verify with:"
    log_info "  kubectl version --client && helm version --short"
    log_info "  k9s version && minikube version && tofu version"
    log_info "  huggingface-cli whoami  # (after first login)"
fi
