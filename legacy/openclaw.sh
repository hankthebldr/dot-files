#!/usr/bin/env bash
# scripts/utils/openclaw.sh
# Open Claw — Central configuration and management command
# Usage: openclaw [command]

set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

# Theme
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_orange=$'\e[38;2;227;179;65m'
c_red=$'\e[38;2;255;123;114m'
c_dim=$'\e[38;2;139;148;158m'
c_white=$'\e[38;2;201;209;217m'
c_bold=$'\e[1m'

# ── Commands ─────────────────────────────────────────────

cmd_status() {
    echo ""
    echo "  ${c_purple}${c_bold}Open Claw Status${c_reset}"
    echo "  ${c_dim}──────────────────────────────────────────${c_reset}"
    printf "  %-18s %s\n" "Dotfiles:" "${c_cyan}$DOTFILES_DIR${c_reset}"
    printf "  %-18s %s\n" "Profile:" "${c_green}${CLAW_ACTIVE_PROFILE:-none}${c_reset}"
    printf "  %-18s %s\n" "Shell:" "${c_white}$(basename "$SHELL")${c_reset}"
    printf "  %-18s %s\n" "Editor:" "${c_white}${EDITOR:-vim}${c_reset}"
    printf "  %-18s %s\n" "OS:" "${c_white}${CLAW_OS:-$(uname -s)}${c_reset}"
    printf "  %-18s %s\n" "Brew prefix:" "${c_white}${HOMEBREW_PREFIX:-n/a}${c_reset}"
    echo ""

    echo "  ${c_purple}${c_bold}Installed Tools${c_reset}"
    echo "  ${c_dim}──────────────────────────────────────────${c_reset}"
    local tools=(fastfetch fzf eza bat rg fd zoxide atuin btop gum yq jq lazygit nvim claude)
    local installed=0
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            printf "  ${c_green}●${c_reset} %-14s ${c_dim}%s${c_reset}\n" "$tool" "$(command -v "$tool")"
            ((installed++))
        else
            printf "  ${c_red}○${c_reset} %-14s ${c_dim}not found${c_reset}\n" "$tool"
        fi
    done
    echo ""
    echo "  ${c_dim}${installed}/${#tools[@]} tools installed${c_reset}"
    echo ""
}

cmd_profiles() {
    echo ""
    echo "  ${c_purple}${c_bold}Available Profiles${c_reset}"
    echo "  ${c_dim}──────────────────────────────────────────${c_reset}"
    local active="${CLAW_ACTIVE_PROFILE:-none}"
    for profile in default security cloud devops ai research cortex claude local; do
        local pfile="$DOTFILES_DIR/shell/profiles/${profile}.zsh"
        if [[ -f "$pfile" ]]; then
            if [[ "$profile" == "$active" ]]; then
                printf "  ${c_green}▶ %-12s${c_reset} ${c_green}active${c_reset}\n" "$profile"
            else
                printf "  ${c_dim}  %-12s${c_reset} ${c_dim}available${c_reset}\n" "$profile"
            fi
        fi
    done
    echo ""
    echo "  ${c_dim}Switch: ${c_white}claw <profile>${c_reset}"
    echo ""
}

cmd_update() {
    echo ""
    echo "  ${c_cyan}Updating Open Claw...${c_reset}"
    cd "$DOTFILES_DIR"
    git pull --rebase
    echo "  ${c_green}✓ Updated to latest${c_reset}"
    echo ""
    echo "  ${c_dim}Reload shell: ${c_white}reload${c_reset}"
    echo ""
}

