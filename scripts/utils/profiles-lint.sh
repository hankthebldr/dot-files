#!/usr/bin/env bash
# claw profiles lint — mechanically validate all profile meta.zsh files.
# Checks: declared PROFILE_TOOLCHAIN resolves on disk (or is empty), a help cmd
# is discoverable, PROFILE_KEY_TOOLS or a bespoke tool_check exists.
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

    if [[ -n "$tc" && ! -f "$INSTALL_DIR/$tc" ]]; then
        note "$name" "declares PROFILE_TOOLCHAIN=$tc but $INSTALL_DIR/$tc is missing"
    fi
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
