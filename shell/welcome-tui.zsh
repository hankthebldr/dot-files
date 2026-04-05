# shell/welcome-tui.zsh
# Interactive Open Claw Login Dashboard

function claw_welcome_tui() {
    # SAFETY: Never run in non-interactive shells (breaks scp, rsync, git-over-ssh)
    [[ ! -o interactive ]] && return
    # SAFETY: Never run if stdin is not a terminal (piped input)
    [[ ! -t 0 ]] && return
    # SAFETY: Never run inside SSH that's piping data (e.g. scp, rsync)
    [[ -n "$SSH_CONNECTION" && ! -t 1 ]] && return
    # Skip if a profile is already active to prevent infinite loop
    [[ -n "$CLAW_ACTIVE_PROFILE" ]] && return

    # Use $DOTFILES_DIR set by .zshrc
    local _d="$DOTFILES_DIR"

    # Trigger background tool updater silently
    ( "$_d/scripts/utils/tool-updater.sh" ) &> /dev/null &

    # Modern GitHub macOS Dark Theme (True Colors)
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'    # GitHub Blue: #58a6ff
    local c_green=$'\e[38;2;63;185;80m'    # GitHub Green: #3fb950
    local c_pink=$'\e[38;2;255;123;114m'   # GitHub Red/Pink: #ff7b72
    local c_purple=$'\e[38;2;188;140;255m' # GitHub Purple: #bc8cff
    local c_orange=$'\e[38;2;210;153;34m'  # GitHub Orange/Gold: #d29922
    local c_yellow=$'\e[38;2;210;153;34m'  # GitHub Yellow (using gold)
    local c_dim=$'\e[38;2;139;148;158m'    # GitHub Muted: #8b949e
    local c_red=$'\e[38;2;255;123;114m'    # GitHub Red: #ff7b72
    local c_white=$'\e[38;2;201;209;217m'  # GitHub fg: #c9d1d9
    local c_bold=$'\e[1m'

    # Render Dashboard Header via fastfetch with custom OPEN CLAW branding
    local ff_config="$_d/config/.config/fastfetch/config.jsonc"
    if command -v fastfetch &> /dev/null && [[ -f "$ff_config" ]]; then
        echo ""
        fastfetch -c "$ff_config"
    else
        # Fallback: branded header if fastfetch is missing
        echo ""
        echo "  ${c_purple}╭──────────────────────────────────────────────╮${c_reset}"
        echo "  ${c_purple}│${c_reset}                                              ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_cyan}█▀█ █▀█ █▀▀ █▄░█   ${c_green}█▀▀ █░░ ▄▀█ █░█░█${c_reset}   ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_cyan}█▄█ █▀▀ ██▄ █░▀█   ${c_green}█▄▄ █▄▄ █▀█ ▀▄▀▄▀${c_reset}   ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}                                              ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(os_version 2>/dev/null || uname -sr) · $(uname -m)${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(date '+%a %b %d %H:%M') · $(local_ip 2>/dev/null)${c_reset}"
        echo "  ${c_purple}│${c_reset}                                              ${c_purple}│${c_reset}"
        echo "  ${c_purple}╰──────────────────────────────────────────────╯${c_reset}"
    fi
    echo ""

    # Ensure fzf is installed to run the interactive menu
    if ! command -v fzf &> /dev/null; then
        echo "  ${c_dim}Launch modules skipped: 'fzf' is not installed.${c_reset}"
        return
    fi

    # Build Interactive Menu Choices — grouped by category
    local choices=""

    # ── Daily Driver (top, highlighted) ──
    choices+="default\t${c_green}${c_bold}⚙️  Default Shell${c_reset}${c_dim}      Standard Dev · daily driver${c_reset}\n"

    # ── Workflow Profiles ──
    choices+="security\t${c_pink}🔐 Security${c_reset}${c_dim}           Pentesting · Scanners · OSINT${c_reset}\n"
    choices+="cloud\t${c_cyan}☁️  Cloud${c_reset}${c_dim}              AWS · K8s · Terraform${c_reset}\n"
    choices+="devops\t${c_green}🏗️  DevOps${c_reset}${c_dim}             CI/CD · Monitoring · IaC${c_reset}\n"
    choices+="ai\t${c_purple}🤖 AI${c_reset}${c_dim}                 LLMs · Embeddings · MLOps${c_reset}\n"
    choices+="research\t${c_orange}🔬 Research${c_reset}${c_dim}           Datasets · Scraping · NLP${c_reset}\n"
    choices+="cortex\t${c_pink}🛡️  Cortex${c_reset}${c_dim}             XSOAR · XSIAM · PAN-OS${c_reset}\n"
    choices+="local\t${c_green}🛠️  Local${c_reset}${c_dim}              Custom Built CLI Tools${c_reset}\n"

    # ── Tools ──
    choices+="─\t${c_dim}───────────────────────────────────────────────${c_reset}\n"
    choices+="homelab\t${c_orange}📡 HomeLab${c_reset}${c_dim}            SSH Topology Manager${c_reset}\n"
    choices+="tunnel\t${c_cyan}🔗 SSH Tunnels${c_reset}${c_dim}        Port Forwards · SOCKS${c_reset}\n"
    choices+="ai_tools\t${c_purple}🧠 AI Toolkit${c_reset}${c_dim}         Ollama · Claude · Aider${c_reset}\n"
    choices+="mcp\t${c_cyan}🔌 MCP Manager${c_reset}${c_dim}        Model Context Protocol${c_reset}\n"
    choices+="claude\t${c_orange}💻 Claude Code${c_reset}\n"

    # ── System ──
    choices+="─\t${c_dim}───────────────────────────────────────────────${c_reset}\n"
    choices+="tmux\t${c_green}🪟 TMUX${c_reset}${c_dim}               Attach or New Session${c_reset}\n"
    choices+="yazi\t${c_cyan}📂 Yazi${c_reset}${c_dim}               File Browser${c_reset}\n"
    choices+="update\t${c_yellow}🔧 System Update${c_reset}${c_dim}      Brew · NPM · Pip${c_reset}\n"
    choices+="doc\t${c_dim}📖 CLI Docs & Help${c_reset}\n"
    choices+="top\t${c_dim}📊 System Monitor${c_reset}\n"
    choices+="skip\t${c_white}↩  Shell${c_reset}${c_dim}              Exit to prompt${c_reset}\n"

    # Launch fzf menu
    local selection
    selection=$(echo -e "$choices" | column -s $'\t' -t | fzf \
        --height=24 --reverse --margin=0,0,0,4 \
        --prompt="▶ " \
        --header="  ENTER default · ↑/↓ navigate · ESC shell" \
        --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#bc8cff,hl+:#bc8cff" \
        --ansi \
        || echo "default")

    # Extract just the lookup key from the selection line
    local key=$(echo "$selection" | awk '{print $1}')

    # Separator lines are not selectable actions
    [[ "$key" == "─" ]] && key="default"
    # Empty = user pressed ESC with no override → default
    [[ -z "$key" ]] && key="default"

    # Process choice directly into the shell session
    case "$key" in
        skip)
            # Exit to bare shell — no profile loaded
            ;;
        default|security|cloud|devops|research|ai|cortex|local)
            export CLAW_ACTIVE_PROFILE="$key"
            local _profile="$_d/shell/profiles/${key}.zsh"
            if [[ -f "$_profile" ]]; then
                source "$_profile"
            else
                echo "${c_red}Profile not found: $_profile${c_reset}"
            fi
            # Display profile-specific fastfetch dashboard
            local _ff_profile="$_d/config/.config/fastfetch/config-${key}.jsonc"
            if command -v fastfetch &> /dev/null && [[ -f "$_ff_profile" ]]; then
                echo ""
                fastfetch -c "$_ff_profile"
            fi
            # Default profile: show quick-ref cheatsheet
            if [[ "$key" == "default" ]]; then
                _claw_default_quickref
            fi
            ;;
        homelab)
            if [[ -f "$_d/scripts/utils/homelab.sh" ]]; then
                "$_d/scripts/utils/homelab.sh"
            else
                echo "${c_red}Homelab connector not found.${c_reset}"
            fi
            ;;
        tunnel)
            if [[ -f "$_d/scripts/utils/tunnel-manager.sh" ]]; then
                "$_d/scripts/utils/tunnel-manager.sh"
            else
                echo "${c_red}Tunnel manager not found.${c_reset}"
            fi
            ;;
        ai_tools)
            echo "${c_purple}Opening AI Toolkit...${c_reset}"
            export TK_AUTO_START="8"
            "$_d/scripts/utils/toolkit.sh"
            ;;
        mcp)
            if [[ -f "$_d/scripts/utils/mcp-manager.sh" ]]; then
                "$_d/scripts/utils/mcp-manager.sh"
            else
                echo "${c_red}MCP Manager not found.${c_reset}"
            fi
            ;;
        claude)
            if command -v claude &> /dev/null; then claude; else echo "${c_red}Claude Code not found.${c_reset}"; fi
            ;;
        tmux)
            if command -v tmux &> /dev/null; then
                tmux attach 2>/dev/null || tmux new-session
            else
                echo "${c_red}tmux not installed.${c_reset}"
            fi
            ;;
        yazi)
            if command -v yazi &> /dev/null; then yazi; else echo "${c_red}Yazi not installed.${c_reset}"; fi
            ;;
        update)
            if [[ -f "$_d/scripts/utils/system-update.sh" ]]; then
                source "$_d/scripts/utils/system-update.sh"
            else
                echo "${c_dim}Running brew update & upgrade...${c_reset}"
                brew update && brew upgrade
            fi
            ;;
        doc)
            if [[ -f "$_d/scripts/utils/help.sh" ]]; then
                "$_d/scripts/utils/help.sh"
            else
                echo "${c_red}Help script not found.${c_reset}"
            fi
            ;;
        top)
            if command -v btop &> /dev/null; then btop; else top; fi
            ;;
        *)
            # Fallback: load default profile
            export CLAW_ACTIVE_PROFILE="default"
            [[ -f "$_d/shell/profiles/default.zsh" ]] && source "$_d/shell/profiles/default.zsh"
            ;;
    esac
}

