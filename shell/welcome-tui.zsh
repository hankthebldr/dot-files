# shell/welcome-tui.zsh
# Interactive Open Claw Login Dashboard

function claw_welcome_tui() {
    # Check if we are running interactively
    if [[ ! -o interactive ]]; then
        return
    fi
    # Skip if a profile is already active to prevent infinite loop
    if [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then
        return
    fi

    # Use $DOTFILES_DIR set by exports.zsh (NOT $0 — $0 is the function name inside a function)
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

    # Render Dashboard Header via fastfetch with custom OPEN CLAW branding
    local ff_config="$_d/config/fastfetch/config.jsonc"
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
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(sw_vers -productName 2>/dev/null || echo 'System') $(sw_vers -productVersion 2>/dev/null) · $(uname -m)${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(date '+%a %b %d %H:%M') · $(ipconfig getifaddr en0 2>/dev/null || echo 'offline')${c_reset}"
        echo "  ${c_purple}│${c_reset}                                              ${c_purple}│${c_reset}"
        echo "  ${c_purple}╰──────────────────────────────────────────────╯${c_reset}"
    fi
    echo ""

    # Ensure fzf is installed to run the interactive menu
    if ! command -v fzf &> /dev/null; then
        echo "  ${c_dim}Launch modules skipped: 'fzf' is not installed.${c_reset}"
        return
    fi

    # Build Interactive Menu Choices
    # Entries: Value\tDisplay String
    local choices="skip\t${c_white}💻 Exit to Shell${c_reset}\n"
    choices+="default\t${c_cyan}⚙️  Default Profile${c_dim}  Standard Dev${c_reset}\n"
    choices+="security\t${c_pink}🔐 Security Profile${c_dim}  Pentesting & Scanners${c_reset}\n"
    choices+="cloud\t${c_cyan}☁️  Cloud Profile${c_dim}  AWS / K8s / Terraform${c_reset}\n"
    choices+="devops\t${c_green}🏗️  DevOps Profile${c_dim}  CI/CD / Monitoring / IaC${c_reset}\n"
    choices+="research\t${c_orange}🔬 Research Profile${c_dim}  Datasets & Scraping${c_reset}\n"
    choices+="ai\t${c_purple}🤖 AI Profile${c_dim}  LLMs / Embeddings / MLOps${c_reset}\n"
    choices+="cortex\t${c_pink}🛡️  Cortex Profile${c_dim}  XSOAR / XSIAM / PAN-OS${c_reset}\n"
    choices+="local\t${c_green}🛠️  Local Profile${c_dim}  Custom Built CLI Tools${c_reset}\n"
    choices+="homelab\t${c_orange}📡 HomeLab${c_dim}  Interactive SSH Manager${c_reset}\n"
    choices+="ai_tools\t${c_purple}🧠 AI Toolkit${c_dim}  Ollama / Claude / Aider / MCP${c_reset}\n"
    choices+="mcp\t${c_cyan}🔌 MCP Manager${c_dim}  Model Context Protocol${c_reset}\n"
    choices+="claude\t${c_orange}💻 Claude Code${c_reset}\n"
    choices+="tmux\t${c_green}🪟 TMUX${c_dim}  Attach or New Session${c_reset}\n"
    choices+="yazi\t${c_cyan}📂 Yazi${c_dim}  File Browser${c_reset}\n"
    choices+="update\t${c_yellow}🔧 System Update${c_dim}  Brew & NPM${c_reset}\n"
    choices+="doc\t${c_dim}📖 CLI Docs & Help${c_reset}\n"
    choices+="top\t${c_dim}📊 System Monitor${c_reset}\n"

    # Launch fzf menu
    local selection
    selection=$(echo -e "$choices" | column -s $'\t' -t | fzf \
        --height=18 --reverse --margin=0,0,0,4 \
        --prompt="▶ " \
        --header="  ↑/↓ navigate · ENTER select · ESC shell" \
        --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#bc8cff,hl+:#bc8cff" \
        --ansi \
        || echo "skip")

    # Extract just the lookup key from the selection line
    local key=$(echo "$selection" | awk '{print $1}')

    # Process choice directly into the shell session
    case "$key" in
        skip)
            # Default exit: do nothing, proceed to standard shell
            ;;
        default|security|cloud|devops|research|ai|cortex|local)
            export CLAW_ACTIVE_PROFILE="$key"
            echo "${c_cyan}Loading $key profile...${c_reset}"
            local _profile="$_d/shell/profiles/${key}.zsh"
            if [[ -f "$_profile" ]]; then
                source "$_profile"
            else
                echo "${c_red}Profile not found: $_profile${c_reset}"
            fi
            ;;
        homelab)
            if [[ -f "$_d/scripts/utils/homelab.sh" ]]; then
                "$_d/scripts/utils/homelab.sh"
            else
                echo "${c_red}Homelab connector not found.${c_reset}"
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
            # Fallback for empty or unrecognized input
            ;;
    esac
}

