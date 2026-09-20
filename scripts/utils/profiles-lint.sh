#!/usr/bin/env bash
# claw profiles lint — mechanically validate all profile meta.zsh files.
#
# meta.zsh is the registry's data source (scripts/utils/registry.sh parses it
# with one awk pass over ^PROFILE_([A-Z_]+)="([^"]*)"), so the grammar is part
# of the contract, not a style preference: one field per line, double quotes,
# value on the same line, optional trailing comment.
#
# Checks: the line grammar above, the required identity fields
# (PROFILE_GLYPH / PROFILE_DESC non-empty, PROFILE_TIER in 1-6, glyphs unique
# across the tree), declared PROFILE_TOOLCHAIN resolves on disk (or is empty),
# a help cmd is discoverable, PROFILE_KEY_TOOLS or a bespoke tool_check exists,
# every profile declares PROFILE_START_DIR with a known @token, no profile file
# hand-rolls a top-level `cd` (relocation is declarative — see
# shell/profile-helpers.zsh), each dispatcher parses under `zsh -n`, and
# finally `registry.sh check` when that script is present.
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
PROFILES_DIR="$DOTFILES/shell/profiles"
INSTALL_DIR="$DOTFILES/scripts/install"

# The one grammar the awk registry parser and this lint both assume.
META_LINE_RE='^PROFILE_[A-Z_]+="[^"]*"[[:space:]]*(#.*)?$'

fail=0
note() { printf '  ✗ %s: %s\n' "$1" "$2" >&2; fail=1; }

# field <meta> <NAME> — the declared value, without sourcing (meta.zsh is zsh).
field() { sed -n "s/^PROFILE_$2=\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

declare -a glyph_owner=()   # parallel arrays: bash 3.2 has no assoc arrays
declare -a glyph_value=()

for meta in "$PROFILES_DIR"/*/meta.zsh; do
    [[ -f "$meta" ]] || continue
    name="$(basename "$(dirname "$meta")")"
    tc="$(field "$meta" TOOLCHAIN)"
    keytools="$(field "$meta" KEY_TOOLS)"
    helpcmd="$(field "$meta" HELP_CMD)"
    glyph="$(field "$meta" GLYPH)"
    desc="$(field "$meta" DESC)"
    tier="$(field "$meta" TIER)"
    startdir=""; cand=""; pf=""; lineno=0; line=""; i=0
    declare -a _cands=()

    # ── grammar: every non-blank, non-comment line is one quoted assignment ──
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ ! "$line" =~ $META_LINE_RE ]]; then
            note "$name" "meta.zsh line $lineno breaks the PROFILE_X=\"…\" grammar: $line"
        fi
    done < "$meta"

    # ── required identity fields (registry columns) ──
    if ! grep -qE '^PROFILE_GLYPH=' "$meta"; then
        note "$name" "no PROFILE_GLYPH (one Nerd Font glyph, unique across the tree)"
    elif [[ -z "$glyph" ]]; then
        note "$name" "empty PROFILE_GLYPH (one Nerd Font glyph, unique across the tree)"
    else
        for ((i = 0; i < ${#glyph_value[@]}; i++)); do
            if [[ "${glyph_value[$i]}" == "$glyph" ]]; then
                note "$name" "duplicate PROFILE_GLYPH '$glyph' (already used by ${glyph_owner[$i]})"
                break
            fi
        done
        glyph_value+=("$glyph"); glyph_owner+=("$name")
    fi

    if ! grep -qE '^PROFILE_DESC=' "$meta"; then
        note "$name" "no PROFILE_DESC (≤40 chars, never names a sibling profile)"
    elif [[ -z "$desc" ]]; then
        note "$name" "empty PROFILE_DESC (≤40 chars, never names a sibling profile)"
    fi

    case "$tier" in
        [1-6]) ;;
        "")    note "$name" "no PROFILE_TIER (1 core · 2 domain · 3 agent · 4 knowledge · 5 customer · 6 hardware)" ;;
        *)     note "$name" "PROFILE_TIER=$tier out of range (1-6)" ;;
    esac

    if [[ -n "$tc" && ! -f "$INSTALL_DIR/$tc" ]]; then
        note "$name" "declares PROFILE_TOOLCHAIN=$tc but $INSTALL_DIR/$tc is missing"
    fi
    # Start dir must be DECLARED (empty value = "stay put" is a valid answer,
    # a missing line means the profile never considered it).
    if ! grep -q '^PROFILE_START_DIR=' "$meta"; then
        note "$name" "no PROFILE_START_DIR (declare it, even as \"\" for stay-put)"
    else
        startdir="$(field "$meta" START_DIR)"
        # Only @vault, @vault-folder and @vault:<Folder> are resolvable tokens.
        IFS='|' read -ra _cands <<< "$startdir"
        for cand in "${_cands[@]}"; do
            cand="${cand#"${cand%%[![:space:]]*}"}"   # ltrim
            cand="${cand%"${cand##*[![:space:]]}"}"   # rtrim
            case "$cand" in
                @vault|@vault-folder|@vault:?*) ;;
                @*) note "$name" "unknown PROFILE_START_DIR token: $cand" ;;
            esac
        done
    fi

    # A top-level `cd` in any profile file is the old footgun — relocation goes
    # through PROFILE_START_DIR so it is visible, reversible and opt-out-able.
    for pf in "$PROFILES_DIR/$name"/*.zsh "$PROFILES_DIR/$name.zsh"; do
        [[ -f "$pf" ]] || continue
        if grep -qE '^cd[[:space:]]' "$pf"; then
            note "$name" "top-level 'cd' in ${pf##*/} — declare PROFILE_START_DIR instead"
        fi
    done

    # The dispatcher must at least parse; a syntax error there kills the load.
    if command -v zsh >/dev/null 2>&1 && [[ -f "$PROFILES_DIR/$name.zsh" ]]; then
        zsh -n "$PROFILES_DIR/$name.zsh" 2>/dev/null \
            || note "$name" "$name.zsh does not parse under zsh -n"
    fi

    if [[ -z "$keytools" && -z "$helpcmd" ]]; then
        # profile must offer at least a key-tool list or an explicit help cmd
        common="$PROFILES_DIR/$name/common.zsh"
        grep -qE "^\s*${name}-help\s*\(\)|_${name}_tool_check\s*\(\)" "$common" 2>/dev/null \
            || note "$name" "no PROFILE_KEY_TOOLS, PROFILE_HELP_CMD, or ${name}-help/_${name}_tool_check"
    fi
done

# The registry is the downstream consumer of everything above — let it have the
# last word (cross-source duplicate ids/aliases/glyphs, dispatch coverage).
registry="$DOTFILES/scripts/utils/registry.sh"
if [[ -x "$registry" ]]; then
    "$registry" check || { printf '  ✗ registry: registry.sh check failed\n' >&2; fail=1; }
fi

if (( fail )); then
    printf '\n  profiles lint: FAIL\n' >&2
    exit 1
fi
printf '  profiles lint: all profiles valid\n'
