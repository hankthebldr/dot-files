#!/usr/bin/env bash
# scripts/utils/system-update.sh
# THE package engine behind `claw update` (spine: one updater front door).
# Topgrade-first: when topgrade is installed the entire run is ONE streamed
# step driving the repo's declarative config (config/topgrade.toml). The
# hand-rolled sweep below survives only as the no-topgrade fallback.
# Streams every step live (stream + collapse-on-success) via claw-progress.sh.
# Design: docs/superpowers/specs/2026-08-17-claw-update-one-engine-design.md
#
#   argv:  --non-interactive   timer path — no clear, no end-of-run pause
#          --dry-run           preview only: topgrade gets -n, the sweep
#                              prints its step plan without executing
#   env:   CLAW_UPDATE_TRIGGER receipt trigger column (default: manual)
#   exit:  0 = every step ok · ≠0 = at least one step failed
#
# Every run appends one receipt row to ~/.cache/claw/updates.tsv:
#   ISO-ts <TAB> trigger <TAB> duration_s <TAB> ok|fail <TAB> detail

# Theme engine (CLAW_RGB_*) + streaming progress chrome (single render path).
source "$(dirname "${BASH_SOURCE[0]}")/theme.sh" 2>/dev/null || true
source "$(dirname "${BASH_SOURCE[0]}")/claw-progress.sh"

DOTFILES="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
RECEIPTS="$CACHE_DIR/updates.tsv"

# ============================================
# CLI / ENV
# ============================================
INTERACTIVE=1
DRY_RUN=0
for _arg in "$@"; do
    case "$_arg" in
        --non-interactive) INTERACTIVE=0 ;;
        --dry-run)         DRY_RUN=1 ;;
    esac
done
# The clear predates the phased front door: bin/claw sets CLAW_UPDATE_PHASED=1
# on the default repo→packages run so phase 2 never wipes phase 1's repo-sync
# report (dirty-tree warnings, pulled SHAs) off the screen.
[[ $INTERACTIVE -eq 1 && -z "${CLAW_UPDATE_PHASED:-}" ]] && clear

# ============================================
# RECEIPT
# ============================================
# One TSV row per run (design contract):
#   ISO-ts <TAB> trigger <TAB> duration_s <TAB> ok|fail <TAB> detail
write_receipt() {  # write_receipt <ok|fail> <detail>
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "${CLAW_UPDATE_TRIGGER:-manual}" \
        "$SECONDS" "$1" "$2" >> "$RECEIPTS" 2>/dev/null || true
}

# finish <detail> — footer + receipt + pause, then the exit-code contract:
# 0 only when every step succeeded.
finish() {
    local result=ok
    (( _CLAW_PROG_FAIL > 0 )) && result=fail
    if [[ "$result" == fail ]]; then
        claw_ui_footer "Update finished with failures"
    elif [[ $DRY_RUN -eq 1 ]]; then
        claw_ui_footer "Dry run complete — nothing executed"
    else
        claw_ui_footer "Update complete"
    fi
    write_receipt "$result" "$1"
    claw_ui_pause
    if [[ "$result" == ok ]]; then exit 0; else exit 1; fi
}

# ============================================
# TOPGRADE — the one engine (declarative, streamed)
# ============================================
# One streamed step covers every ecosystem topgrade detects; the repo config
# keeps it conservative (each disable is justified in config/topgrade.toml).
if command -v topgrade &>/dev/null; then
    tg_sub="topgrade engine — config/topgrade.toml"
    [[ $DRY_RUN -eq 1 ]] && tg_sub="Dry run — ${tg_sub}"
    claw_ui_header "🔄 SYSTEM UPDATE" "$tg_sub"
    tg_args=(--config "$DOTFILES/config/topgrade.toml" -y)
    [[ $DRY_RUN -eq 1 ]] && tg_args+=(-n)   # topgrade prints its own plan
    claw_step "Running topgrade across all ecosystems..." -- topgrade "${tg_args[@]}"
    _detail="engine=topgrade"
    [[ $DRY_RUN -eq 1 ]] && _detail="${_detail} dry_run=1"
    finish "$_detail"
fi

# ============================================
# FALLBACK SWEEP (topgrade not installed)
# ============================================
SWEEP_STEPS=0

