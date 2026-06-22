# Local CLI Profile
# Loadout for custom built and local CLI repositories

# ==========================================
# UNIFIED CLI STARTUP SPEC PARSER
# ==========================================
# This script iterates through all subdirectories in ~/Github/local-clis/
# and parses any `.clistartup` specification files to dynamically load
# tools, aliases, and environment variables.

LOCAL_CLI_DIR="$HOME/Github/local-clis"

if [[ -d "$LOCAL_CLI_DIR" ]]; then
    # zsh's default behavior is to error on unmatched globs; null_glob makes
    # an empty dir produce an empty list instead of an error that aborts the
    # whole profile load.
    setopt local_options null_glob
    # Iterate over all immediate subdirectories
    for d in "$LOCAL_CLI_DIR"/*/; do
        spec_file="${d}.clistartup"
        
        if [[ -f "$spec_file" ]]; then
            # We source the spec file directly to load its bash-compatible variables
            # We execute it in a subshell first to ensure valid syntax before pulling variables into current shell
            if zsh -n "$spec_file" &>/dev/null; then
                # Source safely
                source "$spec_file"
                
                # Apply: TOOL_EXPORT_PATH
                if [[ -n "$TOOL_EXPORT_PATH" ]]; then
                    full_path="${d}${TOOL_EXPORT_PATH}"
                    # Only add if it exists and isn't already in PATH
                    if [[ -d "$full_path" && ":$PATH:" != *":$full_path:"* ]]; then
                        export PATH="$full_path:$PATH"
                    fi
                fi
                
                # Apply: TOOL_ENV
                if [[ -n "${TOOL_ENV[@]}" ]]; then
                    for evar in "${TOOL_ENV[@]}"; do
                        export "$evar"
                    done
                fi

                # Apply: TOOL_ALIASES
                if [[ -n "${TOOL_ALIASES[@]}" ]]; then
                    for string_alias in "${TOOL_ALIASES[@]}"; do
                        # Evaluate to alias command
                        alias "$string_alias"
                    done
                fi
                
                # Unset the spec variables so they don't bleed into the next iteration
                unset TOOL_NAME TOOL_EXPORT_PATH TOOL_ENV TOOL_ALIASES
            else
                echo "⚠️ Syntax error in CLI Startup Spec: $spec_file"
            fi
        fi
    done
fi

# ==========================================
# QUICK REFERENCE
# ==========================================
local-help() {
    local c_reset=$'\e[0m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_green}${c_bold}LOCAL PROFILE${c_reset} ${c_dim}— Custom-Built CLI Tools${c_reset}                  ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
    echo "  ${c_dim}This profile dynamically loads tool specs from:${c_reset}"
    echo "    ${c_white}${LOCAL_CLI_DIR:-$HOME/Github/local-clis}${c_reset}"
    echo ""
    echo "  ${c_dim}Each subdirectory with a ${c_white}.clistartup${c_dim} file gets:${c_reset}"
    echo "    ${c_dim}- TOOL_EXPORT_PATH      added to PATH${c_reset}"
    echo "    ${c_dim}- TOOL_ENV              exported${c_reset}"
    echo "    ${c_dim}- TOOL_ALIASES          installed${c_reset}"
    echo ""
    echo "  ${c_green}${c_bold}Discovered tools${c_reset}"
    setopt local_options null_glob
    local _dir="${LOCAL_CLI_DIR:-$HOME/Github/local-clis}"
    if [[ -d "$_dir" ]]; then
        local _any=0
        for d in "$_dir"/*/; do
            _any=1
            local name="$(basename "$d")"
            if [[ -f "${d}.clistartup" ]]; then
                echo "    ${c_green}●${c_reset} ${c_white}${name}${c_reset}"
            else
                echo "    ${c_dim}○ ${name} (no .clistartup)${c_reset}"
            fi
        done
        (( _any )) || echo "    ${c_dim}(no tools yet — drop a directory with a .clistartup file in $_dir)${c_reset}"
    else
        echo "    ${c_dim}directory not found: $_dir${c_reset}"
    fi
    echo ""
}

# ==========================================
# DISCOVERY STATUS
# ==========================================
_local_tool_check() {
    local c_reset=$'\e[0m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_red=$'\e[38;2;255;123;114m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'

    local dir="${LOCAL_CLI_DIR:-$HOME/Github/local-clis}"
    if [[ ! -d "$dir" ]]; then
        printf "  ${c_red}✗${c_reset} ${c_dim}local CLI dir missing: ${c_white}%s${c_reset}\n" "$dir"
        return 1
    fi
    setopt local_options null_glob
    local total=0 with_spec=0
    for d in "$dir"/*/; do
        ((total++))
        [[ -f "${d}.clistartup" ]] && ((with_spec++))
    done
    printf "  ${c_green}●${c_reset} ${c_dim}local CLIs:${c_reset} ${c_white}%d${c_reset}${c_dim} dirs (${c_green}%d${c_dim} loadable, ${c_red}%d${c_dim} no-spec)${c_reset}\n" \
        "$total" "$with_spec" "$((total - with_spec))"
}

# Profile banner handled by fastfetch (config-local.jsonc)
