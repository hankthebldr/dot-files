#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Uninstaller (soft scope)
# ============================================
# Reverses bootstrap.sh deployment without touching packages
# the user might still want (brew/apt tools, OMZ, P10k, fonts,
# default shell). Mirrors bootstrap's 9-step topology in reverse.
#
# Usage:
#   claw uninstall              # interactive, with confirmation
#   claw uninstall --dry-run    # preview only, no changes
#   claw uninstall --yes        # skip confirmation
#   claw uninstall --keep-backup  # don't restore from ~/.dotfiles-backup/
#   claw uninstall --help
#
# Scope (soft):
#   ✓ stow -D every module deployed by bootstrap step 8
#   ✓ remove ~/.dotfiles symlink (only if it IS a symlink)
#   ✓ remove ~/.config/claw, ~/.cache/claw (claw runtime state)
#   ✓ restore most-recent ~/.dotfiles-backup/<timestamp>/ files
#   ✗ KEEP brew/apt CLI packages (eza, bat, ripgrep, etc)
#   ✗ KEEP OMZ, Powerlevel10k, zsh-completions
#   ✗ KEEP Nerd Fonts
#   ✗ KEEP default shell setting (chsh not reverted)
#
# For more aggressive removal, run the printed manual commands.

set -e

# ── Source utilities ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Logger — load if available, fall back to plain printf so we never
# block uninstall just because the logger file moved.
if [[ -r "$SCRIPT_DIR/logger.sh" ]]; then
    source "$SCRIPT_DIR/logger.sh"
else
    log_info()    { printf '[INFO] %s\n' "$*"; }
    log_success() { printf '[OK]   %s\n' "$*"; }
    log_warning() { printf '[WARN] %s\n' "$*"; }
    log_error()   { printf '[ERR]  %s\n' "$*" >&2; }
fi

# ── Config ───────────────────────────────────────────────
DRY_RUN=false
ASSUME_YES=false
KEEP_BACKUP=false
BACKUP_ROOT="$HOME/.dotfiles-backup"

# Modules stow deployed (must match scripts/setup/symlinks.sh::MODULES)
MODULES=(shell git vim tmux terminal tools config)

# Files we know to restore from backup (must match bootstrap.sh step 2)
BACKUP_FILES=(.zshrc .gitconfig .tmux.conf .vimrc .p10k.zsh)

# Theme — kept inline so uninstall has zero external deps
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_orange=$'\e[38;2;227;179;65m'
c_red=$'\e[38;2;255;123;114m'
c_dim=$'\e[38;2;139;148;158m'
c_white=$'\e[38;2;201;209;217m'
c_bold=$'\e[1m'

# ── Arg parse ────────────────────────────────────────────
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --dry-run)      DRY_RUN=true ;;
        --yes|-y)       ASSUME_YES=true ;;
        --keep-backup)  KEEP_BACKUP=true ;;
        --help|-h)
            # Print only the top doc-block (comment lines up to the first
            # blank or non-comment line after the shebang).
            awk '
                NR == 1 && /^#!/ { next }
                /^# / { sub(/^# ?/, ""); print; next }
                /^#$/ { print ""; next }
                { exit }
            ' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *) log_error "Unknown flag: $1 (try --help)"; exit 1 ;;
    esac
    shift
done

# ── Helpers ──────────────────────────────────────────────
# Run a command unless --dry-run; in dry-run, just print it.
run() {
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "  %sDRY%s  %s\n" "$c_dim" "$c_reset" "$*"
    else
        eval "$@"
    fi
}

confirm() {
    [[ "$ASSUME_YES" == "true" ]] && return 0
    [[ "$DRY_RUN" == "true" ]]    && return 0
    printf "\n  ${c_orange}?${c_reset} %s ${c_dim}[y/N]${c_reset} " "$1"
    read -r reply
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}

