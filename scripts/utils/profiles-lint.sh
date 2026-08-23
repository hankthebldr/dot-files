#!/usr/bin/env bash
# claw profiles lint — mechanically validate all profile meta.zsh files.
# Checks: declared PROFILE_TOOLCHAIN resolves on disk (or is empty), a help cmd
# is discoverable, PROFILE_KEY_TOOLS or a bespoke tool_check exists, every
# profile declares PROFILE_START_DIR with a known @token, and no profile file
# hand-rolls a top-level `cd` (relocation is declarative — see
# shell/profile-helpers.zsh).
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
PROFILES_DIR="$DOTFILES/shell/profiles"
INSTALL_DIR="$DOTFILES/scripts/install"

fail=0
note() { printf '  ✗ %s: %s\n' "$1" "$2" >&2; fail=1; }

for meta in "$PROFILES_DIR"/*/meta.zsh; do
    [[ -f "$meta" ]] || continue
    name="$(basename "$(dirname "$meta")")"
    # Extract declared values without sourcing (avoid zsh-only syntax under bash).
    tc="$(sed -n 's/^PROFILE_TOOLCHAIN="\([^"]*\)".*/\1/p' "$meta" | head -1)"
    keytools="$(sed -n 's/^PROFILE_KEY_TOOLS="\([^"]*\)".*/\1/p' "$meta" | head -1)"
    helpcmd="$(sed -n 's/^PROFILE_HELP_CMD="\([^"]*\)".*/\1/p' "$meta" | head -1)"
    startdir=""; cand=""; pf=""; declare -a _cands=()

    if [[ -n "$tc" && ! -f "$INSTALL_DIR/$tc" ]]; then
        note "$name" "declares PROFILE_TOOLCHAIN=$tc but $INSTALL_DIR/$tc is missing"
    fi
    # Start dir must be DECLARED (empty value = "stay put" is a valid answer,
    # a missing line means the profile never considered it).
    if ! grep -q '^PROFILE_START_DIR=' "$meta"; then
        note "$name" "no PROFILE_START_DIR (declare it, even as \"\" for stay-put)"
    else
        startdir="$(sed -n 's/^PROFILE_START_DIR="\([^"]*\)".*/\1/p' "$meta" | head -1)"
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

    if [[ -z "$keytools" && -z "$helpcmd" ]]; then
        # profile must offer at least a key-tool list or an explicit help cmd
        common="$PROFILES_DIR/$name/common.zsh"
        grep -qE "^\s*${name}-help\s*\(\)|_${name}_tool_check\s*\(\)" "$common" 2>/dev/null \
            || note "$name" "no PROFILE_KEY_TOOLS, PROFILE_HELP_CMD, or ${name}-help/_${name}_tool_check"
    fi
done

if (( fail )); then
    printf '\n  profiles lint: FAIL\n' >&2
    exit 1
fi
printf '  profiles lint: all profiles valid\n'
