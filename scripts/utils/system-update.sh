#!/usr/bin/env bash
# scripts/utils/system-update.sh
# Cumulative System Update with beautiful progress UI
# Uses gum spinners when available, falls back to styled echo

# ============================================
# THEME & HELPERS
# ============================================
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_orange=$'\e[38;2;210;153;34m'
c_red=$'\e[38;2;255;123;114m'
c_dim=$'\e[38;2;139;148;158m'
c_white=$'\e[38;2;201;209;217m'
c_bold=$'\e[1m'

HAS_GUM=false
command -v gum &>/dev/null && HAS_GUM=true

# Spinner wrapper: gum spin if available, else styled echo + run
run_step() {
    local title="$1"
    shift
    if $HAS_GUM; then
        gum spin --spinner dot --spinner.foreground="#58a6ff" --title "  $title" -- bash -c "$*" 2>/dev/null
    else
        printf "  ${c_cyan}◌${c_reset} ${c_white}%s${c_reset}" "$title"
        if eval "$*" &>/dev/null; then
            printf "\r  ${c_green}●${c_reset} ${c_white}%s${c_reset}\n" "$title"
        else
            printf "\r  ${c_red}✗${c_reset} ${c_white}%s${c_reset} ${c_dim}(failed)${c_reset}\n" "$title"
        fi
    fi
}

skip_msg() {
    printf "  ${c_dim}○ %s — not installed${c_reset}\n" "$1"
}

section() {
    echo ""
    echo "  ${c_purple}${c_bold}$1${c_reset}"
    echo "  ${c_dim}$(printf '%.0s─' {1..44})${c_reset}"
}

count_managers() {
    local count=0
    for cmd in brew npm yarn pnpm uv pipx pip3 gem rustup go; do
        command -v "$cmd" &>/dev/null && ((count++))
    done
    echo "$count"
}

# ============================================
# HEADER
# ============================================
INTERACTIVE=1
[[ "$1" == "--non-interactive" ]] && INTERACTIVE=0
[[ $INTERACTIVE -eq 1 ]] && clear

total=$(count_managers)
echo ""
echo "  ${c_purple}╭──────────────────────────────────────────────────────╮${c_reset}"
echo "  ${c_purple}│${c_reset}  ${c_cyan}${c_bold}🔄 SYSTEM UPDATE${c_reset}                                     ${c_purple}│${c_reset}"
echo "  ${c_purple}│${c_reset}  ${c_dim}Updating ${total} package managers across all ecosystems${c_reset}  ${c_purple}│${c_reset}"
echo "  ${c_purple}╰──────────────────────────────────────────────────────╯${c_reset}"

# ============================================
# 1. HOMEBREW
# ============================================
section "Homebrew"
if command -v brew &>/dev/null; then
    run_step "Updating Homebrew formulae index..." "brew update"
    run_step "Upgrading outdated packages..." "brew upgrade"
    run_step "Cleaning up old versions..." "brew cleanup --prune=7"
else
    skip_msg "brew"
fi

# ============================================
# 2. NODE.JS
# ============================================
section "Node.js"
if command -v npm &>/dev/null; then
    run_step "Updating global npm packages..." "npm update -g"
else
    skip_msg "npm"
fi
if command -v yarn &>/dev/null; then
    run_step "Updating global yarn packages..." "yarn global upgrade"
else
    skip_msg "yarn"
fi
if command -v pnpm &>/dev/null; then
    run_step "Updating global pnpm packages..." "pnpm update -g"
else
    skip_msg "pnpm"
fi

# ============================================
# 3. PYTHON
# ============================================
section "Python"
if command -v uv &>/dev/null; then
    run_step "Updating uv itself..." "uv self update"
    run_step "Upgrading uv-managed tools..." "uv tool upgrade --all 2>/dev/null || true"
else
    skip_msg "uv"
fi
if command -v pipx &>/dev/null; then
    run_step "Upgrading pipx tools..." "pipx upgrade-all"
else
    skip_msg "pipx"
fi
if command -v pip3 &>/dev/null; then
    run_step "Upgrading pip itself..." "python3 -m pip install --upgrade pip"
else
    skip_msg "pip3"
fi

# ============================================
# 4. RUBY
# ============================================
section "Ruby"
if command -v gem &>/dev/null; then
    run_step "Updating RubyGems system..." "gem update --system"
else
    skip_msg "gem"
fi

# ============================================
# 5. RUST
# ============================================
section "Rust"
if command -v rustup &>/dev/null; then
    run_step "Updating Rust toolchains..." "rustup update"
else
    skip_msg "rustup"
fi

# ============================================
# 6. GO
# ============================================
section "Go"
if command -v go &>/dev/null; then
    run_step "Cleaning Go module cache..." "go clean -modcache"
    printf "  ${c_dim}○ Go binary managed by brew/system package manager${c_reset}\n"
else
    skip_msg "go"
fi

# ============================================
# 7. SHELL
# ============================================
section "Shell"
if [[ -d "$HOME/.oh-my-zsh" ]] && command -v omz &>/dev/null; then
    run_step "Updating Oh My Zsh..." "omz update --unattended 2>/dev/null"
else
    skip_msg "Oh My Zsh"
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo "  ${c_green}${c_bold}✓ Update complete${c_reset}  ${c_dim}$(date '+%H:%M:%S')${c_reset}"
echo ""

if [[ $INTERACTIVE -eq 1 ]]; then
    read -n 1 -s -r -p "  ${c_dim}Press any key to continue...${c_reset}"
    echo ""
fi
