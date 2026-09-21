# shell/claw-palette.zsh
# THE palette: one flat, fuzzy, frecency-ranked list of every destination —
# 18 profiles + the registry's verbs — over `registry.sh palette`.
#
# Why (audit 2026-09-20):
#   F-17  the old two-level menu was hierarchy-as-gate, not search: no frecency,
#         L1 contradicted actual usage, and 'sec' leaked child names. One flat
#         list ranked by frecency replaces both levels.
#   F-18  one entry contract (bare `claw`, `claw menu`, ^G) and one exit
#         contract (ESC closes, changes nothing). fzf rc 2 fails LOUD instead of
#         being read as an ESC.
#   F-06  the palette is never on the login path. It opens only after a prompt
#         exists, and Enter on a query that matches nothing does NOTHING.
#   F-16  every open, pick, abandon and refusal is one `_claw_tlog` row, with
#         the query, so `claw tui-stats` can see no-pick queries.
#
# Sourced from shell/claw-fn.zsh (which .zshrc sources at step 6), so the
# widget is bound after claw() exists. Colours come from the theme engine.

# EPOCHSECONDS for the frecency clock; `date` is the fallback.
zmodload -i zsh/datetime 2>/dev/null

# The palette logs through the ONE logger (_claw_tlog, shell/claw-login.zsh).
# Sourcing claw-login.zsh has no side effects, so pulling it in here is safe
# for the `claw` that runs in a shell whose rc never reached step 2b.
if ! typeset -f _claw_tlog >/dev/null 2>&1; then
    [[ -f "${DOTFILES_DIR:-$HOME/.dotfiles}/shell/claw-login.zsh" ]] && \
        source "${DOTFILES_DIR:-$HOME/.dotfiles}/shell/claw-login.zsh"
fi

# ── frecency ────────────────────────────────────────────────────────────────
# ${XDG_STATE_HOME:-~/.local/state}/claw/frecency.tsv — `id\tcount\tlast_epoch`,
# keyed on the BARE id (a profile and a verb of the same name share a counter,
# by design — registry.sh reads it the same way). Rewritten atomically so a
# concurrent `registry.sh palette` never reads a half-written file.
_claw_frecency_bump() {
    emulate -L zsh
    local id="${1:-}"
    [[ -n "$id" ]] || return 0
    local dir="${XDG_STATE_HOME:-$HOME/.local/state}/claw"
    local f="$dir/frecency.tsv" now="${CLAW_NOW:-${EPOCHSECONDS:-}}"
    [[ -n "$now" ]] || now="$(command date +%s 2>/dev/null)" || return 0
    [[ -d "$dir" ]] || command mkdir -p "$dir" 2>/dev/null || return 0
    local tmp
    tmp="$(command mktemp "$dir/.frecency.XXXXXX" 2>/dev/null)" || return 0
    if { [[ -f "$f" ]] && command cat "$f" || true; } 2>/dev/null \
        | command awk -F'\t' -v OFS='\t' -v id="$id" -v now="$now" '
              $1 == id && NF >= 3 { print $1, $2 + 1, now; seen = 1; next }
              $1 != "" && NF >= 3 { print $1, $2, $3 }
              END { if (!seen) print id, 1, now }
          ' > "$tmp" 2>/dev/null
    then
        command mv -f "$tmp" "$f" 2>/dev/null || command rm -f "$tmp" 2>/dev/null
    else
        command rm -f "$tmp" 2>/dev/null
    fi
    return 0
}

# ── the outcome applier ─────────────────────────────────────────────────────
# `PROFILE\t<id>` | `ACTION\t<id>` | anything else (NONE) → nothing.
# THE one applier: the palette, `claw <p>`, `claw load <p>` and any future
# front-end all land here. Moved out of welcome-tui.zsh, whose ACTION branch
# hard-coded six ids (three of which fell through to `*) :` — F-19).
_claw_apply_outcome() {
    emulate -L zsh
    local line="${1:-}" kind rest
    kind="${line%%$'\t'*}"
    rest="${line#*$'\t'}"
    [[ "$rest" == "$line" ]] && rest=""
    case "$kind" in
        PROFILE)
            [[ -n "$rest" ]] || return 1
            if typeset -f _claw_load_profile >/dev/null 2>&1; then
                _claw_load_profile "$rest" palette
            else
                return 1
            fi
            ;;
        ACTION)
            [[ -n "$rest" ]] || return 1
            _claw_action "$rest"
            ;;
        *) return 0 ;;
    esac
}

