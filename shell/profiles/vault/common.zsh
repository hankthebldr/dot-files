# shell/profiles/vault/common.zsh
# Aliases / functions / help — work identically on macOS and Linux.
# Builds ON TOP OF the global shell/obsidian.zsh module (which provides
# o/on/os/ov/otoday/ocapture/ovaults/ovuse and the _CLAW_OBSIDIAN_VAULTS map).


# ==========================================
# VAULT-NATIVE ALIASES
# ==========================================
# These complement (not replace) the global o/on/os/ov family in obsidian.zsh.

# --- Quick render / preview ---
# Show a vault note pretty-printed in glow; falls back to bat if glow missing
vshow() {
    local target="${1:?usage: vshow <path-or-pattern>}"
    local note
    if [[ -f "$target" ]]; then
        note="$target"
    else
        # Search the active vault by basename pattern
        note="$(find "$(_claw_obsidian_vault)" -name "*${target}*.md" -print -quit 2>/dev/null)"
    fi
    [[ -z "$note" ]] && { echo "no match: $target" >&2; return 1; }
    if command -v glow &>/dev/null; then
        glow -p "$note"
    elif command -v bat &>/dev/null; then
        bat "$note"
    else
        cat "$note"
    fi
}

# --- Frontmatter inspection ---
# Show YAML frontmatter of a note (everything between the first two `---` lines)
vmeta() {
    local note="${1:?usage: vmeta <note.md>}"
    awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$note"
}

# --- Tag listing ---
# All unique tags across the vault (frontmatter + inline #tag)
vtags() {
    local vault="$(_claw_obsidian_vault)"
    {
        # Frontmatter tags
        find "$vault" -name "*.md" -print0 2>/dev/null \
            | xargs -0 awk '/^tags:/,/^[^[:space:]-]/{ print }' 2>/dev/null \
            | command grep -oE '[a-zA-Z][a-zA-Z0-9/_-]+' 2>/dev/null
        # Inline #tags
        rg -oh '#[a-zA-Z][a-zA-Z0-9/_-]+' "$vault" 2>/dev/null | sed 's/^#//'
    } | sort -u | head -50
}

# --- Backlinks ---
# Notes that link to the given note
vlinks() {
    local needle="${1:?usage: vlinks <note-basename-without-ext>}"
    local vault="$(_claw_obsidian_vault)"
    rg -l "\[\[${needle}(\||\])" "$vault" 2>/dev/null
}

# --- Orphans ---
# Notes that no other note links to (candidates for cleanup or promotion)
vorphans() {
    local vault="$(_claw_obsidian_vault)"
    find "$vault" -name "*.md" -print0 2>/dev/null | while IFS= read -r -d '' note; do
        local base="${note##*/}"; base="${base%.md}"
        if ! rg -q "\[\[${base}(\||\])" "$vault"; then
            echo "${note#$vault/}"
        fi
    done
}

# --- Inbox shortcuts ---
# Jump to inbox folder of the active vault (where capture lands)
vinbox() {
    local vault="$(_claw_obsidian_vault)"
    local inbox
    for candidate in "00-Inbox" "0_Inbox" "inbox" "Inbox" "_inbox"; do
        if [[ -d "$vault/$candidate" ]]; then
            inbox="$vault/$candidate"
            break
        fi
    done
    if [[ -z "$inbox" ]]; then
        echo "no inbox dir found in $vault (looked for 00-Inbox, 0_Inbox, inbox, Inbox)" >&2
        return 1
    fi
    cd "$inbox" || return 1
    ls -lt | head -20
}