cmd_doctor() {
    echo ""
    echo "  ${c_purple}${c_bold}Open Claw Doctor${c_reset}"
    echo "  ${c_dim}──────────────────────────────────────────${c_reset}"
    local issues=0

    # Check symlink
    if [[ -L "$HOME/.dotfiles" ]]; then
        printf "  ${c_green}✓${c_reset} ~/.dotfiles symlink OK\n"
    elif [[ -d "$HOME/.dotfiles" ]]; then
        printf "  ${c_green}✓${c_reset} ~/.dotfiles directory exists\n"
    else
        printf "  ${c_red}✗${c_reset} ~/.dotfiles missing\n"
        ((issues++))
    fi

    # Check .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "DOTFILES_DIR" "$HOME/.zshrc"; then
            printf "  ${c_green}✓${c_reset} ~/.zshrc sources Open Claw\n"
        else
            printf "  ${c_red}✗${c_reset} ~/.zshrc does not source Open Claw\n"
            ((issues++))
        fi
    else
        printf "  ${c_red}✗${c_reset} ~/.zshrc missing\n"
        ((issues++))
    fi

    # Check OMZ
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        printf "  ${c_green}✓${c_reset} Oh-My-Zsh installed\n"
    else
        printf "  ${c_orange}!${c_reset} Oh-My-Zsh not installed (optional)\n"
    fi

    # Check p10k
    if [[ -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
        printf "  ${c_green}✓${c_reset} Powerlevel10k installed\n"
    else
        printf "  ${c_orange}!${c_reset} Powerlevel10k not installed (optional)\n"
    fi

    # Check brew
    if command -v brew &>/dev/null; then
        printf "  ${c_green}✓${c_reset} Homebrew at ${HOMEBREW_PREFIX:-unknown}\n"
    else
        printf "  ${c_red}✗${c_reset} Homebrew not installed\n"
        ((issues++))
    fi

    # Check zsh is default
    if [[ "$SHELL" == *"zsh"* ]]; then
        printf "  ${c_green}✓${c_reset} Default shell is zsh\n"
    else
        printf "  ${c_orange}!${c_reset} Default shell is $SHELL (expected zsh)\n"
    fi

    # Check fonts
    if [[ -d "$HOME/.local/share/fonts" ]] || ls ~/Library/Fonts/*Nerd* &>/dev/null 2>&1; then
        printf "  ${c_green}✓${c_reset} Nerd Fonts detected\n"
    else
        printf "  ${c_orange}!${c_reset} Nerd Fonts not found (icons may not render)\n"
    fi

    # Check platform.zsh
    if [[ -f "$DOTFILES_DIR/shell/platform.zsh" ]]; then
        printf "  ${c_green}✓${c_reset} platform.zsh (cross-platform shims)\n"
    else
        printf "  ${c_red}✗${c_reset} platform.zsh missing\n"
        ((issues++))
    fi

    echo ""
    if ((issues == 0)); then
        echo "  ${c_green}${c_bold}No issues found.${c_reset}"
    else
        echo "  ${c_red}${c_bold}${issues} issue(s) found.${c_reset} Run ${c_white}bootstrap.sh${c_reset} to fix."
    fi
    echo ""
}

cmd_edit() {
    local target="${1:-}"
    case "$target" in
        zshrc)    ${EDITOR:-vim} "$HOME/.zshrc" ;;
        aliases)  ${EDITOR:-vim} "$DOTFILES_DIR/shell/aliases.zsh" ;;
        exports)  ${EDITOR:-vim} "$DOTFILES_DIR/shell/exports.zsh" ;;
        profile)  ${EDITOR:-vim} "$DOTFILES_DIR/shell/profiles/${CLAW_ACTIVE_PROFILE:-default}.zsh" ;;
        tmux)     ${EDITOR:-vim} "$HOME/.tmux.conf" ;;
        git)      ${EDITOR:-vim} "$HOME/.gitconfig" ;;
        nvim)     ${EDITOR:-vim} "$HOME/.config/nvim/init.lua" ;;
        ssh)      ${EDITOR:-vim} "$HOME/.ssh/config" ;;
        tunnels)  ${EDITOR:-vim} "$DOTFILES_DIR/config/ssh/tunnels.yml" ;;
        claude)   ${EDITOR:-vim} "CLAUDE.md" ;;
        *)
            echo "  Usage: openclaw edit <target>"
            echo "  Targets: zshrc aliases exports profile tmux git nvim ssh tunnels claude"
            ;;
    esac
}

cmd_help() {
    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}openclaw${c_reset} — Open Claw Management                    ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"
    echo ""
    echo "  ${c_green}${c_bold}Commands${c_reset}"
    echo "  ${c_white}openclaw status${c_reset}        ${c_dim}Show dotfiles status + installed tools${c_reset}"
    echo "  ${c_white}openclaw profiles${c_reset}      ${c_dim}List available profiles${c_reset}"
    echo "  ${c_white}openclaw doctor${c_reset}        ${c_dim}Check system health + diagnose issues${c_reset}"
    echo "  ${c_white}openclaw update${c_reset}        ${c_dim}Pull latest from git${c_reset}"
    echo "  ${c_white}openclaw edit <file>${c_reset}   ${c_dim}Edit config (zshrc aliases exports profile tmux git nvim ssh tunnels claude)${c_reset}"
    echo "  ${c_white}openclaw install${c_reset}       ${c_dim}Run bootstrap.sh${c_reset}"
    echo "  ${c_white}openclaw help${c_reset}          ${c_dim}This help${c_reset}"
    echo ""
}

# ── Entry Point ──────────────────────────────────────────
case "${1:-help}" in
    status)   cmd_status ;;
    profiles) cmd_profiles ;;
    doctor)   cmd_doctor ;;
    update)   cmd_update ;;
    edit)     shift; cmd_edit "$@" ;;
    install)  exec bash "$DOTFILES_DIR/bootstrap.sh" "${@:2}" ;;
    help|--help|-h) cmd_help ;;
    *)        echo "  Unknown command: $1"; cmd_help ;;
esac