# ── the verb runner ─────────────────────────────────────────────────────────
# _claw_action <id> — look the verb up in the registry and run its `run`
# snippet IN THIS SHELL, honouring the flag vocabulary:
#   !        confirm first (gum confirm, else `read -q`)
#   x        external — mutates no shell state (informational)
#   l:<mod>  source shell/<mod>.zsh first, unless the run's first word is
#            already a function
#   hidden   help/completion only; never reaches the palette
# The row is matched on (kind, id): ids are unique per KIND, not globally —
# `ai` and `homelab` are both a profile and a verb.
_claw_action() {
    emulate -L zsh
    local id="${1:-}" d="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local _red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _rst=$'\e[0m'
    [[ -n "$id" ]] || return 1

    local row
    row="$(command bash "$d/scripts/utils/registry.sh" rows 2>/dev/null \
           | command awk -F'\t' -v id="$id" '$1 == "action" && $2 == id { print; exit }')"
    if [[ -z "$row" ]]; then
        printf "  ${_red}✗${_rst} ${_dim}no such action: ${_fg}%s${_rst}\n" "$id" >&2
        _claw_tlog palette:badid "id=$id"
        return 1
    fi

    local -a _f; _f=("${(@ps:\t:)row}")
    local run="${_f[8]}" flags="${_f[9]}"
    local -a _fl; _fl=(${(s:,:)flags})

    # l:<mod> — lazy-source the module that defines the run's first word.
    # ${(z)run} splits the snippet into shell words; take the first one as an
    # array element (a scalar subscript would give its first CHARACTER).
    local tok mod first
    local -a _w; _w=( ${(z)run} ); first="${_w[1]-}"
    for tok in "${_fl[@]}"; do
        [[ "$tok" == l:* ]] || continue
        mod="${tok#l:}"
        [[ -n "$mod" ]] || continue
        typeset -f "$first" >/dev/null 2>&1 && continue
        [[ -f "$d/shell/$mod.zsh" ]] && source "$d/shell/$mod.zsh"
    done

    # ! — confirm before running. gum when present, `read -q` otherwise.
    if (( ${_fl[(I)!]} )); then
        local _ok=1
        if command -v gum &>/dev/null; then
            command gum confirm "run: $run?" || _ok=0
        else
            local _ans
            read -q "_ans?  ${_dim}run: ${_fg}${run}${_rst}${_dim} [y/N] ${_rst}" || _ok=0
            print
        fi
        if (( ! _ok )); then
            printf "  ${_dim}○ cancelled${_rst}\n"
            _claw_tlog palette:deny "id=$id"
            return 1
        fi
    fi

    eval "$run"
    local rc=$?
    _claw_frecency_bump "$id"
    return $rc
}