# ==========================================
# QUICK REFERENCE
# ==========================================
vault-help() {
    local green='\e[38;2;57;255;20m'         # dosbbs theme green
    local amber='\e[38;2;255;176;0m'
    local cyan='\e[38;2;0;170;170m'
    local dim='\e[38;2;128;128;128m'
    local white='\e[38;2;220;255;220m'
    local bold='\e[1m'
    local reset='\e[0m'

    printf "\n"
    printf "  ${amber}${bold}╭──────────────────────────────────────────────────────────╮${reset}\n"
    printf "  ${amber}${bold}│  KNOWLEDGE-KEEPER — Vault profile  (${PROFILE_OS_SUPPORT})       │${reset}\n"
    printf "  ${amber}${bold}╰──────────────────────────────────────────────────────────╯${reset}\n"
    printf "\n"
    printf "  ${bold}${cyan}Vault root${reset}    ${white}$(_claw_obsidian_vault 2>/dev/null || echo "(not set)")${reset}\n"
    printf "\n"
    printf "  ${bold}Navigate${reset}  ${dim}(from global obsidian.zsh)${reset}\n"
    printf "  ${green}o${reset}         ${dim}cd \$(vault) && ls -lt${reset}\n"
    printf "  ${green}obs${reset}       ${dim}open Obsidian app${reset}\n"
    printf "  ${green}on${reset} TITLE  ${dim}new note (top-level)${reset}\n"
    printf "  ${green}os${reset} QUERY  ${dim}search notes by content (rg)${reset}\n"
    printf "  ${green}ov${reset} TITLE  ${dim}view note (\$EDITOR)${reset}\n"
    printf "  ${green}otoday${reset}    ${dim}open/create today's daily note${reset}\n"
    printf "  ${green}ocapture${reset}  ${dim}quick-capture into 00-Inbox/${reset}\n"
    printf "  ${green}ovaults${reset}   ${dim}list sub-vaults; mark active${reset}\n"
    printf "  ${green}ovuse${reset} V   ${dim}switch active sub-vault for this shell${reset}\n"
    printf "\n"
    printf "  ${bold}Inspect${reset}  ${dim}(vault profile additions)${reset}\n"
    printf "  ${green}vshow${reset} PAT     ${dim}render note in glow/bat${reset}\n"
    printf "  ${green}vmeta${reset} NOTE    ${dim}extract YAML frontmatter${reset}\n"
    printf "  ${green}vtags${reset}         ${dim}all unique tags${reset}\n"
    printf "  ${green}vlinks${reset} NAME   ${dim}notes that link to NAME${reset}\n"
    printf "  ${green}vorphans${reset}      ${dim}notes nobody links to${reset}\n"
    printf "  ${green}vinbox${reset}        ${dim}cd to 00-Inbox/${reset}\n"
    printf "\n"
    printf "  ${bold}Per-OS extras${reset}\n"
    printf "  ${dim}see ${OS_FAMILY:-?}.zsh — Mac uses mdfind (Spotlight); Linux uses rg-only${reset}\n"
    printf "\n"
}

# Tool-availability check — install hint comes from {mac,linux}.zsh
_vault_tool_check() {
    local green='\e[38;2;57;255;20m'
    local red='\e[38;2;255;100;100m'
    local white='\e[38;2;220;255;220m'
    local dim='\e[38;2;128;128;128m'
    local bold='\e[1m'
    local reset='\e[0m'

    local -a tools=(
        "rg:ripgrep" "fzf:fzf" "glow:glow" "bat:bat"
        "pandoc:pandoc" "yq:yq"
    )
    local found=0 missing=0
    local total=${#tools[@]}

    printf "\n  ${bold}${white}KNOWLEDGE-KEEPER Toolchain${reset}  ${dim}(${OS_FAMILY:-?})${reset}\n"
    printf "  ${dim}─────────────────────────${reset}\n"
    for entry in "${tools[@]}"; do
        local cmd="${entry%%:*}"
        local pkg="${entry##*:}"
        if command -v "$cmd" &>/dev/null; then
            printf "  ${green}●${reset}  ${white}%-10s${reset}\n" "$cmd"
            ((found++))
        else
            printf "  ${red}✗${reset}  ${white}%-10s${reset}  ${dim}→ $(_vault_install_hint "$pkg")${reset}\n" "$cmd"
            ((missing++))
        fi
    done
    printf "\n  ${dim}${found}/${total} available${reset}"
    (( missing > 0 )) && printf " ${red}(${missing} missing)${reset}"
    printf "\n\n"
}
