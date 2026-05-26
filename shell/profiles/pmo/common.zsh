# shell/profiles/pmo/common.zsh
# Project management orchestration. OS-agnostic helpers; per-OS bits (Things 3
# vs taskwarrior) live in {mac,linux}.zsh.

export CLAW_PROFILE_THEME="pmo"

# Where notes about the active sprint / plan live (vault-bound)
PMO_NOTES_ROOT="${PMO_NOTES_ROOT:-$(_claw_obsidian_vault 2>/dev/null || echo "$HOME")/_pmo}"

# ==========================================
# GIT + GH HELPERS (cross-platform)
# ==========================================

# Generate a standup blurb from yesterday's commits across active repos.
# Output format: "did / doing / blocked" — paste straight into Slack/Things 3.
standup() {
    local since="${1:-yesterday}"
    local repos=("${PMO_REPOS[@]:-$(pwd)}")
    echo "─── standup ($since → now) ───"
    echo ""
    echo "did:"
    local repo
    for repo in "${repos[@]}"; do
        [[ -d "$repo/.git" ]] || continue
        local commits
        commits=$(git -C "$repo" log --since="$since" --author="$(git -C "$repo" config user.email)" \
                  --pretty=format:'  - %s' 2>/dev/null)
        [[ -n "$commits" ]] && { echo "  · $(basename "$repo"):"; echo "$commits" | sed 's/^/  /'; }
    done
    echo ""
    echo "doing:"
    echo "  · (from Things 3 Today list — see \`today\` alias)"
    echo ""
    echo "blocked:"
    echo "  · (none / fill in)"
}

# List open PRs across configured repos
prs() {
    if ! command -v gh &>/dev/null; then
        echo "needs gh CLI" >&2; return 1
    fi
    local repos=("${PMO_REPOS[@]:-$(pwd)}")
    local repo
    for repo in "${repos[@]}"; do
        [[ -d "$repo/.git" ]] || continue
        echo "── $(basename "$repo") ──"
        gh pr list --repo "$(cd "$repo" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
            --state open --json number,title,author --template \
            '{{range .}}{{printf "  #%v" .number}} {{.title}} ({{.author.login}}){{"\n"}}{{end}}' 2>/dev/null
    done
}

# ==========================================
# SPRINT NOTES (vault-backed)
# ==========================================

# Create or open the current week's sprint note
sprint() {
    mkdir -p "$PMO_NOTES_ROOT"
    local week; week="$(date +%Y-W%V)"
    local note="$PMO_NOTES_ROOT/sprint-${week}.md"
    if [[ ! -f "$note" ]]; then
        cat > "$note" <<EOF
# sprint · ${week} · ($(date +%Y-%m-%d))

## goals (set Monday)

## carryover

## blockers

## decisions made

## demoable by friday
EOF
    fi
    ${EDITOR:-vim} "$note"
}

# ==========================================
# QUICK REFERENCE
# ==========================================
pmo-help() {
    # dosbbs theme palette (amber/cyan)
    local amber='\e[38;2;255;176;0m'
    local cyan='\e[38;2;0;170;170m'
    local green='\e[38;2;0;170;0m'
    local dim='\e[38;2;128;128;128m'
    local white='\e[38;2;255;255;255m'
    local bold='\e[1m'
    local reset='\e[0m'

    printf "\n"
    printf "  ${amber}${bold}╭──────────────────────────────────────────────────────────╮${reset}\n"
    printf "  ${amber}${bold}│  SCRIBE-OPERATOR — PMO profile  (${PROFILE_OS_SUPPORT})        │${reset}\n"
    printf "  ${amber}${bold}╰──────────────────────────────────────────────────────────╯${reset}\n"
    printf "\n"
    printf "  ${bold}${cyan}Notes root${reset}   ${white}${PMO_NOTES_ROOT}${reset}\n"
    printf "\n"
    printf "  ${bold}Things 3 / Tasks${reset}  ${dim}(per-OS — see ${OS_FAMILY:-?}.zsh)${reset}\n"
    printf "  ${green}today${reset}        ${dim}list today's tasks${reset}\n"
    printf "  ${green}inbox${reset}        ${dim}list inbox${reset}\n"
    printf "  ${green}tadd${reset} TITLE   ${dim}add to inbox${reset}\n"
    printf "  ${green}tdone${reset} N      ${dim}mark task complete${reset}\n"
    printf "\n"
    printf "  ${bold}Rhythm${reset}\n"
    printf "  ${green}standup${reset}      ${dim}generate \"did/doing/blocked\" from git${reset}\n"
    printf "  ${green}sprint${reset}       ${dim}open this week's sprint note${reset}\n"
    printf "  ${green}prs${reset}          ${dim}open PRs across PMO_REPOS${reset}\n"
    printf "\n"
    printf "  ${bold}Sync${reset}\n"
    printf "  ${green}pmo-sync${reset}     ${dim}invoke /sync-docs skill (repo ↔ Things 3)${reset}\n"
    printf "\n"
    printf "  ${bold}Env${reset}\n"
    printf "  ${white}PMO_REPOS${reset}=${dim}(array of repo paths for standup/prs)${reset}\n"
    printf "  ${white}PMO_NOTES_ROOT${reset}=${dim}${PMO_NOTES_ROOT}${reset}\n"
    printf "\n"
}

# Sync-docs handoff (works on both OSes; the skill itself decides what to do)
pmo-sync() {
    if ! command -v claude &>/dev/null; then
        echo "needs claude CLI" >&2; return 1
    fi
    local target="${1:-$(pwd)}"
    claude "/sync-docs ${target}"
}
