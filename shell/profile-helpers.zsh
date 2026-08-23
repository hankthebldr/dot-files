# shell/profile-helpers.zsh
# Tiny helpers shared across all 9 profiles. Sourced once from .zshrc before
# any profile load.

# _claw_guard <name> <tool> <command...>
#
# If <tool> is on PATH:        defines an alias `name=command...`
# If <tool> is NOT on PATH:    defines a function that prints a helpful
#                              install hint and returns 1.
#
# Usage:
#   _claw_guard nrecon nmap nmap -T4 -A -v
#   _claw_guard sqli  sqlmap sqlmap --batch --random-agent
#   _claw_guard pcap  tcpdump sudo tcpdump -i any
#
# Beats a raw "nmap: command not found" — surfaces the actual missing tool
# AND tells the user how to install it.
_claw_guard() {
    local name="$1" tool="$2"; shift 2
    if command -v "$tool" &>/dev/null; then
        alias "$name=$*"
    else
        eval "$name() {
            printf '  \\e[38;2;255;123;114m✗\\e[0m %s not installed — try: \\e[38;2;201;209;217mbrew install %s\\e[0m\\n' \"$tool\" \"$tool\" >&2
            return 1
        }"
    fi
}

# ── Generic profile tool-check ──────────────────────────────────────────────
# Fallback for profiles that declare PROFILE_KEY_TOOLS but no bespoke
# _<name>_tool_check (blackwell, brainstorm, deck, demo, design, homelab, pmo,
# tunnels). Reports installed/missing for the active profile's key tools.
_claw_profile_tool_check() {
    emulate -L zsh
    local list="${PROFILE_KEY_TOOLS:-}"
    if [[ -z "$list" ]]; then
        printf "  no key tools declared for %s\n" "${CLAW_ACTIVE_PROFILE:-profile}"
        return 0
    fi
    printf "  %s key tools:\n" "${CLAW_ACTIVE_PROFILE:-profile}"
    local bin
    for bin in ${(s: :)list}; do
        if command -v "$bin" &>/dev/null; then
            printf "    \e[38;2;63;185;80m✓\e[0m %s\n" "$bin"
        else
            printf "    \e[38;2;255;123;114m✗\e[0m %s${PROFILE_TOOLCHAIN:+ — claw install ${PROFILE_TOOLCHAIN%-toolchain.sh}}\n" "$bin"
        fi
    done
}

# ── Profile start directories ───────────────────────────────────────────────
# WHERE a profile drops you is DECLARATIVE: every profile's meta.zsh sets
# PROFILE_START_DIR, and the ONE resolver + ONE applier below are consumed by
# every load path (`claw load` in claw-fn.zsh, the fzf welcome TUI, the
# rust-TUI outcome applier). Never hand-roll a top-level `cd` in a profile file
# — `claw profiles lint` fails the tree if you do.
#
# Spec grammar (PROFILE_START_DIR · the override file · $CLAW_START_DIR):
#   ""                no relocation — the profile leaves you where you are
#   ~/path $VAR/path  plain path ($VAR and ~ expanded when the spec is applied)
#   @vault            the Obsidian vault ROOT              (~/hr-vault-main-pa)
#   @vault-folder     vault root + the profile's mapped folder (obsidian.zsh's
#                     _CLAW_OBSIDIAN_FOLDERS: cortex→CORTEX, security→Secops…),
#                     falling back to the vault root when that folder is absent
#   @vault:<Folder>   vault root + an explicit folder
#   a|b|c             candidate list — the FIRST candidate that EXISTS wins, so
#                     one spec covers divergent macOS / Linux layouts
#
# Precedence when loading profile <p>:
#   1. $CLAW_START_DIR                    session override (this shell only)
#   2. ~/.config/claw/start-dirs.conf     per-machine map: `<profile> = <spec>`
#      Machine-local paths belong THERE, not in the tracked repo — same rule as
#      ~/.zshrc.local. See config/claw/start-dirs.conf.example.
#   3. PROFILE_START_DIR                  the profile's declared default
#
# Master switch $CLAW_PROFILE_CD:  1 = always relocate (default)
#                                  0 = never (pure aliases/exports, no cd)
#                                  home = only when the shell sits in $HOME

# Per-machine override map. One `profile = spec` per line, `#` comments ignored.
_claw_start_dir_conf() {
    print -r -- "${XDG_CONFIG_HOME:-$HOME/.config}/claw/start-dirs.conf"
}