# ============================================
# DEFAULT PROFILE QUICK-REFERENCE CHEATSHEET
# Displayed inline after default profile loads
# ============================================
_claw_default_quickref() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_orange=$'\e[38;2;210;153;34m'
    local c_red=$'\e[38;2;255;123;114m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}Daily Driver${c_reset}                          ${c_dim}type ${c_white}default-help${c_dim} for full ref${c_reset}  ${c_purple}│${c_reset}"
    echo "  ${c_purple}├──────────────────────────────────────────────────────────────────┤${c_reset}"
    echo "  ${c_purple}│${c_reset}                                                                  ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_green}${c_bold}Navigate${c_reset}    ${c_white}z${c_reset} ${c_dim}smart cd${c_reset}   ${c_white}Ctrl+R${c_reset} ${c_dim}history${c_reset}   ${c_white}Ctrl+T${c_reset} ${c_dim}find files${c_reset}     ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}Files${c_reset}       ${c_white}ls${c_reset} ${c_dim}eza${c_reset}  ${c_white}cat${c_reset} ${c_dim}bat${c_reset}  ${c_white}find${c_reset} ${c_dim}fd${c_reset}  ${c_white}grep${c_reset} ${c_dim}rg${c_reset}  ${c_white}diff${c_reset} ${c_dim}delta${c_reset}      ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_orange}${c_bold}Network${c_reset}     ${c_white}netcheck${c_reset} ${c_dim}diag${c_reset}  ${c_white}ports${c_reset} ${c_dim}listen${c_reset}  ${c_white}myip${c_reset}  ${c_white}dns${c_reset}  ${c_white}headers${c_reset}    ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_red}${c_bold}Tools${c_reset}       ${c_white}tun${c_reset} ${c_dim}tunnels${c_reset}  ${c_white}glg${c_reset} ${c_dim}lazygit${c_reset}  ${c_white}lzd${c_reset} ${c_dim}docker${c_reset}  ${c_white}fkill${c_reset}      ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_purple}${c_bold}System${c_reset}      ${c_white}top${c_reset} ${c_dim}btop${c_reset}  ${c_white}df${c_reset} ${c_dim}duf${c_reset}  ${c_white}du${c_reset} ${c_dim}dust${c_reset}  ${c_white}reload${c_reset}  ${c_white}update${c_reset}     ${c_purple}│${c_reset}"
    echo "  ${c_purple}│${c_reset}                                                                  ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}
