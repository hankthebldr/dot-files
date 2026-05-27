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

    # Append-only TUI event logger. Matches the TSV schema used by bin/claw
    # (timestamp \t event \t arg_count \t profile). Errors swallowed so a
    # broken log can never break login. Disable with CLAW_NO_LOG=1.
    _claw_tui_log() {
        [[ "$CLAW_NO_LOG" = "1" ]] && return 0
        local _cache="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
        {
            mkdir -p "$_cache" 2>/dev/null
            printf '%s\t%s\t%s\t%s\n' \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                "tui:${1:-unknown}" \
                "0" \
                "${CLAW_ACTIVE_PROFILE:-none}" \
                >> "$_cache/usage.tsv"
        } 2>/dev/null || true
    }
    _claw_tui_log fire

    # Trigger background tool updater silently.
    # NOTE: `&!` is zsh's background-and-disown — it prevents the `[N] + done`
    # job-control notification from bleeding over the fastfetch logo when the
    # wrapper subshell exits a few ms later (the script itself self-backgrounds).
    "$_d/scripts/utils/tool-updater.sh" &>/dev/null &!

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

    # Clean slate — TUI owns the full terminal
    clear

    # Render Dashboard Header via fastfetch with native OS logo
    local ff_config="$_d/config/.config/fastfetch/config.jsonc"
    if command -v fastfetch &> /dev/null && [[ -f "$ff_config" ]]; then
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

    # ── Tier 1: Daily Driver ──
    choices+="default\t${c_green}${c_bold}⚙️  Default Shell${c_reset}${c_dim}      Standard Dev · daily driver${c_reset}\n"
    choices+="local\t${c_green}🛠️  Local${c_reset}${c_dim}              Custom Built CLI Tools${c_reset}\n"

    # ── Tier 2: Domain Expertise ──
    choices+="─\t${c_dim}── domain expertise ──────────────────────────${c_reset}\n"
    choices+="cloud\t${c_cyan}☁️  Cloud${c_reset}${c_dim}              AWS · K8s · Terraform · SKYSURFER${c_reset}\n"
    choices+="devops\t${c_green}🏗️  DevOps${c_reset}${c_dim}             CI/CD · Monitoring · IaC · WRENCH-MAGE${c_reset}\n"
    choices+="security\t${c_pink}🔐 Security${c_reset}${c_dim}           Pentest · OSINT · Forensics · NIGHTHACKER${c_reset}\n"
    choices+="cortex\t${c_pink}🛡️  Cortex${c_reset}${c_dim}             XSOAR · XSIAM · PAN-OS · GHOST-IN-THE-XSIAM${c_reset}\n"
    choices+="ai\t${c_purple}🤖 AI${c_reset}${c_dim}                 LLMs · Embeddings · MLOps · NEUROMANCER${c_reset}\n"
    choices+="research\t${c_orange}🔬 Research${c_reset}${c_dim}           Datasets · Scraping · NLP · DATA-DJ${c_reset}\n"

    # ── Tier 3: Agent / IDE ──
    choices+="─\t${c_dim}── agent / IDE ───────────────────────────────${c_reset}\n"
    choices+="claude\t${c_orange}🧡 Claude Code${c_reset}${c_dim}        Agent SDK · MCP · PROMPT-RIDER${c_reset}\n"

    # ── Tier 4: Knowledge & Ideation ──
    choices+="─\t${c_dim}── knowledge & ideation ──────────────────────${c_reset}\n"
    choices+="vault\t${c_orange}📓 Vault${c_reset}${c_dim}              Obsidian · notes · KNOWLEDGE-KEEPER${c_reset}\n"
    choices+="brainstorm\t${c_pink}💡 Brainstorm${c_reset}${c_dim}         Ideation · mind maps · SPARK-CATCHER${c_reset}\n"
    choices+="pmo\t${c_cyan}📋 PMO${c_reset}${c_dim}                Things 3 · planning · SCRIBE-OPERATOR${c_reset}\n"

    # ── Tier 5: Customer-Facing & Visual ──
    choices+="─\t${c_dim}── customer-facing & visual ──────────────────${c_reset}\n"
    choices+="deck\t${c_green}📊 Deck${c_reset}${c_dim}               Cortex slides · DECK-SMITH${c_reset}\n"
    choices+="design\t${c_purple}🎨 Design${c_reset}${c_dim}             Diagrams · palettes · FRAME-SMITH${c_reset}\n"
    choices+="demo\t${c_pink}🎬 Demo${c_reset}${c_dim}               Presales mode · SHOW-RUNNER${c_reset}\n"

    # ── Tier 6: Hardware & Ops ──
    choices+="─\t${c_dim}── hardware & ops ────────────────────────────${c_reset}\n"
    choices+="homelab\t${c_orange}📡 Homelab${c_reset}${c_dim}            BD790i ops · RACK-WIZARD${c_reset}\n"
    choices+="blackwell\t${c_green}🧠 Blackwell${c_reset}${c_dim}          GPU/ML · CUDA · PHOSPHOR-GHOST${c_reset}\n"
    choices+="tunnels\t${c_cyan}🔗 Tunnels${c_reset}${c_dim}            SSH · Tailscale · PORT-RUNNER${c_reset}\n"

    # ── Direct Tools (action shortcuts, not profile loads) ──
    choices+="─\t${c_dim}── direct actions ────────────────────────────${c_reset}\n"
    choices+="ai_tools\t${c_purple}🧠 AI Toolkit${c_reset}${c_dim}         Ollama · Claude · Aider${c_reset}\n"
    choices+="mcp\t${c_cyan}🔌 MCP Manager${c_reset}${c_dim}        Model Context Protocol${c_reset}\n"
    choices+="agents\t${c_purple}🧠 Agents${c_reset}${c_dim}             Claude · Hermes · Aider · …${c_reset}\n"
    choices+="homelab_ssh\t${c_orange}📡 Homelab SSH${c_reset}${c_dim}        Direct topology launcher${c_reset}\n"
    choices+="tunnel_mgr\t${c_cyan}🔗 Tunnel Manager${c_reset}${c_dim}     Direct FZF tunnel TUI${c_reset}\n"
    choices+="vault_open\t${c_orange}📓 Open Vault${c_reset}${c_dim}         Launch Obsidian directly${c_reset}\n"

    # ── System ──
    choices+="─\t${c_dim}───────────────────────────────────────────────${c_reset}\n"
    choices+="onboard\t${c_pink}🕹  Onboarding${c_reset}${c_dim}        80s arcade · picks your profile${c_reset}\n"
    choices+="integrity\t${c_green}🛡  Integrity Check${c_reset}${c_dim}   verify install · tamper-check${c_reset}\n"
    choices+="tmux\t${c_green}🪟 TMUX${c_reset}${c_dim}               Attach or New Session${c_reset}\n"
    choices+="yazi\t${c_cyan}📂 Yazi${c_reset}${c_dim}               File Browser${c_reset}\n"
    choices+="update\t${c_yellow}🔧 System Update${c_reset}${c_dim}      Brew · NPM · Pip${c_reset}\n"
    choices+="doc\t${c_dim}📖 CLI Docs & Help${c_reset}\n"
    choices+="top\t${c_dim}📊 System Monitor${c_reset}\n"
    choices+="skip\t${c_white}↩  Shell${c_reset}${c_dim}              Exit to prompt${c_reset}\n"

    # Launch fzf menu
    local selection
    selection=$(echo -e "$choices" | column -s $'\t' -t | fzf \
        --height=~30 --reverse --margin=0,0,0,4 \
        --prompt="▶ " \
        --header="  ENTER default · ↑/↓ navigate · ESC shell" \
        --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#bc8cff,hl+:#bc8cff" \
        --ansi \
        || echo "default")

    # Extract just the lookup key from the selection line
    local key=$(echo "$selection" | awk '{print $1}')
    local raw_key="$key"  # preserved before any fallbacks for telemetry

    # Separator lines are not selectable actions
    [[ "$key" == "─" ]] && key="default"
    # Empty = user pressed ESC with no override → default
    [[ -z "$key" ]] && key="default"

    # Telemetry: distinguish ESC-fallback from explicit "default" pick.
    # Answers the key question: how often does the TUI add zero value?
    if [[ -z "$raw_key" ]]; then
        _claw_tui_log "esc_to_default"
    else
        _claw_tui_log "pick:$key"
    fi

    # Process choice directly into the shell session
    case "$key" in
        skip)
            # Exit to bare shell — no profile loaded
            ;;
        default|security|cloud|devops|research|ai|cortex|claude|local|vault|brainstorm|pmo|deck|design|demo|homelab|blackwell|tunnels)
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
        homelab_ssh)
            # Direct action — bypasses the profile, just launches the SSH topology TUI.
            # The `homelab` profile load (above) is the preferred entry point.
            if [[ -f "$_d/scripts/utils/homelab.sh" ]]; then
                "$_d/scripts/utils/homelab.sh"
            else
                echo "${c_red}Homelab connector not found.${c_reset}"
            fi
            ;;
        tunnel_mgr)
            # Direct action — bypasses the profile, just launches the tunnel TUI.
            # The `tunnels` profile load (above) is the preferred entry point.
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
        vault_open)
            # Direct action — open Obsidian to the active vault. The `vault`
            # profile load (above) is the preferred entry point and also
            # exposes oo/oon/oos/ov as in-shell aliases.
            if typeset -f _claw_obsidian_vault &>/dev/null; then
                local _v="$(_claw_obsidian_vault)"
                if [[ -d "$_v" ]]; then
                    claw_open "obsidian://open?vault=$(basename "$_v")"
                    printf "  ${c_green}✓${c_reset} opened ${c_white}%s${c_reset}  ${c_dim}(profile: ${CLAW_ACTIVE_PROFILE:-default})${c_reset}\n" "$(basename "$_v")"
                else
                    echo "  ${c_red}✗${c_reset} vault not found: $_v"
                fi
            else
                echo "  ${c_red}✗${c_reset} obsidian helpers not loaded"
            fi
            ;;
        onboard)
            if [[ -f "$_d/scripts/utils/onboarding.sh" ]]; then
                bash "$_d/scripts/utils/onboarding.sh"
            else
                echo "${c_red}Onboarding script not found.${c_reset}"
            fi
            ;;
        integrity)
            if [[ -f "$_d/scripts/utils/integrity.sh" ]]; then
                bash "$_d/scripts/utils/integrity.sh" audit
            else
                echo "${c_red}Integrity script not found.${c_reset}"
            fi
            ;;
        agents)
            # Show registered agents as an FZF picker; pick one → exec it.
            if ! command -v fzf &>/dev/null; then
                "$_d/bin/claw" agent list
                printf "\n  ${c_dim}fzf not installed — install for picker UX${c_reset}\n"
                return 0
            fi
            local _agents
            # Strip ANSI escapes first, then extract lines with ● bullet, then
            # the agent name (first non-whitespace token after ●).
            _agents=$("$_d/bin/claw" agent list 2>/dev/null | \
                sed -E 's/\x1b\[[0-9;]*m//g' | \
                awk '/●/ {print $2}')
            if [[ -z "$_agents" ]]; then
                echo "  ${c_dim}no agents registered. add one with: claw agent add <name> <command> [profile]${c_reset}"
                return 0
            fi
            local _pick
            _pick=$(echo "$_agents" | fzf --reverse --height=~12 --margin=0,0,0,2 \
                --prompt="agent ▶ " \
                --header="  ENTER launch · ESC cancel" \
                --color="bg+:#161b22,fg+:#c9d1d9,prompt:#bc8cff,header:#8b949e,pointer:#3fb950" \
                | awk '{print $1}')
            [[ -z "$_pick" ]] && return 0
            "$_d/bin/claw" "$_pick"
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
                # Run as bash, NOT source in zsh — system-update.sh sources
                # tui-style.sh via ${BASH_SOURCE[0]} which is bash-only.
                # Sourcing here would break the helper-path resolution.
                bash "$_d/scripts/utils/system-update.sh"
            else
                echo "${c_dim}Running brew update & upgrade...${c_reset}"
                if command -v brew &>/dev/null; then brew update && brew upgrade; elif command -v apt &>/dev/null; then sudo apt update && sudo apt upgrade -y; fi
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
