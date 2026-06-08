# shell/welcome-tui.zsh
# Interactive Open Claw Login Dashboard — two-level wizard (group → sub-profile)

# Apply a claw-tui outcome line (PROFILE\t<key> | ACTION\t<id> | NONE) to the
# parent shell — this is the half the binary physically cannot do.
_claw_apply_outcome() {
    local line="$1" kind rest
    kind="${line%%$'\t'*}"; rest="${line#*$'\t'}"
    case "$kind" in
        PROFILE)
            [[ -f "$DOTFILES_DIR/shell/profiles/${rest}.zsh" ]] && {
                export CLAW_ACTIVE_PROFILE="$rest"
                source "$DOTFILES_DIR/shell/profiles/${rest}.zsh"
            } ;;
        ACTION)
            # Run a known claw action, then continue to a bare shell.
            command -v claw &>/dev/null && claw "$rest" ;;
        *) : ;;   # NONE / unknown → bare shell
    esac
}

function claw_welcome_tui() {
    # SAFETY: Never run in non-interactive shells (breaks scp, rsync, git-over-ssh)
    [[ ! -o interactive ]] && return
    # SAFETY: Never run if stdin is not a terminal (piped input)
    [[ ! -t 0 ]] && return
    # SAFETY: Never run inside SSH that's piping data (e.g. scp, rsync)
    [[ -n "$SSH_CONNECTION" && ! -t 1 ]] && return
    # Skip if a profile is already active to prevent infinite loop
    [[ -n "$CLAW_ACTIVE_PROFILE" ]] && return

    # ── Wave 4: optional ratatui front-end (opt-in via CLAW_TUI=1) ──────────
    # The Rust binary renders + selects; we apply its one-line outcome here.
    # Default-off so the proven fzf path stays the baseline (progressive
    # enhancement, same guard pattern as every tool in the repo).
    if [[ "${CLAW_TUI:-0}" == 1 ]] && command -v claw-tui &> /dev/null; then
        _claw_apply_outcome "$(claw-tui welcome)"
        return
    fi

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
    local c_orange=$'\e[38;2;227;179;65m'  # GitHub Orange/Gold: #e3b341
    local c_yellow=$'\e[38;2;227;179;65m'  # GitHub Yellow (using gold)
    local c_dim=$'\e[38;2;139;148;158m'    # GitHub Muted: #8b949e
    local c_red=$'\e[38;2;255;123;114m'    # GitHub Red: #ff7b72
    local c_white=$'\e[38;2;201;209;217m'  # GitHub fg: #c9d1d9
    local c_bold=$'\e[1m'

    # Ensure fzf is installed to run the interactive menu
    if ! command -v fzf &> /dev/null; then
        clear
        echo "  ${c_dim}Welcome TUI skipped: 'fzf' is not installed.${c_reset}"
        return
    fi

    # Colors from the active theme (exported by exports.zsh / theme.sh); fall
    # back to the refined-dark defaults if the dashboard is invoked standalone.
    local _fzf_color="${CLAW_FZF_COLOR:-bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#bc8cff,hl+:#bc8cff}"

    # Render the Screen-1 dashboard header. Preference order:
    #   1. claw-dashboard.py — the framed, gradient, two-column dashboard (best)
    #   2. fastfetch config.jsonc — the two-column readout
    #   3. branded ASCII fallback
    _claw_tui_header() {
        clear
        local dash="$_d/scripts/utils/claw-dashboard.py"
        local ff_config="$_d/config/.config/fastfetch/config.jsonc"
        if command -v python3 &> /dev/null && [[ -f "$dash" ]]; then
            DOTFILES_DIR="$_d" python3 "$dash"
        elif command -v fastfetch &> /dev/null && [[ -f "$ff_config" ]]; then
            fastfetch -c "$ff_config"
        else
            # Fallback: branded header if fastfetch is missing
            echo ""
            echo "  ${c_purple}╭──────────────────────────────────────────────╮${c_reset}"
            echo "  ${c_purple}│${c_reset}   ${c_cyan}█▀█ █▀█ █▀▀ █▄░█   ${c_green}█▀▀ █░░ ▄▀█ █░█░█${c_reset}   ${c_purple}│${c_reset}"
            echo "  ${c_purple}│${c_reset}   ${c_cyan}█▄█ █▀▀ ██▄ █░▀█   ${c_green}█▄▄ █▄▄ █▀█ ▀▄▀▄▀${c_reset}   ${c_purple}│${c_reset}"
            echo "  ${c_purple}│${c_reset}   ${c_dim}$(os_version 2>/dev/null || uname -sr) · $(uname -m)${c_reset}"
            echo "  ${c_purple}│${c_reset}   ${c_dim}$(date '+%a %b %d %H:%M') · $(local_ip 2>/dev/null)${c_reset}"
            echo "  ${c_purple}╰──────────────────────────────────────────────╯${c_reset}"
        fi
        echo ""
    }

    # ── Level 1: groups + direct picks ──
    # Tokens are either a profile/action key (direct) or a group id. Group ids
    # (domain/knowledge/visual/hardware/actions/system) are chosen NOT to collide
    # with any profile or action key, so membership alone decides Screen 2 vs dispatch.
    local l1=""
    l1+="default\t${c_green}${c_bold}⚙️  Default Shell${c_reset}${c_dim}      Standard Dev · daily driver${c_reset}\n"
    l1+="local\t${c_green}🛠️  Local${c_reset}${c_dim}              Custom Built CLI Tools${c_reset}\n"
    l1+="claude\t${c_orange}🧡 Claude Code${c_reset}${c_dim}        Agent SDK · MCP · PROMPT-RIDER${c_reset}\n"
    l1+="domain\t${c_cyan}☁️  Domain Expertise${c_reset} ${c_dim}▸ cloud · devops · security · cortex · ai · research${c_reset}\n"
    l1+="knowledge\t${c_orange}📓 Knowledge & Ideation${c_reset} ${c_dim}▸ vault · brainstorm · pmo${c_reset}\n"
    l1+="visual\t${c_purple}🎨 Customer-Facing${c_reset} ${c_dim}▸ deck · design · demo${c_reset}\n"
    l1+="hardware\t${c_orange}📡 Hardware & Ops${c_reset} ${c_dim}▸ homelab · blackwell · tunnels${c_reset}\n"
    l1+="actions\t${c_cyan}⚡ Direct Actions${c_reset} ${c_dim}▸ ai-toolkit · mcp · agents · ssh · tunnels · vault${c_reset}\n"
    l1+="system\t${c_yellow}🛠  System${c_reset} ${c_dim}▸ onboard · integrity · tmux · yazi · update · docs · monitor${c_reset}\n"

    # ── Level 2: items per group ──
    typeset -A l2 l2_title
    l2_title[domain]="Domain Expertise"; l2_title[knowledge]="Knowledge & Ideation"
    l2_title[visual]="Customer-Facing & Visual"; l2_title[hardware]="Hardware & Ops"
    l2_title[actions]="Direct Actions"; l2_title[system]="System"

    l2[domain]=""
    l2[domain]+="cloud\t${c_cyan}☁️  Cloud${c_reset}${c_dim}              AWS · K8s · Terraform · SKYSURFER${c_reset}\n"
    l2[domain]+="devops\t${c_green}🏗️  DevOps${c_reset}${c_dim}             CI/CD · Monitoring · IaC · WRENCH-MAGE${c_reset}\n"
    l2[domain]+="security\t${c_pink}🔐 Security${c_reset}${c_dim}           Pentest · OSINT · Forensics · NIGHTHACKER${c_reset}\n"
    l2[domain]+="cortex\t${c_pink}🛡️  Cortex${c_reset}${c_dim}             XSOAR · XSIAM · PAN-OS · GHOST-IN-THE-XSIAM${c_reset}\n"
    l2[domain]+="ai\t${c_purple}🤖 AI${c_reset}${c_dim}                 LLMs · Embeddings · MLOps · NEUROMANCER${c_reset}\n"
    l2[domain]+="research\t${c_orange}🔬 Research${c_reset}${c_dim}           Datasets · Scraping · NLP · DATA-DJ${c_reset}\n"

    l2[knowledge]=""
    l2[knowledge]+="vault\t${c_orange}📓 Vault${c_reset}${c_dim}              Obsidian · notes · KNOWLEDGE-KEEPER${c_reset}\n"
    l2[knowledge]+="brainstorm\t${c_pink}💡 Brainstorm${c_reset}${c_dim}         Ideation · mind maps · SPARK-CATCHER${c_reset}\n"
    l2[knowledge]+="pmo\t${c_cyan}📋 PMO${c_reset}${c_dim}                Things 3 · planning · SCRIBE-OPERATOR${c_reset}\n"

    l2[visual]=""
    l2[visual]+="deck\t${c_green}📊 Deck${c_reset}${c_dim}               Cortex slides · DECK-SMITH${c_reset}\n"
    l2[visual]+="design\t${c_purple}🎨 Design${c_reset}${c_dim}             Diagrams · palettes · FRAME-SMITH${c_reset}\n"
    l2[visual]+="demo\t${c_pink}🎬 Demo${c_reset}${c_dim}               Presales mode · SHOW-RUNNER${c_reset}\n"

    l2[hardware]=""
    l2[hardware]+="homelab\t${c_orange}📡 Homelab${c_reset}${c_dim}            BD790i ops · RACK-WIZARD${c_reset}\n"
    l2[hardware]+="blackwell\t${c_green}🧠 Blackwell${c_reset}${c_dim}          GPU/ML · CUDA · PHOSPHOR-GHOST${c_reset}\n"
    l2[hardware]+="tunnels\t${c_cyan}🔗 Tunnels${c_reset}${c_dim}            SSH · Tailscale · PORT-RUNNER${c_reset}\n"

    l2[actions]=""
    l2[actions]+="ai_tools\t${c_purple}🧠 AI Toolkit${c_reset}${c_dim}         Ollama · Claude · Aider${c_reset}\n"
    l2[actions]+="mcp\t${c_cyan}🔌 MCP Manager${c_reset}${c_dim}        Model Context Protocol${c_reset}\n"
    l2[actions]+="agents\t${c_purple}🧠 Agents${c_reset}${c_dim}             Claude · Hermes · Aider · …${c_reset}\n"
    l2[actions]+="homelab_ssh\t${c_orange}📡 Homelab SSH${c_reset}${c_dim}        Direct topology launcher${c_reset}\n"
    l2[actions]+="tunnel_mgr\t${c_cyan}🔗 Tunnel Manager${c_reset}${c_dim}     Direct FZF tunnel TUI${c_reset}\n"
    l2[actions]+="vault_open\t${c_orange}📓 Open Vault${c_reset}${c_dim}         Launch Obsidian directly${c_reset}\n"

    l2[system]=""
    l2[system]+="onboard\t${c_pink}🕹  Onboarding${c_reset}${c_dim}        80s arcade · picks your profile${c_reset}\n"
    l2[system]+="integrity\t${c_green}🛡  Integrity Check${c_reset}${c_dim}   verify install · tamper-check${c_reset}\n"
    l2[system]+="tmux\t${c_green}🪟 TMUX${c_reset}${c_dim}               Attach or New Session${c_reset}\n"
    l2[system]+="yazi\t${c_cyan}📂 Yazi${c_reset}${c_dim}               File Browser${c_reset}\n"
    l2[system]+="update\t${c_yellow}🔧 System Update${c_reset}${c_dim}      Brew · NPM · Pip${c_reset}\n"
    l2[system]+="doc\t${c_dim}📖 CLI Docs & Help${c_reset}\n"
    l2[system]+="top\t${c_dim}📊 System Monitor${c_reset}\n"
    l2[system]+="skip\t${c_white}↩  Shell${c_reset}${c_dim}              Exit to prompt${c_reset}\n"

    # ── Two-level selection loop ──
    # L1: pick a direct entry or a group. ESC at L1 → default (preserves old behavior).
    # L2: pick an item. ESC at L2 → back to L1.
    local key="" raw_key="" _group=""
    while true; do
        _claw_tui_header
        local sel tok
        sel=$(echo -e "$l1" | column -s $'\t' -t | fzf \
            --height=~14 --reverse --margin=0,0,0,4 --ansi \
            --prompt="▶ " \
            --header="  ENTER select · ↑/↓ navigate · ESC shell" \
            --color="$_fzf_color")
        tok=$(echo "$sel" | awk '{print $1}')

        # ESC at L1 (empty) → fall through to default profile (legacy behavior)
        if [[ -z "$tok" ]]; then key="default"; raw_key=""; break; fi

        # Is the token a group? → descend to Level 2
        if [[ -n "${l2[$tok]:-}" ]]; then
            _claw_tui_log "group:$tok"
            clear
            printf "\n  ${c_purple}${c_bold}Open Claw${c_reset} ${c_dim}▸${c_reset} ${c_white}%s${c_reset}\n\n" "${l2_title[$tok]}"
            local sel2 itok
            sel2=$(echo -e "${l2[$tok]}" | column -s $'\t' -t | fzf \
                --height=~14 --reverse --margin=0,0,0,4 --ansi \
                --with-nth=2.. \
                --prompt="▶ " \
                --header="  ENTER select · ESC back" \
                --color="$_fzf_color")
            itok=$(echo "$sel2" | awk '{print $1}')
            # ESC at L2 → back to the group picker
            [[ -z "$itok" ]] && continue
            key="$itok"; raw_key="$itok"; _group="$tok"; break
        fi

        # Direct pick (default / local / claude)
        key="$tok"; raw_key="$tok"; break
    done

    # Telemetry: distinguish ESC-fallback from an explicit pick.
    if [[ -z "$raw_key" ]]; then
        _claw_tui_log "esc_to_default"
    else
        _claw_tui_log "pick:$key"
    fi

    # Wipe the Screen-1 dashboard before rendering the post-pick art. fzf runs in
    # an inline height region and leaves the header dashboard on screen when it
    # exits; without this clear the profile art (or, for `default`, a second copy
    # of the same dashboard) stacks underneath it — the "doubled boxes" bug.
    clear

    # Process choice directly into the shell session
    case "$key" in
        skip)
            # Exit to bare shell — no profile loaded
            ;;
        default|security|cloud|devops|research|ai|cortex|claude|local|vault|brainstorm|pmo|deck|design|demo|homelab|blackwell|tunnels)
            export CLAW_ACTIVE_PROFILE="$key"
            export CLAW_ACTIVE_GROUP="$_group"   # "" for direct picks (default/local/claude)
            local _profile="$_d/shell/profiles/${key}.zsh"
            if [[ -f "$_profile" ]]; then
                source "$_profile"
            else
                echo "${c_red}Profile not found: $_profile${c_reset}"
            fi
            # Display profile-specific art. default → the framed claw-dashboard
            # (system logo + two-column readout); other profiles keep their
            # truecolor fastfetch art. Falls back so EVERY pick renders something.
            local _dash="$_d/scripts/utils/claw-dashboard.py"
            local _ff_profile="$_d/config/.config/fastfetch/config-${key}.jsonc"
            [[ -f "$_ff_profile" ]] || _ff_profile="$_d/config/.config/fastfetch/config.jsonc"
            if [[ "$key" == "default" ]] && command -v python3 &> /dev/null && [[ -f "$_dash" ]]; then
                echo ""
                DOTFILES_DIR="$_d" python3 "$_dash"
            elif command -v fastfetch &> /dev/null && [[ -f "$_ff_profile" ]]; then
                echo ""
                fastfetch -c "$_ff_profile"
            fi
            # Readout under the art: default keeps its quick-ref card; every
            # other profile gets the metadata-driven key-tools/docs/help readout.
            if [[ "$key" == "default" ]]; then
                _claw_default_quickref
            else
                _claw_profile_readout "$key"
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
    local c_orange=$'\e[38;2;227;179;65m'
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