print_header() {
    echo ""
    echo "  ${c_red}╭──────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_red}│${c_reset}                                                      ${c_red}│${c_reset}"
    echo "  ${c_red}│${c_reset}   ${c_red}█░█ █▄░█ █ █▄░█ █▀ ▀█▀ ▄▀█ █░░ █${c_reset}                  ${c_red}│${c_reset}"
    echo "  ${c_red}│${c_reset}   ${c_red}█▄█ █░▀█ █ █░▀█ ▄█ ░█░ █▀█ █▄▄ █${c_reset}                  ${c_red}│${c_reset}"
    echo "  ${c_red}│${c_reset}                                                      ${c_red}│${c_reset}"
    echo "  ${c_red}│${c_reset}   ${c_white}${c_bold}OPEN CLAW Uninstaller${c_reset}  ${c_dim}soft scope${c_reset}                ${c_red}│${c_reset}"
    if [[ "$DRY_RUN" == "true" ]]; then
    echo "  ${c_red}│${c_reset}   ${c_orange}DRY RUN — no changes will be made${c_reset}                  ${c_red}│${c_reset}"
    fi
    echo "  ${c_red}│${c_reset}                                                      ${c_red}│${c_reset}"
    echo "  ${c_red}╰──────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}

# Find newest ~/.dotfiles-backup/<timestamp>/ that contains <file>.
# Returns path or empty. Portable: avoids -printf (GNU-only) and parses
# timestamp from the directory name itself (which bootstrap writes as
# YYYYMMDD-HHMMSS — string-sorts correctly).
newest_backup_of() {
    local file="$1"
    [[ ! -d "$BACKUP_ROOT" ]] && return 0
    # find directories named like timestamps, sort descending, take first
    # that contains the file
    local d
    while IFS= read -r d; do
        if [[ -f "$d/$file" ]]; then
            printf '%s' "$d/$file"
            return 0
        fi
    done < <(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
                  -name '[0-9]*-[0-9]*' 2>/dev/null | sort -r)
}

# ── Steps (reverse of bootstrap) ─────────────────────────

# Step R1: Stow -D every module
step_unlink_stow() {
    log_info "Step 1/4 — un-stowing modules"
    if ! command -v stow &>/dev/null; then
        log_warning "GNU stow not on PATH — skipping module unlink"
        log_warning "(install stow if you need this step; symlinks will remain)"
        return 0
    fi
    if [[ ! -d "$REPO_ROOT" ]]; then
        log_error "Cannot locate repo root at $REPO_ROOT"
        return 1
    fi
    local removed=0
    for module in "${MODULES[@]}"; do
        if [[ -d "$REPO_ROOT/$module" ]]; then
            # stow -D = delete (only removes symlinks pointing into the module)
            # -v: verbose so the user can see what came down
            if run "stow -D -d '$REPO_ROOT' -t '$HOME' '$module' 2>&1 | sed 's/^/    /'"; then
                log_success "unstowed $module"
                # arithmetic assignment, NOT ((removed++)): under `set -e` the
                # post-increment returns the OLD value (0 on the first module) →
                # exit 1 → script aborts after one module (half-uninstall).
                removed=$((removed + 1))
            else
                log_warning "stow -D failed for $module (may have been manually modified)"
            fi
        fi
    done
    log_info "  ${c_dim}${removed}/${#MODULES[@]} modules unlinked${c_reset}"
}

# Step R2: Restore from most-recent backup
step_restore_backup() {
    if [[ "$KEEP_BACKUP" == "true" ]]; then
        log_info "Step 2/4 — backup restore ${c_dim}(skipped: --keep-backup)${c_reset}"
        return 0
    fi
    log_info "Step 2/4 — restoring pre-install configs from $BACKUP_ROOT"
    if [[ ! -d "$BACKUP_ROOT" ]]; then
        log_info "  ${c_dim}no backup directory found — nothing to restore${c_reset}"
        return 0
    fi
    local restored=0
    for f in "${BACKUP_FILES[@]}"; do
        local src
        src=$(newest_backup_of "$f")
        if [[ -n "$src" ]]; then
            # If target is still a symlink (stow -D should have removed
            # it, but be defensive), drop it before copying.
            if [[ -L "$HOME/$f" ]]; then
                run "rm '$HOME/$f'"
            fi
            run "cp -p '$src' '$HOME/$f'"
            log_success "restored $f ${c_dim}(from $(basename "$(dirname "$src")"))${c_reset}"
            restored=$((restored + 1))   # set -e-safe (see unstow loop above)
        fi
    done
    if (( restored == 0 )); then
        log_info "  ${c_dim}no matching backup files found — fresh-state install${c_reset}"
    fi
}

# Step R3: Remove ~/.dotfiles symlink (NEVER touch a real directory)
step_unlink_dotfiles() {
    log_info "Step 3/4 — removing ~/.dotfiles symlink"
    if [[ -L "$HOME/.dotfiles" ]]; then
        local target
        target=$(readlink "$HOME/.dotfiles")
        run "rm '$HOME/.dotfiles'"
        log_success "removed symlink ${c_dim}(was → $target)${c_reset}"
    elif [[ -d "$HOME/.dotfiles" ]]; then
        log_warning "~/.dotfiles is a real directory, not a symlink — leaving it alone"
        log_warning "(the actual repo lives there; remove manually if intentional)"
    else
        log_info "  ${c_dim}~/.dotfiles already absent${c_reset}"
    fi
}

# Step R4: Wipe claw runtime state
step_remove_claw_state() {
    log_info "Step 4/4 — removing claw runtime state"
    local paths=(
        "${XDG_CONFIG_HOME:-$HOME/.config}/claw"
        "${XDG_CACHE_HOME:-$HOME/.cache}/claw"
    )
    for p in "${paths[@]}"; do
        if [[ -e "$p" ]]; then
            run "rm -rf '$p'"
            log_success "removed $p"
        fi
    done
    # Integrity manifest the user can choose to keep or not. Living
    # inside the repo, it's already gone if they later `rm -rf` the
    # repo; we don't touch it here.
}

print_summary() {
    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}   ${c_green}✓${c_reset}  OPEN CLAW uninstalled ${c_dim}(soft scope)${c_reset}              ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"
    echo ""
    echo "  ${c_cyan}${c_bold}What was kept${c_reset} ${c_dim}(intentionally — run these manually to remove)${c_reset}"
    echo ""
    echo "    ${c_dim}# CLI packages (you may still want these)${c_reset}"
    echo "    ${c_white}brew uninstall eza zoxide atuin btop lazygit lazydocker git-delta dust duf procs glow fastfetch vivid gum${c_reset}"
    echo ""
    echo "    ${c_dim}# Oh-My-Zsh + Powerlevel10k${c_reset}"
    echo "    ${c_white}rm -rf ~/.oh-my-zsh ~/.p10k.zsh${c_reset}"
    echo ""
    echo "    ${c_dim}# Default shell back to bash${c_reset}"
    echo "    ${c_white}chsh -s /bin/bash${c_reset}"
    echo ""
    echo "    ${c_dim}# Backup tree (keeps your pre-install configs around just in case)${c_reset}"
    echo "    ${c_white}rm -rf ~/.dotfiles-backup${c_reset}"
    echo ""
    echo "    ${c_dim}# The repo itself${c_reset}"
    printf "    ${c_white}rm -rf %s${c_reset}\n" "$REPO_ROOT"
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "  ${c_orange}(dry-run — re-run without --dry-run to apply)${c_reset}"
        echo ""
    else
        echo "  ${c_dim}Restart your shell to pick up the cleaned environment: ${c_white}exec \$SHELL${c_reset}"
        echo ""
    fi
}

# ── Main ─────────────────────────────────────────────────
print_header

log_info "Repo root:    ${c_dim}$REPO_ROOT${c_reset}"
log_info "Dotfiles link: ${c_dim}$HOME/.dotfiles${c_reset}"
log_info "Backup root:   ${c_dim}$BACKUP_ROOT${c_reset}"
log_info "Modules:       ${c_dim}${MODULES[*]}${c_reset}"
echo ""

if ! confirm "Proceed with soft uninstall?"; then
    log_warning "Aborted by user — nothing was changed"
    exit 0
fi

step_unlink_stow
echo ""
step_restore_backup
echo ""
step_unlink_dotfiles
echo ""
step_remove_claw_state

print_summary
