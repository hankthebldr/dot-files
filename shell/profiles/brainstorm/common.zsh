# shell/profiles/brainstorm/common.zsh
# Ideation mode — capture sparks before they cool. OS-agnostic core.

export CLAW_PROFILE_THEME="brainstorm"

# Where today's brainstorm log lives. Append-only by design.
BRAINSTORM_ROOT="${BRAINSTORM_ROOT:-$(_claw_obsidian_vault 2>/dev/null || echo "$HOME")/_brainstorm}"

# ==========================================
# CAPTURE — fast, append-only
# ==========================================

# Drop a one-liner into today's spark log. No editor, no friction.
# Usage: spark "idea about cortex onboarding telemetry"
spark() {
    local idea="$*"
    [[ -z "$idea" ]] && { echo "usage: spark <text>" >&2; return 1; }
    mkdir -p "$BRAINSTORM_ROOT"
    local log="$BRAINSTORM_ROOT/$(date +%Y-%m-%d).md"
    [[ ! -f "$log" ]] && printf '# brainstorm · %s\n\n' "$(date +%Y-%m-%d)" > "$log"
    printf -- '- `%s` %s\n' "$(date +%H:%M)" "$idea" >> "$log"
    printf '  \e[38;2;255;0;220m→\e[0m %s\n' "$log"
}

# Open today's log in $EDITOR for a longer riff
bm() {
    mkdir -p "$BRAINSTORM_ROOT"
    local log="$BRAINSTORM_ROOT/$(date +%Y-%m-%d).md"
    [[ ! -f "$log" ]] && printf '# brainstorm · %s\n\n## seed\n\n## sparks\n\n' "$(date +%Y-%m-%d)" > "$log"
    ${EDITOR:-vim} "$log"
}

# Search across all brainstorm logs (filtered by content match)
bmsearch() {
    local query="${1:-}"
    [[ -z "$query" ]] && { echo "usage: bmsearch <pattern>" >&2; return 1; }
    rg --color=always -A 2 -B 1 "$query" "$BRAINSTORM_ROOT" 2>/dev/null | less -R
}

# Pick a past log via fzf
bmpick() {
    local pick
    pick=$(find "$BRAINSTORM_ROOT" -name "*.md" 2>/dev/null \
        | sort -r \
        | fzf --preview 'glow -s dark {} 2>/dev/null || bat --color=always {} || cat {}' \
              --preview-window=right:60% \
              --header="brainstorm logs (newest first)")
    [[ -n "$pick" ]] && ${EDITOR:-vim} "$pick"
}

# ==========================================
# MIND MAPPING
# ==========================================

# Render a markdown file as a mind map via markmap (HTML). Opens in browser.
mindmap() {
    local src="${1:?usage: mindmap <markdown-file>}"
    if ! command -v markmap &>/dev/null; then
        echo "needs markmap: npm i -g markmap-cli" >&2
        return 1
    fi
    markmap "$src" --no-open
    echo "rendered → ${src%.md}.html  (open with: vopen ${src%.md}.html)"
}

# ==========================================
# SEED — random prompt to riff on
# ==========================================
# Pulls a random line from $BRAINSTORM_ROOT/_prompts.txt if it exists, else
# uses the built-in fallback. Add your own prompts to that file over time.
seed() {
    local prompts_file="$BRAINSTORM_ROOT/_prompts.txt"
    local prompts
    if [[ -f "$prompts_file" ]]; then
        prompts=$(shuf -n 1 "$prompts_file" 2>/dev/null || sort -R "$prompts_file" | head -1)
    else
        local -a builtin=(
            "if this stopped working tomorrow, what would I miss most?"
            "what's the version of this that I'd be embarrassed to ship?"
            "who's the smallest possible audience that finds this useful?"
            "what would the AI version of this look like that I'd actually use?"
            "what's the smallest change that doubles its value?"
            "if I had to teach this to a 12-year-old, what would I cut?"
            "what assumption am I making that's probably wrong?"
            "what would the inverse of this look like?"
        )
        prompts="${builtin[$((RANDOM % ${#builtin[@]} + 1))]}"
    fi
    printf '\e[38;2;255;0;220m▶\e[0m \e[1m%s\e[0m\n' "$prompts"
}

# ==========================================
# BRAINSTORM SKILL HANDOFF (Claude)
# ==========================================
# Hands off to product-management:brainstorm skill via claude CLI.
# Requires `claude` to be on PATH and the skill plugin enabled.
huh() {
    local topic="$*"
    [[ -z "$topic" ]] && { echo "usage: huh <topic-or-question>" >&2; return 1; }
    if ! command -v claude &>/dev/null; then
        echo "needs claude CLI on PATH" >&2; return 1
    fi
    claude "/brainstorm $topic"
}

# ==========================================
# QUICK REFERENCE
# ==========================================
brainstorm-help() {
    # vhs theme palette
    local pink='\e[38;2;255;0;220m'
    local cyan='\e[38;2;0;220;255m'
    local yellow='\e[38;2;255;240;0m'
    local dim='\e[38;2;120;100;120m'
    local white='\e[38;2;240;240;220m'
    local bold='\e[1m'
    local reset='\e[0m'

    printf "\n"
    printf "  ${pink}${bold}╭──────────────────────────────────────────────────────────╮${reset}\n"
    printf "  ${pink}${bold}│  SPARK-CATCHER — Brainstorm profile  (${PROFILE_OS_SUPPORT})    │${reset}\n"
    printf "  ${pink}${bold}╰──────────────────────────────────────────────────────────╯${reset}\n"
    printf "\n"
    printf "  ${bold}${cyan}Logs root${reset}    ${white}${BRAINSTORM_ROOT}${reset}\n"
    printf "\n"
    printf "  ${bold}Capture${reset}\n"
    printf "  ${pink}spark${reset} ...     ${dim}one-liner → today's log (no editor)${reset}\n"
    printf "  ${pink}bm${reset}            ${dim}open today's log in \$EDITOR${reset}\n"
    printf "  ${pink}bmsearch${reset} PAT  ${dim}rg over all logs${reset}\n"
    printf "  ${pink}bmpick${reset}        ${dim}fzf pick past log + preview${reset}\n"
    printf "\n"
    printf "  ${bold}Riff${reset}\n"
    printf "  ${pink}seed${reset}          ${dim}random prompt to spark on${reset}\n"
    printf "  ${pink}mindmap${reset} FILE  ${dim}markmap → HTML mind-map${reset}\n"
    printf "  ${pink}huh${reset} TOPIC     ${dim}hand off to /brainstorm skill in claude${reset}\n"
    printf "\n"
    printf "  ${bold}Per-OS extras${reset}\n"
    printf "  ${dim}see ${OS_FAMILY:-?}.zsh — Mac: Granola/voice; Linux: sox/audacity${reset}\n"
    printf "\n"
    printf "  ${yellow}tip${reset}   ${dim}three sparks/day beats one polished idea/week${reset}\n"
    printf "\n"
}