# ── the palette ─────────────────────────────────────────────────────────────
# claw_palette [--src=cmd|chord]
#
# fzf argv, as settled (see docs/superpowers/specs/2026-09-20-tui-redesign-design.md):
#   --delimiter=$'\t' --with-nth=3..   display the glyph+label, desc and group
#   --nth=1..                          search ALL of the displayed fields.
#                                      (the design's `--nth=2,3,4` is measurably
#                                      wrong: --nth indexes the TRANSFORMED
#                                      string, so 2,3,4 drops the label and
#                                      `security` matches nothing — verified on
#                                      fzf 0.74.3.)
#   --print-query                      so an abandoned query is logged (F-06)
#   --expect=ctrl-p                    pin the picked profile as the login one
#   --height=~60% / 60%                `~` auto-height needs fzf >= 0.34
# stdout with --print-query + --expect is three lines: query, key, selection.
claw_palette() {
    emulate -L zsh
    local src=cmd a
    for a in "$@"; do
        case "$a" in
            --src=*) src="${a#--src=}" ;;
        esac
    done

    local d="${DOTFILES_DIR:-$HOME/.dotfiles}"
    local _red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
    local _dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
    local _fg=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
    local _rst=$'\e[0m'

    if ! command -v fzf &>/dev/null; then
        printf "  ${_red}✗${_rst} ${_dim}fzf is not installed — the palette needs it${_rst}\n" >&2
        printf "  ${_dim}   brew install fzf ${_rst}${_dim}·${_rst}${_dim} apt install fzf${_rst}\n" >&2
        printf "  ${_dim}   meanwhile: ${_fg}claw help${_rst}${_dim} · ${_fg}claw <profile>${_rst}\n" >&2
        _claw_tlog palette:nofzf "src=$src"
        return 1
    fi

    # --height=~N% (auto-size to the list) landed in fzf 0.34; older builds exit
    # 2 on it, which the old menu silently read as an ESC (F-18).
    local _h='--height=~60%' _ver _maj _min
    local -a _vw; _vw=( ${(z)"$(command fzf --version 2>/dev/null)"} )
    _ver="${_vw[1]-0.0}"
    _maj="${_ver%%.*}"; _min="${${_ver#*.}%%.*}"
    [[ "$_maj" == <-> ]] || _maj=0
    [[ "$_min" == <-> ]] || _min=0
    (( _maj == 0 && _min < 34 )) && _h='--height=60%'

    local _color="${CLAW_FZF_COLOR:-}"
    if [[ -z "$_color" ]] && typeset -f claw_theme_fzf >/dev/null 2>&1; then
        _color="$(claw_theme_fzf 2>/dev/null)"
    fi

    _claw_tlog palette:open "src=$src"

    local _err
    _err="$(command mktemp "${TMPDIR:-/tmp}/claw-palette.XXXXXX" 2>/dev/null)" || _err=""
    local -a _args
    _args=(
        --delimiter=$'\t'
        --with-nth=3..
        --nth=1..
        "$_h"
        --layout=reverse
        --border
        --ansi
        --tiebreak=index
        --print-query
        --prompt='claw ▸ '
        --header='type to search · enter run · ctrl-p pin as login · esc close'
        --expect=ctrl-p
    )
    [[ -n "$_color" ]] && _args+=( --color="$_color" )

    local out
    out="$(command bash "$d/scripts/utils/registry.sh" palette 2>/dev/null \
        | command fzf "${_args[@]}" 2>"${_err:-/dev/null}")"
    local _rc=$?

    # rc 2 is an fzf ERROR (a flag it does not understand, a broken $FZF_DEFAULT_OPTS).
    # Say so — the old menu treated it as an ESC and silently did nothing (F-18).
    if (( _rc == 2 )); then
        printf "  ${_red}✗${_rst} ${_dim}fzf failed (rc 2) — the palette did not open${_rst}\n" >&2
        [[ -n "$_err" && -s "$_err" ]] && command cat "$_err" >&2
        [[ -n "$_err" ]] && command rm -f "$_err" 2>/dev/null
        _claw_tlog palette:err "src=$src;rc=2"
        return 2
    fi
    [[ -n "$_err" ]] && command rm -f "$_err" 2>/dev/null

    local -a _lines; _lines=("${(@f)out}")
    local query="${_lines[1]-}" key="${_lines[2]-}" sel="${_lines[3]-}"

    # Enter on a query that matches nothing, or ESC: do NOTHING. Not a default
    # profile, not a bare shell reload — nothing. (F-06/F-18.)
    if [[ -z "$sel" ]]; then
        _claw_tlog palette:esc "src=$src;rc=$_rc;q=${query//;/,}"
        return 0
    fi

    local id kind
    id="${sel%%$'\t'*}"
    kind="${${(@ps:\t:)sel}[2]}"
    [[ -n "$id" && -n "$kind" ]] || { _claw_tlog palette:esc "src=$src;rc=$_rc"; return 0; }

    if [[ "$key" == ctrl-p ]]; then
        if [[ "$kind" == profile ]]; then
            _claw_tlog palette:pin "src=$src;id=$id"
            command claw pin "$id"
            return $?
        fi
        printf "  ${_dim}○ ctrl-p pins a profile; ${_fg}%s${_rst}${_dim} is a %s${_rst}\n" "$id" "$kind"
        return 0
    fi

    _claw_tlog "palette:pick:$kind:$id" "src=$src;q=${query//;/,}"
    _claw_frecency_bump "$id"
    _claw_apply_outcome "${(U)kind}"$'\t'"$id"
}

# ── the ^G chord ────────────────────────────────────────────────────────────
# zle -I flushes the line editor so the palette owns the screen; reset-prompt
# redraws afterwards. </dev/tty >/dev/tty because a widget's stdio is not the
# terminal. CLAW_PALETTE_KEY= (set, empty) leaves the chord unbound.
_claw_palette_widget() {
    zle -I
    claw_palette --src=chord </dev/tty >/dev/tty
    zle reset-prompt
}

if [[ -o interactive ]] && (( ${+builtins[zle]} )); then
    zle -N _claw_palette_widget
    if [[ -n "${CLAW_PALETTE_KEY-^G}" ]]; then
        for _claw_pk_map in emacs viins vicmd; do
            bindkey -M "$_claw_pk_map" "${CLAW_PALETTE_KEY-^G}" _claw_palette_widget 2>/dev/null
        done
    fi
    unset _claw_pk_map
fi