# _claw_start_dir_spec [profile] → the winning SPEC (unresolved) on stdout.
_claw_start_dir_spec() {
    emulate -L zsh
    setopt local_options extended_glob
    local p="${1:-${CLAW_ACTIVE_PROFILE:-}}"

    # 1. session override
    if [[ -n "${CLAW_START_DIR:-}" ]]; then
        print -r -- "$CLAW_START_DIR"
        return 0
    fi

    # 2. per-machine map. Profile names are [a-z0-9_-] by contract; anything
    #    else never reaches the sed pattern.
    local conf="$(_claw_start_dir_conf)" line
    if [[ -n "$p" && "$p" == [a-zA-Z0-9_-]## && -r "$conf" ]]; then
        line=$(sed -n -E "s/^[[:space:]]*${p}[[:space:]]*=[[:space:]]*//p" "$conf" 2>/dev/null \
               | tr -d '\r' | sed -E 's/[[:space:]]+$//' | tail -1)
        if [[ -n "$line" ]]; then
            print -r -- "$line"
            return 0
        fi
    fi

    # 3. the profile's own declaration — the live PROFILE_START_DIR when <p> is
    #    the profile we just sourced, else read straight out of its meta.zsh
    #    (so `_claw_profile_start_dir cloud` is right while `vault` is loaded).
    if [[ -n "$p" && "$p" != "${PROFILE_NAME:-}" ]]; then
        local meta="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/profiles/$p/meta.zsh"
        if [[ -r "$meta" ]]; then
            print -r -- "$(sed -n -E 's/^PROFILE_START_DIR="(.*)"[[:space:]]*$/\1/p' "$meta" | tail -1)"
            return 0
        fi
    fi
    print -r -- "${PROFILE_START_DIR:-}"
}

# _claw_resolve_start_dir <spec> [profile] → best path on stdout.
# "Best" = the first candidate that exists; if none exists, the first candidate
# (so callers can report the miss). Empty spec → no output.
_claw_resolve_start_dir() {
    emulate -L zsh
    setopt local_options extended_glob
    local spec="${1:-}" p="${2:-${CLAW_ACTIVE_PROFILE:-}}"
    [[ -z "$spec" ]] && return 0

    # @vault* tokens route through obsidian.zsh's resolvers — the ONE vault/
    # folder map. It loads at .zshrc step 6 but the welcome TUI fires at step 3,
    # so pull it in on demand (idempotent — pure exports + function defs).
    if [[ "$spec" == *@vault* ]] && ! typeset -f _claw_obsidian_vault >/dev/null 2>&1; then
        local _obs="${DOTFILES_DIR:-$HOME/.dotfiles}/shell/obsidian.zsh"
        [[ -f "$_obs" ]] && source "$_obs"
    fi
    # Scope the folder map to the profile being resolved, not the loaded one.
    local CLAW_ACTIVE_PROFILE="${p:-${CLAW_ACTIVE_PROFILE:-}}"

    local cand path first=""
    for cand in ${(s:|:)spec}; do
        cand="${cand##[[:space:]]#}"; cand="${cand%%[[:space:]]#}"
        [[ -z "$cand" ]] && continue
        case "$cand" in
            @vault)
                typeset -f _claw_obsidian_vault >/dev/null 2>&1 || continue
                path="$(_claw_obsidian_vault)" ;;
            @vault-folder)
                typeset -f _claw_obsidian_dir >/dev/null 2>&1 || continue
                path="$(_claw_obsidian_dir)"
                # folder not carved out yet → the vault root is still the right
                # landing, never a dead path
                [[ -d "$path" ]] || path="$(_claw_obsidian_vault)" ;;
            @vault:*)
                typeset -f _claw_obsidian_vault >/dev/null 2>&1 || continue
                path="$(_claw_obsidian_vault)/${cand#@vault:}" ;;
            @*)
                continue ;;   # unknown token — profiles lint catches these
            *)
                # ~ then $VAR expansion. Specs are shell-owned config (meta.zsh
                # in the repo, start-dirs.conf in your dotfiles) — same trust
                # level as ~/.zshrc.local.
                path="$cand"
                [[ "$path" == "~"* ]] && path="${HOME}${path#\~}"
                path="${(e)path}" ;;
        esac
        [[ -z "$path" ]] && continue
        [[ "$path" != "/" ]] && path="${path%%/##}"
        [[ -z "$first" ]] && first="$path"
        if [[ -d "$path" ]]; then
            print -r -- "$path"
            return 0
        fi
    done
    print -r -- "$first"
}

