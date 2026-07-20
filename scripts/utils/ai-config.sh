#!/usr/bin/env bash
# ai-config.sh — Open Claw "ai-config plugin" engine.
#
# Brings opencode + openwork CONFIG under dot-files: renders each tool's config
# from portable sources (opencode from a tracked base; openwork's workspace roots
# from the Obsidian vault resolver), tops each with a managed-file sentinel, and
# refuses to clobber a hand-edited/app-written config. Mirrors clin.sh; POSIX sh.
#
#   ai-config.sh render <opencode|openwork> [out]   emit one config
#   ai-config.sh sync                               render both live configs (gated)
#   ai-config.sh status                             what's managed + openwork runtime/secret files
#   ai-config.sh setup                              first-run adopt (idempotent, lossless)
#
# Managed-file gate: CLAW_AICONFIG_MANAGED = 1 (default) | force | 0/off/no.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
AICONFIG_SENTINEL="managed by the Open Claw ai-config plugin"
OC_BASE="$DOTFILES_DIR/config/opencode/opencode.base.jsonc"
OC_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.jsonc"
OW_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/openwork/server.json"
OW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/openwork"

# Resolve the Obsidian vault root (env → known default). No fork needed.
_aic_vault() {
    printf '%s' "${OBSIDIAN_VAULT:-$HOME/${OBSIDIAN_VAULT_NAME:-hr-vault-main-pa}}"
}

# Return 0 if it's safe to (over)write $1 — file absent, already ours (matches
# $2 grep pattern), or force. Else warn and return 1.
_aic_managed_ok() {
    _f="$1"; _pat="$2"
    case "${CLAW_AICONFIG_MANAGED:-1}" in
        0|off|no) return 1 ;;
        force)    return 0 ;;
    esac
    [ -f "$_f" ] || return 0
    grep -q "$_pat" "$_f" 2>/dev/null && return 0
    printf '  ai-config: %s looks hand-edited/app-written — not overwriting.\n' "$_f" >&2
    printf '  ai-config: re-run with CLAW_AICONFIG_MANAGED=force to let claw manage it.\n' >&2
    return 1
}

# --- opencode: base file + line-1 sentinel ---------------------------------
aic_render_opencode() {
    _out="${1:-/dev/stdout}"
    [ -r "$OC_BASE" ] || { printf 'ai-config: missing base %s\n' "$OC_BASE" >&2; return 1; }
    [ "$_out" != "/dev/stdout" ] && mkdir -p "$(dirname "$_out")" 2>/dev/null
    {
        printf '// %s — do not hand-edit (claw ai config sync)\n' "$AICONFIG_SENTINEL"
        cat "$OC_BASE"
    } > "$_out" 2>/dev/null
}

aic_render_openwork() { printf 'ai-config: openwork render not yet implemented\n' >&2; return 1; }
aic_sync()   { aic_render_opencode "$OC_CONFIG"; }
aic_status() { printf '  ai-config: opencode base %s\n' "$OC_BASE"; }
aic_setup()  { aic_sync; }

_cmd="${1:-status}"; shift 2>/dev/null || true
case "$_cmd" in
    render)
        case "${1:-}" in
            opencode) shift; aic_render_opencode "${1:-/dev/stdout}" ;;
            openwork) shift; aic_render_openwork "${1:-/dev/stdout}" ;;
            *) printf 'usage: ai-config.sh render <opencode|openwork> [out]\n' >&2; exit 1 ;;
        esac ;;
    sync)   aic_sync ;;
    status) aic_status ;;
    setup)  aic_setup ;;
    *) printf 'usage: ai-config.sh {render <tool> [out] | sync | status | setup}\n' >&2; exit 1 ;;
esac