# run_step "<label>" "<command>" — claw_step normally; under --dry-run print
# the planned step as a dim claw_ui_skip-style row and execute nothing.
run_step() {
    SWEEP_STEPS=$(( SWEEP_STEPS + 1 ))
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '  %s%s %s — %s%s\n' "$(_c muted)" "$(_claw_glyph arrow)" "$1" "$2" "$(_creset)"
        return 0
    fi
    claw_step "$1" -- bash -c "$2"
}

count_managers() {
    local count=0
    for cmd in brew apt-get dnf pacman snap flatpak npm yarn pnpm uv pipx pip3 gem rustup go; do
        command -v "$cmd" &>/dev/null && ((count++))
    done
    echo "$count"
}

# Sudo upfront: the first apt/dnf step used to stall mid-stream on a password
# prompt. Validate the ticket once before any step and keep it warm; the
# keepalive is killed by the EXIT trap so it can never outlive the run.
# Non-interactive runs (weekly timer) have no tty for a password: only a
# cached/NOPASSWD ticket (`sudo -n`) counts, and without one SUDO_READY=0 —
# the sudo-needing sections below are then skipped with a dim note instead of
# every step dying on the missing tty and crit-alerting the timer weekly.
SUDO_KEEPALIVE_PID=""
SUDO_READY=1
sweep_sudo_cleanup() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
    return 0
}
sweep_sudo_prime() {
    local m need=0
    for m in apt-get dnf pacman snap; do
        command -v "$m" &>/dev/null && { need=1; break; }
    done
    [[ $need -eq 1 && $DRY_RUN -eq 0 ]] || return 0
    command -v sudo &>/dev/null || return 0
    if [[ $INTERACTIVE -eq 0 ]]; then
        sudo -n true 2>/dev/null || { SUDO_READY=0; return 0; }
    else
        sudo -v || return 0
    fi
    ( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
    trap 'sweep_sudo_cleanup' EXIT
}

# skip_sudo <manager> — the dim no-ticket note (claw_ui_skip styling)
skip_sudo() {
    printf '  %s%s %s — skipped, sudo needs a password and there is no tty (run: claw update --packages)%s\n' \
        "$(_c muted)" "$(_claw_glyph skip)" "$1" "$(_creset)"
    _CLAW_PROG_SKIP=$(( _CLAW_PROG_SKIP + 1 ))
}

# ============================================
# HEADER
# ============================================
total=$(count_managers)
subtitle="Updating ${total} package managers across all ecosystems"
[[ $DRY_RUN -eq 1 ]] && subtitle="Dry run — planned steps for ${total} package managers"
claw_ui_header "🔄 SYSTEM UPDATE" "$subtitle"
sweep_sudo_prime

# ============================================
# 0. SYSTEM PACKAGES (Linux only — apt / dnf / pacman)
# ============================================
# Foundational layer — runs before brew so kernel/libc/etc come up first.
# `apt update` is verbose by default; claw_step streams + collapses it.
if command -v apt-get &>/dev/null; then
    claw_ui_section "APT (system)"
    if [[ $SUDO_READY -eq 1 ]]; then
        run_step "Refreshing apt cache..." "sudo apt-get update -qq"
        run_step "Upgrading apt packages..." "sudo apt-get upgrade -y"
        run_step "Removing obsolete packages..." "sudo apt-get autoremove -y"
        run_step "Cleaning apt archives..." "sudo apt-get autoclean -y"
    else
        skip_sudo "apt"
    fi
elif command -v dnf &>/dev/null; then
    claw_ui_section "DNF (system)"
    if [[ $SUDO_READY -eq 1 ]]; then
        run_step "Upgrading dnf packages..." "sudo dnf upgrade -y"
        run_step "Removing orphans..." "sudo dnf autoremove -y"
    else
        skip_sudo "dnf"
    fi
elif command -v pacman &>/dev/null; then
    claw_ui_section "Pacman (system)"
    if [[ $SUDO_READY -eq 1 ]]; then
        run_step "Syncing pacman..." "sudo pacman -Syu --noconfirm"
    else
        skip_sudo "pacman"
    fi
fi

# Snap (Ubuntu, some Debian)
if command -v snap &>/dev/null; then
    claw_ui_section "Snap"
    if [[ $SUDO_READY -eq 1 ]]; then
        run_step "Refreshing snap packages..." "sudo snap refresh"
    else
        skip_sudo "snap"
    fi
fi

# Flatpak (Fedora, some Ubuntu)
if command -v flatpak &>/dev/null; then
    claw_ui_section "Flatpak"
    run_step "Updating flatpak packages..." "flatpak update -y --noninteractive"
fi

# Firmware updates (Linux laptops/desktops with fwupd)
if command -v fwupdmgr &>/dev/null; then
    claw_ui_section "Firmware"
    run_step "Refreshing fwupd metadata..." "fwupdmgr refresh --force 2>/dev/null || true"
    run_step "Applying firmware updates..." "fwupdmgr update -y 2>/dev/null || true"
fi

# ============================================
# 1. HOMEBREW (macOS + Linuxbrew)
# ============================================
claw_ui_section "Homebrew"
if command -v brew &>/dev/null; then
    run_step "Updating Homebrew formulae index..." "brew update"
    run_step "Upgrading outdated packages..." "brew upgrade"
    run_step "Cleaning up old versions..." "brew cleanup --prune=7"
else
    claw_ui_skip "brew"
fi

# ============================================
# 2. NODE.JS
# ============================================
claw_ui_section "Node.js"
if command -v npm &>/dev/null; then
    run_step "Updating global npm packages..." "npm update -g"
else
    claw_ui_skip "npm"
fi
if command -v yarn &>/dev/null; then
    run_step "Updating global yarn packages..." "yarn global upgrade"
else
    claw_ui_skip "yarn"
fi
if command -v pnpm &>/dev/null; then
    run_step "Updating global pnpm packages..." "pnpm update -g"
else
    claw_ui_skip "pnpm"
fi

# ============================================
# 3. PYTHON
# ============================================
claw_ui_section "Python"
if command -v uv &>/dev/null; then
    run_step "Updating uv itself..." "uv self update"
    run_step "Upgrading uv-managed tools..." "uv tool upgrade --all 2>/dev/null || true"
else
    claw_ui_skip "uv"
fi
if command -v pipx &>/dev/null; then
    run_step "Upgrading pipx tools..." "pipx upgrade-all"
else
    claw_ui_skip "pipx"
fi
if command -v pip3 &>/dev/null; then
    run_step "Upgrading pip itself..." "python3 -m pip install --upgrade pip"
else
    claw_ui_skip "pip3"
fi

# ============================================
# 4. RUBY
# ============================================
claw_ui_section "Ruby"
if command -v gem &>/dev/null; then
    # Updates installed user gems (incl. colorls). The old `--system` bump
    # only refreshed RubyGems itself and never touched a single gem.
    run_step "Updating installed gems..." "gem update"
else
    claw_ui_skip "gem"
fi

# ============================================
# 5. RUST
# ============================================
claw_ui_section "Rust"
if command -v rustup &>/dev/null; then
    run_step "Updating Rust toolchains..." "rustup update"
else
    claw_ui_skip "rustup"
fi

# ============================================
# 6. GO
# ============================================
claw_ui_section "Go"
if command -v go &>/dev/null; then
    # No update step on purpose: the go binary is brew/system-managed, and the
    # old modcache wipe deleted a cache instead of updating anything.
    printf "  %s○ Go toolchain managed by brew/system package manager%s\n" "$(_c muted)" "$(_creset)"
else
    claw_ui_skip "go"
fi

# ============================================
# 7. SHELL
# ============================================
claw_ui_section "Shell"
if [[ -d "$HOME/.oh-my-zsh" ]] && command -v omz &>/dev/null; then
    run_step "Updating Oh My Zsh..." "omz update --unattended 2>/dev/null"
else
    claw_ui_skip "Oh My Zsh"
fi

# ============================================
# DONE
# ============================================
_detail="engine=sweep steps=${SWEEP_STEPS} fail=${_CLAW_PROG_FAIL}"
[[ $SUDO_READY -eq 0 ]] && _detail="${_detail} sudo=skipped"
[[ $DRY_RUN -eq 1 ]] && _detail="${_detail} dry_run=1"
finish "$_detail"