# _claw_profile_start_dir [profile] → the resolved start dir (spec → path).
# Public-ish helper: `claw profiles paths`, debugging, and the applier below.
_claw_profile_start_dir() {
    emulate -L zsh
    local p="${1:-${CLAW_ACTIVE_PROFILE:-}}"
    _claw_resolve_start_dir "$(_claw_start_dir_spec "$p")" "$p"
}

# _claw_profile_cd [profile] — THE applier. Lands the shell in the profile's
# start dir and says so. Interactive shells only (a sourced profile must never
# relocate a script), never fatal, and always reversible with `cd -`.
_claw_profile_cd() {
    emulate -L zsh
    [[ -o interactive ]] || return 0

    local mode="${CLAW_PROFILE_CD:-1}"
    case "$mode" in
        0|off|no|false) return 0 ;;
        home) [[ "$PWD" == "$HOME" ]] || return 0 ;;
    esac

    local p="${1:-${CLAW_ACTIVE_PROFILE:-}}"
    local dir="$(_claw_profile_start_dir "$p")"
    [[ -z "$dir" ]] && return 0
    [[ "$dir" == "$PWD" ]] && return 0

    local _grn=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local _amb=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _rst=$'\e[0m'

    if [[ ! -d "$dir" ]]; then
        printf "  ${_amb}●${_rst} ${_dim}start dir missing: ${_fg}%s${_rst}${_dim} — staying in %s${_rst}\n" \
            "${dir/#$HOME/~}" "${PWD/#$HOME/~}"
        return 0
    fi
    if ! cd -- "$dir" 2>/dev/null; then
        printf "  ${_amb}●${_rst} ${_dim}could not enter ${_fg}%s${_rst}${_dim} — staying in %s${_rst}\n" \
            "${dir/#$HOME/~}" "${PWD/#$HOME/~}"
        return 0
    fi
    printf "  ${_grn}↳${_rst} ${_fg}%s${_rst}  ${_dim}(cd - to go back)${_rst}\n" "${dir/#$HOME/~}"
}

# _claw_profile_paths — every profile's declared start dir + whether it resolves
# on THIS machine. Backs `claw profiles paths`; also the fastest way to see the
# whole routing table at once.
_claw_profile_paths() {
    emulate -L zsh
    local dotfiles="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local _grn=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
    local _amb=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _pur=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"$'m'
    local _bld=$'\e[1m' _rst=$'\e[0m'

    printf "\n  ${_pur}${_bld}profile start dirs${_rst}  ${_dim}— PROFILE_START_DIR → resolved (this machine)${_rst}\n"
    printf "  ${_dim}%s${_rst}\n\n" "──────────────────────────────────────────────────────"

    local meta name spec dir
    for meta in "$dotfiles"/shell/profiles/*/meta.zsh(N); do
        name="${${meta:h}:t}"
        spec=$(CLAW_ACTIVE_PROFILE="$name" PROFILE_START_DIR="" DOTFILES_DIR="$dotfiles" \
               zsh -fc "source '$dotfiles/shell/profile-helpers.zsh'; source '$meta'; _claw_start_dir_spec '$name'" 2>/dev/null)
        if [[ -z "$spec" ]]; then
            printf "  ${_dim}○ %-11s stays put${_rst}\n" "$name"
            continue
        fi
        dir=$(CLAW_ACTIVE_PROFILE="$name" DOTFILES_DIR="$dotfiles" \
              zsh -fc "source '$dotfiles/shell/profile-helpers.zsh'; source '$meta'; _claw_profile_start_dir '$name'" 2>/dev/null)
        if [[ -n "$dir" && -d "$dir" ]]; then
            printf "  ${_grn}●${_rst} ${_fg}%-11s${_rst} %s\n" "$name" "${dir/#$HOME/~}"
        else
            printf "  ${_amb}●${_rst} ${_fg}%-11s${_rst} ${_dim}%s  (missing)${_rst}\n" "$name" "${${dir:-$spec}/#$HOME/~}"
        fi
    done
    printf "\n  ${_dim}override per machine: %s${_rst}\n" "$(_claw_start_dir_conf)"
    printf "  ${_dim}this shell only: CLAW_START_DIR=/some/path claw load <profile>${_rst}\n"
    printf "  ${_dim}disable entirely: CLAW_PROFILE_CD=0  (home = only from \$HOME)${_rst}\n\n"
}