# ============================================
# PER-PROFILE READOUT
# Compact card under the profile art — key tools, docs, help guidance.
# Driven entirely by the PROFILE_* metadata the loaded profile's meta.zsh set
# (PROFILE_CLASS / PROFILE_TAG / PROFILE_KEY_TOOLS / PROFILE_TOOLCHAIN) plus the
# {profile}-help / _{profile}_tool_check helpers it defines. Only shows commands
# that actually resolve, so it degrades gracefully on any profile.
# ============================================
_claw_profile_readout() {
    local key="$1"
    local c_reset=$'\e[0m' c_cyan=$'\e[38;2;88;166;255m' c_green=$'\e[38;2;63;185;80m'
    local c_orange=$'\e[38;2;227;179;65m' c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m' c_bold=$'\e[1m'

    # Key tools — first 8 of PROFILE_KEY_TOOLS, "·"-joined
    local tools_line=""
    if [[ -n "${PROFILE_KEY_TOOLS:-}" ]]; then
        local -a _t=(${=PROFILE_KEY_TOOLS})
        local -a _head=(${_t[1,8]})
        tools_line="${(j: · :)_head}"
        (( ${#_t[@]} > 8 )) && tools_line+=" · …"
    fi

    # Reference commands — only those that actually resolve as functions
    local help_cmd="${PROFILE_HELP_CMD:-${key}-help}"
    local check_cmd="_${key}_tool_check"
    # Profiles without a bespoke checker fall back to the generic one (which
    # reads PROFILE_KEY_TOOLS) so the status card always renders.
    if (( ! ${+functions[$check_cmd]} )) && [[ -n "${PROFILE_KEY_TOOLS:-}" ]]; then
        check_cmd="_claw_profile_tool_check"
    fi
    local -a refs=()
    (( ${+functions[$help_cmd]} ))  && refs+=("${c_green}${help_cmd}${c_reset} ${c_dim}reference${c_reset}")
    (( ${+functions[$check_cmd]} )) && refs+=("${c_green}${check_cmd}${c_reset} ${c_dim}status${c_reset}")
    [[ -n "${PROFILE_TOOLCHAIN:-}" ]] && refs+=("${c_green}${PROFILE_TOOLCHAIN}${c_reset} ${c_dim}install${c_reset}")

    # Glyph mirrors the picker
    local glyph
    case "$key" in
        cloud) glyph="☁️" ;;   devops) glyph="🏗️" ;;   security) glyph="🔐" ;;
        cortex) glyph="🛡️" ;;  ai) glyph="🤖" ;;       research) glyph="🔬" ;;
        claude) glyph="🧡" ;;  vault) glyph="📓" ;;     brainstorm) glyph="💡" ;;
        pmo) glyph="📋" ;;     deck) glyph="📊" ;;      design) glyph="🎨" ;;
        demo) glyph="🎬" ;;    homelab) glyph="📡" ;;   blackwell) glyph="🧠" ;;
        tunnels) glyph="🔗" ;; local) glyph="🛠️" ;;     *) glyph="⚙️" ;;
    esac

    echo ""
    # Identity — class + tag
    if [[ -n "${PROFILE_CLASS:-}${PROFILE_TAG:-}" ]]; then
        printf "  %s  ${c_green}${c_bold}%s${c_reset}" "$glyph" "${PROFILE_CLASS:-$key}"
        [[ -n "${PROFILE_TAG:-}" ]] && printf "  ${c_dim}· %s${c_reset}" "$PROFILE_TAG"
        echo ""
    fi
    # Key tools
    [[ -n "$tools_line" ]] && \
        printf "  ${c_orange}${c_bold}🔧 Key tools${c_reset}   ${c_white}%s${c_reset}\n" "$tools_line"
    # Docs & help
    (( ${#refs[@]} )) && \
        printf "  ${c_cyan}${c_bold}📖 Docs & help${c_reset}  %s\n" "${(j:   ·   :)refs}"
    echo ""
}
