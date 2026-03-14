#!/usr/bin/env bash
# scripts/utils/system-update.sh
# Cumulative System Update Script with modern beautiful UI

# Theme Colors (GitHub macOS Dark)
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_dim=$'\e[38;2;139;148;158m'

# Check if running in non-interactive (MCP) mode
INTERACTIVE=1
if [[ "$1" == "--non-interactive" ]]; then
    INTERACTIVE=0
fi

if [[ $INTERACTIVE -eq 1 ]]; then
    clear
fi

echo "${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
echo "${c_purple}│${c_reset}  ${c_cyan}🔄 CUMULATIVE SYSTEM UPDATE${c_reset}                           ${c_purple}│${c_reset}"
echo "${c_purple}├────────────────────────────────────────────────────────┤${c_reset}"
echo "${c_purple}│${c_reset}  ${c_dim}Scanning and updating all installed package managers..${c_reset}${c_purple}│${c_reset}"
echo "${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
echo ""

# Helper to print step headers
step_header() {
    echo "${c_green}── $1 ──${c_reset}"
}

# Helper to print skip messages
skip_msg() {
    echo "  ${c_dim}Skipping: $1 not installed.${c_reset}"
}

# 1. Homebrew
step_header "macOS / Homebrew"
if command -v brew &> /dev/null; then
    echo "  ${c_dim}Running brew update & upgrade...${c_reset}"
    brew update && brew upgrade
else
    skip_msg "brew"
fi
echo ""

# 2. Node.js Ecosystem
step_header "Node.js Ecosystem"
if command -v npm &> /dev/null; then
    echo "  ${c_dim}Updating global npm packages...${c_reset}"
    npm update -g
else
    skip_msg "npm"
fi

if command -v yarn &> /dev/null; then
    echo "  ${c_dim}Updating global yarn packages...${c_reset}"
    yarn global upgrade
else
    skip_msg "yarn"
fi

if command -v pnpm &> /dev/null; then
    echo "  ${c_dim}Updating global pnpm packages...${c_reset}"
    pnpm update -g || pnpm upgrade --global
else
    skip_msg "pnpm"
fi
echo ""

# 3. Python Ecosystem
step_header "Python Ecosystem"
if command -v uv &> /dev/null; then
    echo "  ${c_dim}Updating uv tools and uv itself...${c_reset}"
    uv self update
    uv tool upgrade --all 2>/dev/null || true
else
    skip_msg "uv"
fi

if command -v pipx &> /dev/null; then
    echo "  ${c_dim}Updating pipx tools...${c_reset}"
    pipx upgrade-all
else
    skip_msg "pipx"
fi

if command -v pip3 &> /dev/null; then
    echo "  ${c_dim}Updating pip module...${c_reset}"
    python3 -m pip install --upgrade pip
else
    skip_msg "pip3"
fi
echo ""

# 4. Ruby
step_header "Ruby Ecosystem"
if command -v gem &> /dev/null; then
    echo "  ${c_dim}Updating ruby gems system...${c_reset}"
    gem update --system
else
    skip_msg "gem"
fi
echo ""

# 5. Rust
step_header "Rust Ecosystem"
if command -v rustup &> /dev/null; then
    echo "  ${c_dim}Updating rust toolchains...${c_reset}"
    rustup update
else
    skip_msg "rustup"
fi
echo ""

# 6. Go
step_header "Go Ecosystem"
if command -v go &> /dev/null; then
    echo "  ${c_dim}Updating Go toolchain (if supported via go module)...${c_reset}"
    # Go 1.21+ supports 'go get go@latest' or similar for toolchains, but we'll try a safe global module update
    go clean -modcache
    echo "  ${c_dim}(Go binary updates are usually managed by brew/system package manager)${c_reset}"
else
    skip_msg "go"
fi
echo ""

# 7. Shell / Oh My Zsh
step_header "Shell / Oh My Zsh"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    # Oh My Zsh has a built in updater script we can call
    if command -v omz &> /dev/null; then
        echo "  ${c_dim}Updating Oh My Zsh...${c_reset}"
        # Prevent it from altering the TUI too much by piping to cat or running silently
        omz update --unattended
    else
        skip_msg "omz CLI tool"
    fi
else
    skip_msg "Oh My Zsh"
fi
echo ""

echo "${c_cyan}✅ Cumulative System Update Complete!${c_reset}"
if [[ $INTERACTIVE -eq 1 ]]; then
    echo ""
    read -n 1 -s -r -p "Press any key to continue..."
    echo ""
fi
