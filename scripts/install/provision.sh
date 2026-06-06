#!/usr/bin/env bash
################################################################################
# provision.sh — take a fresh macOS or Linux box to fully-configured in one pass.
#
#   claw provision              full provisioning
#   claw provision --dry-run    preview every step
#   claw provision --minimal    base + modern-cli + stow only (skip nextgen/agents)
#
# Idempotent: every step guards on what's already present. Orchestrates the
# existing install scripts + the tool manifest + the agentic harnesses, so a
# new homelab node ends up matching this repo's declared state in one command.
################################################################################
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
_U="$DOTFILES/scripts/utils"; _I="$DOTFILES/scripts/install"
# shellcheck source=/dev/null
source "$_U/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; log_skip(){ echo "· $*"; }; _section(){ echo "── $1 $2 ──"; }; _banner_basic(){ echo "$1"; }; c_white=''; c_dim=''; c_reset=''; }
# shellcheck source=/dev/null
source "$_U/detect-os.sh" 2>/dev/null && detect_os
: "${OS_TYPE:=$(uname -s)}"
if [[ -z "${PKG_MANAGER:-}" || "$PKG_MANAGER" == unknown ]]; then
    command -v brew &>/dev/null && PKG_MANAGER=brew || { command -v apt-get &>/dev/null && PKG_MANAGER=apt || PKG_MANAGER=unknown; }
fi
export USER="${USER:-$(id -un 2>/dev/null||echo user)}"

DRY=0; MINIMAL=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --minimal) MINIMAL=1;; esac; done
run() { if (( DRY )); then log_info "DRY: $*"; else "$@"; fi; }
have() { command -v "$1" &>/dev/null; }

_banner_basic "OPEN  CLAW  PROVISION" "FULL  BOX  SETUP" "fresh ${OS_TYPE} → fully configured in one pass"
log_info "platform: ${c_white}${OS_TYPE}/${PKG_MANAGER}${c_reset}$( ((DRY)) && echo '  (dry-run)'; ((MINIMAL)) && echo '  (minimal)')"

# ── 1. Package manager ──────────────────────────────────────────────────────
_section 1 "Package  Manager"
if [[ "$PKG_MANAGER" == brew ]] && ! have brew; then
    log_info "installing Homebrew..."
    (( DRY )) && log_info "DRY: install Homebrew via official script" || \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
elif [[ "$PKG_MANAGER" == apt ]]; then
    run sudo apt-get update -qq
else
    log_skip "$PKG_MANAGER ready"
fi

# ── 2. Base + modern CLI ────────────────────────────────────────────────────
_section 2 "Base  +  Modern  CLI"
if (( DRY )); then log_info "DRY: source packages/common.sh + modern-cli.sh"
else
    # shellcheck source=/dev/null
    [[ -f "$_I/packages/common.sh" ]]     && bash "$_I/packages/common.sh"     || log_warning "common.sh missing"
    [[ -f "$_I/packages/modern-cli.sh" ]] && bash "$_I/packages/modern-cli.sh" || log_warning "modern-cli.sh missing"
fi

# ── 3. Symlinks (stow) ──────────────────────────────────────────────────────
_section 3 "Dotfile  Symlinks"
run bash "$DOTFILES/scripts/setup/symlinks.sh"

if (( ! MINIMAL )); then
    # ── 4. Next-gen tool pack ───────────────────────────────────────────────
    _section 4 "Next-Gen  Tool  Pack"
    if (( DRY )); then DRY_RUN=1 bash "$_I/nextgen-toolchain.sh"; else bash "$_I/nextgen-toolchain.sh"; fi

    # ── 5. Manifest install (everything tracked, incl. your added tools) ─────
    _section 5 "Tracked  Tools  (manifest)"
    if (( DRY )); then log_info "DRY: pkg install all"; else bash "$_U/pkg-manifest.sh" install all; fi

    # ── 6. Agentic harnesses ────────────────────────────────────────────────
    _section 6 "Agentic  Harnesses"
    if have npm; then
        have claude || run npm install -g @anthropic-ai/claude-code
        have gemini || run npm install -g @google/gemini-cli
    else
        log_warning "npm absent — claude-code/gemini-cli need Node (installed via dev-tools)"
    fi
    if ! have ollama; then
        if [[ "$OS_TYPE" == macos ]]; then have brew && run brew install ollama
        else run sh -c "curl -fsSL https://ollama.com/install.sh | sh"; fi
    else log_skip "ollama present"; fi
    have aichat || { have brew && run brew install aichat || log_skip "aichat (brew only / cargo)"; }
    # Replay Claude Code state (skills/plugins/mcp) from the repo manifests.
    [[ -f "$_I/claude-sync.sh" ]] && { if (( DRY )); then log_info "DRY: claude-sync"; else CLAUDE_SYNC_DRY_RUN=$DRY bash "$_I/claude-sync.sh" || true; fi; }
fi

# ── 7. Fonts (Nerd Font — icons) ────────────────────────────────────────────
_section 7 "Nerd  Fonts"
if [[ "$OS_TYPE" == macos ]]; then
    have brew && run brew install --cask font-jetbrains-mono-nerd-font font-meslo-lg-nerd-font 2>/dev/null || true
else
    fdir="$HOME/.local/share/fonts"
    if ! ls "$fdir"/*NerdFont* &>/dev/null 2>&1; then
        run mkdir -p "$fdir"
        run sh -c "curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar xJ -C '$fdir'" || true
        run fc-cache -f "$fdir" 2>/dev/null || true
    else log_skip "Nerd Font present"; fi
fi

# ── 8. Integrity baseline ───────────────────────────────────────────────────
_section 8 "Integrity  Baseline"
[[ -f "$_U/integrity.sh" ]] && run bash "$_U/integrity.sh" generate || log_skip "integrity.sh absent"

printf "\n"
log_success "provisioning complete$( ((DRY)) && echo ' (dry-run — nothing changed)')"
log_info "next: ${c_white}exec zsh${c_reset}  ·  set terminal font to JetBrainsMono Nerd Font Mono  ·  ${c_white}claw doctor${c_reset}"
