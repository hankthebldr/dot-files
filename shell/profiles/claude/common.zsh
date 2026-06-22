# Claude Code Profile
# Loadout for AI-assisted development with Claude Code, Agent SDK, and MCP

# ==========================================
# ENVIRONMENT VARIABLES
# ==========================================
export CLAUDE_WORKSPACE="$HOME/projects"
mkdir -p "$CLAUDE_WORKSPACE" 2>/dev/null

# Claude Code (CLI) config paths
# DO NOT set CLAUDE_CONFIG_DIR — that env var relocates the *Claude Code CLI*
# config dir away from its default ~/.claude (where link-claude.sh deploys
# CLAUDE.md, hooks, skills, commands, settings.json, keybindings). Pointing it
# at ~/.config/claude lands the CLI on an empty parallel tree: no memory, no
# hooks, default keybindings — which looks like "Claude is broken / input is
# weird" the moment this profile is active. See docs/claude-config-boundaries.md.
# MCP/registry config is owned by Claude Desktop (macOS) or `claude mcp` (CLI).
if [[ "$OSTYPE" == darwin* ]]; then
  export MCP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
fi

# ==========================================
# CLAUDE CODE ALIASES
# ==========================================

# --- Core ---
alias cc='claude'
alias cci='claude --interactive'
alias ccp='claude --print'
alias ccr='claude --resume'
alias ccs='claude --sync'

# --- Context ---
alias ccmd='$EDITOR CLAUDE.md'
alias cclocal='$EDITOR .claude.local.md'
alias ccglobal='$EDITOR ~/.claude/CLAUDE.md'

# --- MCP ---
alias mcp='${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/mcp-manager.sh'
alias mcpconfig='$EDITOR $MCP_CONFIG'
alias mcplist='claude mcp list 2>/dev/null || echo "Use mcp alias for MCP manager"'

# --- Agent SDK ---
alias agents='claude agent'
alias agentrun='claude agent run'
alias agentls='claude agent list'

# --- Project Workflows ---
alias ccplan='claude "review the codebase and create an implementation plan"'
alias ccreview='claude "review the recent changes for bugs and improvements"'
alias cctest='claude "run the test suite and fix any failures"'
alias ccdocs='claude "update documentation to match the current code"'

# --- Quick Actions ---
alias ccfix='claude "fix the issue described in the last error output"'
alias ccrefactor='claude "refactor this file for clarity and maintainability"'
alias ccexplain='claude "explain how this codebase works at a high level"'

# ==========================================
# HELPER FUNCTIONS
# ==========================================

# Claude Code with file context
ccf() {
    if [[ -z "$1" ]]; then
        echo "Usage: ccf <file> [prompt]"
        echo "  Opens Claude Code with the file as context"
        return 1
    fi
    local file="$1"
    shift
    claude "$@" -- "$file"
}

# Quick commit with Claude
cccommit() {
    claude "look at the staged changes (git diff --staged) and create a good commit message, then commit"
}

# ==========================================
# QUICK REFERENCE
# ==========================================
claude-help() {
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_orange=$'\e[38;2;227;179;65m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    echo ""
    echo "  ${c_purple}╭──────────────────────────────────────────────────────────╮${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}CLAUDE CODE PROFILE${c_reset} — Quick Reference                 ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰──────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
    echo "  ${c_green}${c_bold}Core${c_reset}"
    echo "  ${c_white}cc${c_reset}           ${c_dim}Launch Claude Code${c_reset}"
    echo "  ${c_white}cci${c_reset}          ${c_dim}Interactive mode${c_reset}"
    echo "  ${c_white}ccp${c_reset}          ${c_dim}Print mode (no file changes)${c_reset}"
    echo "  ${c_white}ccr${c_reset}          ${c_dim}Resume last conversation${c_reset}"
    echo ""
    echo "  ${c_cyan}${c_bold}Context Files${c_reset}"
    echo "  ${c_white}ccmd${c_reset}         ${c_dim}Edit project CLAUDE.md${c_reset}"
    echo "  ${c_white}cclocal${c_reset}      ${c_dim}Edit .claude.local.md${c_reset}"
    echo "  ${c_white}ccglobal${c_reset}     ${c_dim}Edit global ~/.claude/CLAUDE.md${c_reset}"
    echo ""
    echo "  ${c_orange}${c_bold}Workflows${c_reset}"
    echo "  ${c_white}ccplan${c_reset}       ${c_dim}Generate implementation plan${c_reset}"
    echo "  ${c_white}ccreview${c_reset}     ${c_dim}Code review recent changes${c_reset}"
    echo "  ${c_white}cctest${c_reset}       ${c_dim}Run tests and fix failures${c_reset}"
    echo "  ${c_white}ccfix${c_reset}        ${c_dim}Fix last error${c_reset}"
    echo "  ${c_white}cccommit${c_reset}     ${c_dim}AI-generated commit message${c_reset}"
    echo ""
    echo "  ${c_purple}${c_bold}MCP & Agents${c_reset}"
    echo "  ${c_white}mcp${c_reset}          ${c_dim}MCP server manager TUI${c_reset}"
    echo "  ${c_white}mcpconfig${c_reset}    ${c_dim}Edit MCP config JSON${c_reset}"
    echo "  ${c_white}agents${c_reset}       ${c_dim}Agent SDK commands${c_reset}"
    echo ""
}

# ==========================================
# TOOL VALIDATION
# ==========================================
_claude_tool_check() {
    local c_reset=$'\e[0m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_red=$'\e[38;2;255;123;114m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'

    local tools=(claude node npm npx python3 git gh jq yq)
    local installed=0
    local total=${#tools[@]}

    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            ((installed++))
        fi
    done

    if ((installed == total)); then
        echo "  ${c_green}✓${c_reset} ${c_dim}All ${total} Claude Code tools available${c_reset}"
    else
        echo "  ${c_dim}Tools: ${c_green}${installed}${c_dim}/${total}${c_reset}"
        for tool in "${tools[@]}"; do
            if ! command -v "$tool" &>/dev/null; then
                echo "    ${c_red}✗${c_reset} ${c_white}${tool}${c_reset}"
            fi
        done
    fi
}

# Profile banner handled by fastfetch (config-claude.jsonc)
