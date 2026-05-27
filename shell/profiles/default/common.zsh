# Default Profile
# Standard Developer Loadout — the base experience all other profiles extend
export CLAW_PROFILE_THEME="default"

# ==========================================
# QUICK REFERENCE HELP
# ==========================================
default-help() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_orange=$'\e[38;2;210;153;34m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    echo ""
    echo "  ${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}OPEN CLAW — Default Profile${c_reset}                          ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
    echo "  ${c_cyan}${c_bold}Navigation${c_reset}"
    echo "  ${c_white}z <dir>${c_reset}         ${c_dim}Smart cd (zoxide — learns your habits)${c_reset}"
    echo "  ${c_white}Ctrl+R${c_reset}          ${c_dim}Fuzzy history search (atuin)${c_reset}"
    echo "  ${c_white}Ctrl+T${c_reset}          ${c_dim}Fuzzy file finder (fzf)${c_reset}"
    echo "  ${c_white}Alt+C${c_reset}           ${c_dim}Fuzzy cd into subdirectory (fzf)${c_reset}"
    echo ""
    echo "  ${c_green}${c_bold}Modern CLI${c_reset}"
    echo "  ${c_white}ls/ll/la/lt${c_reset}     ${c_dim}eza with icons + git status${c_reset}"
    echo "  ${c_white}cat <file>${c_reset}       ${c_dim}bat with syntax highlighting${c_reset}"
    echo "  ${c_white}grep → rg${c_reset}        ${c_dim}ripgrep (faster, smarter)${c_reset}"
    echo "  ${c_white}find → fd${c_reset}        ${c_dim}fd (simpler syntax, respects .gitignore)${c_reset}"
    echo "  ${c_white}diff → delta${c_reset}     ${c_dim}Beautiful git diffs${c_reset}"
    echo "  ${c_white}top → btop${c_reset}       ${c_dim}Gorgeous system monitor${c_reset}"
    echo ""
    echo "  ${c_orange}${c_bold}Workflows${c_reset}"
    echo "  ${c_white}tun${c_reset}             ${c_dim}SSH Tunnel Manager${c_reset}"
    echo "  ${c_white}glg${c_reset}             ${c_dim}Lazygit TUI${c_reset}"
    echo "  ${c_white}lzd${c_reset}             ${c_dim}Lazydocker TUI${c_reset}"
    echo "  ${c_white}halp <cmd>${c_reset}       ${c_dim}TLDR simplified man pages${c_reset}"
    echo "  ${c_white}fkill${c_reset}           ${c_dim}Fuzzy process killer${c_reset}"
    echo "  ${c_white}dothelp${c_reset}         ${c_dim}Full Open Claw help system${c_reset}"
    echo ""
    echo "  ${c_purple}${c_bold}Profiles${c_reset}"
    echo "  ${c_dim}Switch profiles from the welcome TUI or:${c_reset}"
    echo "  ${c_white}export CLAW_ACTIVE_PROFILE=cloud && source ~/.zshrc${c_reset}"
    echo ""
    echo "  ${c_purple}${c_bold}AI agents${c_reset} ${c_dim}(via claw registry)${c_reset}"
    echo "  ${c_white}claw claude${c_reset}     ${c_dim}Anthropic Claude Code${c_reset}"
    echo "  ${c_white}claw gemini${c_reset}     ${c_dim}Google Gemini CLI${c_reset}"
    echo "  ${c_white}claw agent list${c_reset} ${c_dim}see all registered agents${c_reset}"
    echo ""
}

# ==========================================
# TOOL STATUS CHECK
# ==========================================
_default_tool_check() {
    local c_reset=$'\e[0m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_red=$'\e[38;2;255;123;114m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'

    local tools=(eza bat rg fd fzf zoxide atuin delta btop dust duf lazygit yazi glow tldr)
    local installed=0
    local total=${#tools[@]}

    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            ((installed++))
        fi
    done

    if ((installed == total)); then
        echo "  ${c_green}✓${c_reset} ${c_dim}All ${total} core tools installed${c_reset}"
    else
        echo "  ${c_dim}Tools: ${c_green}${installed}${c_dim}/${total} installed${c_reset}"
        for tool in "${tools[@]}"; do
            if ! command -v "$tool" &> /dev/null; then
                echo "    ${c_red}✗${c_reset} ${c_white}${tool}${c_reset} ${c_dim}— brew install ${tool}${c_reset}"
            fi
        done
    fi
}

# Profile banner handled by fastfetch (config-default.jsonc)
