# ============================================
# CLIN PLUGIN  (Obsidian sub-profile)
# ============================================
# clin (reekta92/clin-rs) is a TUI note manager inspired by Obsidian. This
# module is the interactive half of the "clin plugin": it rides on top of
# shell/obsidian.zsh (sourced just before this file) and REUSES its resolvers —
#   _claw_obsidian_vault   → vault root
#   _claw_obsidian_folder  → active profile's folder in the vault
#   _claw_obsidian_dir     → the two joined
# so `cl`/`cln` open clin in the SAME profile-scoped folder that `o`/`on`/`os`
# target. The engine (scripts/utils/clin.sh) renders clin's config.toml from the
# active theme + vault, so colors and vault stay in lockstep with the rest of
# Open Claw. Everything is guarded: missing clin just prints an install hint.

CLAW_CLIN_ENGINE="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils/clin.sh"
CLAW_CLIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/clin/config.toml"

# Guard helper: clin present? Otherwise nudge toward the toolchain installer.
_claw_clin_have() {
    if command -v clin &>/dev/null; then
        return 0
    fi
    printf "  \e[38;2;255;123;114m✗\e[0m clin not installed — \e[1mclaw clin install\e[0m (or \`claw install cortex\`)\n" >&2
    return 1
}

# cl: launch clin in the ACTIVE profile-scoped folder. Renders a per-shell
# ephemeral config (theme + this shell's vault/folder) and launches via
# `clin --config`, so it never clobbers the persistent config and two shells on
# different profiles don't fight over one file.
function cl() {
    _claw_clin_have || return 1
    local vault folder tmp
    if typeset -f _claw_obsidian_vault &>/dev/null; then
        vault="$(_claw_obsidian_vault)"
        folder="$(_claw_obsidian_folder)"
        mkdir -p "$vault/$folder" 2>/dev/null
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/clin-cfg.XXXXXX")" || { clin; return; }
    bash "$CLAW_CLIN_ENGINE" render "$tmp" "$vault" "$folder" 2>/dev/null
    clin --config "$tmp" "$@"
    rm -f "$tmp" 2>/dev/null
}

# cln: new note in the active profile folder (mirrors `on`), then open clin.
# Usage: cln "Note Name"
function cln() {
    local note_name="$1"
    if [[ -z "$note_name" ]]; then
        echo "Usage: cln \"Note Name\""
        return 1
    fi
    _claw_clin_have || return 1
    local dir note
    dir="$(_claw_obsidian_dir 2>/dev/null)" || dir="$PWD"
    mkdir -p "$dir"
    note="$dir/$note_name.md"
    if [[ ! -f "$note" ]]; then
        printf "# %s\n\nCreated: %s\n" "$note_name" "$(date '+%Y-%m-%d %H:%M')" > "$note"
        echo "  ✓ created $note_name.md (in $(_claw_obsidian_folder 2>/dev/null))"
    fi
    cl
}

# clin-sync: re-render the persistent ~/.config/clin/config.toml from the
# active theme + vault (also runs automatically on `claw theme set`).
function clin-sync() { bash "$CLAW_CLIN_ENGINE" sync; }

# clin-help: one-screen reference card (GitHub-dark palette).
function clin-help() {
    print -P ""
    print -P "  %F{39c5ff}clin%f %F{8b949e}— Obsidian-style note TUI, scoped to your active profile%f"
    print -P "  %F{30363d}────────────────────────────────────────────────────────%f"
    print -P "  %F{3fb950}cl%f                 open clin in the active profile folder"
    print -P "  %F{3fb950}cln%f %F{8b949e}\"Title\"%f       new note in that folder, then open clin"
    print -P "  %F{3fb950}clin-sync%f          re-theme + re-vault ~/.config/clin/config.toml"
    print -P "  %F{3fb950}claw clin setup%f    install clin-rs + sync config"
    print -P ""
    print -P "  %F{8b949e}folder follows %F{c9d1d9}\$CLAW_ACTIVE_PROFILE%f%F{8b949e} (override per-shell with %F{c9d1d9}ovuse%f%F{8b949e})%f"
    print -P "  %F{8b949e}colors follow %F{c9d1d9}claw theme%f%F{8b949e}; opt out with %F{c9d1d9}CLAW_CLIN_MANAGED=0%f"
    print -P ""
}
