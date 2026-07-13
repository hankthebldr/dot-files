# shell/delight.zsh
# Daily-driver delight: progress on slow ops, repo dashboards, fact-of-the-day,
# weather. Everything is guarded on `command -v` and interactive-only — sourcing
# this in a non-interactive/SSH-pipe shell is a no-op (never pollutes stdout).
# Part of the Open Claw "every element should delight" mandate (see ULTRAPLAN).

# ── Progress-aware file ops (pv / rsync) ────────────────────────────────────
# cpv  — copy with a live progress bar+ETA (rsync if present, else pv per-file).
# mvv  — same, then remove source. dlv — download with progress (aria2 > xh > curl).
if command -v rsync &>/dev/null; then
    cpv() { rsync -ah --info=progress2 --no-inc-recursive "$@"; }
elif command -v pv &>/dev/null; then
    cpv() { [[ $# -eq 2 && -f "$1" ]] && pv -- "$1" > "$2" || cp -v "$@"; }
fi
command -v rsync &>/dev/null && mvv() { rsync -ah --info=progress2 --remove-source-files "$@"; }

dlv() {  # dlv <url> [out]  — fastest available downloader with a progress bar
    local url="$1" out="${2:-}"
    if command -v aria2c &>/dev/null; then
        aria2c -x8 -s8 ${out:+-o "$out"} -- "$url"
    elif command -v xh &>/dev/null; then
        xh --download ${out:+--output "$out"} -- "$url"
    else
        curl -fL --progress-bar ${out:+-o "$out"} -- "$url"
    fi
}

# extract — progress-aware archive extraction
command -v pv &>/dev/null && xtract() {
    local f="$1"
    case "$f" in
        *.tar.gz|*.tgz) pv -- "$f" | tar -xz ;;
        *.tar.xz)       pv -- "$f" | tar -xJ ;;
        *.tar.bz2)      pv -- "$f" | tar -xj ;;
        *.tar)          pv -- "$f" | tar -x  ;;
        *)              command -v tar &>/dev/null && tar -xf "$f" || echo "unknown archive: $f" ;;
    esac
}

# ── onefetch on entering a git repo (once per dir, opt-in) ──────────────────
# Set CLAW_ONEFETCH=1 to enable. Shows a repo dashboard the first time you cd
# into a new git worktree this session. Quiet, guarded, never on $HOME.
if [[ -o interactive ]] && command -v onefetch &>/dev/null; then
    typeset -gA _claw_onefetch_seen
    _claw_onefetch_hook() {
        [[ "${CLAW_ONEFETCH:-0}" == 1 ]] || return
        local root
        root=$(git rev-parse --show-toplevel 2>/dev/null) || return
        [[ "$root" == "$HOME" || -n "${_claw_onefetch_seen[$root]:-}" ]] && return
        _claw_onefetch_seen[$root]=1
        onefetch --no-art 2>/dev/null
    }
    autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook chpwd _claw_onefetch_hook
fi

# ── Fact / quote of the day (cached daily, interactive only) ────────────────
# Uses a curated facts file if present, else `fortune`. Silent if neither exists.
claw_fact() {
    local facts="${DOTFILES_DIR:-$HOME/.dotfiles}/config/facts.txt" line
    if [[ -f "$facts" ]]; then
        # Filter + pick in pure zsh — NOT `sort -R | grep`. Interactive shells
        # expand aliases inside $(...), and aliases.zsh maps grep→rg; ripgrep
        # then prefixes every line with "line:col:" (the "1:1:" that leaked into
        # the fact on login). Reading natively is alias-proof and subprocess-free.
        local -a pool; local l
        while IFS= read -r l; do
            [[ -z "$l" || "$l" == '#'* ]] && continue
            pool+=("$l")
        done < "$facts"
        (( ${#pool[@]} )) && line="${pool[RANDOM % ${#pool[@]} + 1]}"
    elif command -v fortune &>/dev/null; then
        line=$(fortune -s 2>/dev/null)
    fi
    # Signal failure (no fact emitted) so the daily stamp is only written after a
    # fact actually renders — see the trigger block below.
    [[ -z "$line" ]] && return 1

    emulate -L zsh
    setopt extendedglob
    # Framed, titled, screen-centred card matching the "Daily Driver" quickref
    # (_claw_default_quickref): purple rounded border, cyan-bold title left + dim
    # date right, blank padding rows. Colours consume the theme engine
    # (CLAW_RGB_*) with refined-dark fallbacks — never hardcode a new surface.
    local c_reset=$'\e[0m' c_bold=$'\e[1m'
    local c_border=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"'m'
    local c_title=$'\e[38;2;'"${CLAW_RGB_CYAN:-57;197;255}"'m'
    local c_text=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"'m'

    # Date via zsh/datetime (subprocess-free, alias-proof); fall back to `date`.
    local _today; zmodload zsh/datetime 2>/dev/null \
        && strftime -s _today '%a %b %d' $EPOCHSECONDS \
        || _today="$(command date '+%a %b %d' 2>/dev/null)"
    local title="${c_title}${c_bold}✦ Fact of the Day${c_reset}"
    local hint="${c_text}${_today}${c_reset}"
    # Visible widths: strip SGR (extendedglob), then glyph-count (✦ = 1 cell).
    local _t="${title//$'\e'\[[0-9;]#m/}" _h="${hint//$'\e'\[[0-9;]#m/}"
    local tvl=${#_t} hvl=${#_h}
    local header=$(( tvl + 2 + hvl ))     # title + min gap + hint

    # Word-wrap the fact to a comfortable reading width, bounded by the terminal.
    # ${=line} splits on whitespace without evaluating backticks/em-dashes.
    local cols=${COLUMNS:-100} maxw=64
    (( maxw > cols - 4 )) && maxw=$(( cols - 4 ))
    (( maxw < 20 )) && maxw=20
    local -a words=(${=line}) wrapped=(); local w cur=""
    for w in $words; do
        if [[ -z "$cur" ]]; then cur="$w"
        elif (( ${#cur} + 1 + ${#w} <= maxw )); then cur="$cur $w"
        else wrapped+=("$cur"); cur="$w"; fi
    done
    [[ -n "$cur" ]] && wrapped+=("$cur")

    # Inner width = widest wrapped row, but never narrower than the header.
    local W=0; for w in $wrapped; do (( ${#w} > W )) && W=${#w}; done
    (( W < header )) && W=$header

    local mar=$(( (cols - (W + 4)) / 2 )); (( mar < 0 )) && mar=0
    local M="${(l:$mar:: :)}"                      # left margin (screen-centre)
    local bar="${(l:$((W+2))::─:)}"               # horizontal rule
    local blank="${(l:$W:: :)}"                    # full-width empty content

    local gap=$(( W - tvl - hvl )); (( gap < 1 )) && gap=1
    local trow="${title}${(l:$gap:: :)}${hint}"    # title left, date right

    print -r -- ""
    print -r -- "${M}${c_border}╭${bar}╮${c_reset}"
    print -r -- "${M}${c_border}│${c_reset} ${trow} ${c_border}│${c_reset}"
    print -r -- "${M}${c_border}├${bar}┤${c_reset}"
    print -r -- "${M}${c_border}│${c_reset} ${blank} ${c_border}│${c_reset}"
    for w in $wrapped; do                          # centre each prose line in-box
        local lp=$(( (W - ${#w}) / 2 )); (( lp < 0 )) && lp=0
        local rp=$(( W - ${#w} - lp )); (( rp < 0 )) && rp=0
        print -r -- "${M}${c_border}│${c_reset} ${(l:$lp:: :)}${c_text}${w}${c_reset}${(l:$rp:: :)} ${c_border}│${c_reset}"
    done
    print -r -- "${M}${c_border}│${c_reset} ${blank} ${c_border}│${c_reset}"
    print -r -- "${M}${c_border}╰${bar}╯${c_reset}"
    print -r -- ""
}
# One fact per day on interactive login (skip SSH-pipe / non-tty).
if [[ -o interactive && -t 1 && -z "${SSH_CONNECTION:-}" && "${CLAW_FACT:-1}" == 1 ]]; then
    _claw_fact_stamp="${XDG_CACHE_HOME:-$HOME/.cache}/claw/fact-$(date +%Y%m%d)"
    if [[ ! -f "$_claw_fact_stamp" ]]; then
        # Render FIRST, stamp only on success — never burn the day on a fact that
        # was never emitted (empty pool / no fortune). claw_fact returns non-zero
        # when it prints nothing, so a bad first login retries on the next one.
        claw_fact && mkdir -p "${_claw_fact_stamp:h}" 2>/dev/null && touch "$_claw_fact_stamp"
    fi
    unset _claw_fact_stamp
fi

# ── Weather (wttr.in — zero install) ────────────────────────────────────────
# aliases.zsh loads first; unalias `weather`/`wttr` so these richer city-aware
# functions can be defined — a function defined on top of an alias is a zsh
# parse error that aborts the rest of this file. `weatherfull` stays an alias
# (no function shadows it).
unalias weather wttr 2>/dev/null
weather() { curl -fsS "wttr.in/${1:-}?format=3" 2>/dev/null || echo "weather: offline"; }
wttr()    { curl -fsS "wttr.in/${1:-}" 2>/dev/null || echo "weather: offline"; }

# ── pkg-track nudge (P1) ────────────────────────────────────────────────────
# Once/day, refresh an untracked-tool count in the background and nudge if any
# manually-installed tools aren't in the manifest yet. Non-blocking, opt-out
# with CLAW_PKG_NUDGE=0.
if [[ -o interactive && -t 1 && -z "${SSH_CONNECTION:-}" && "${CLAW_PKG_NUDGE:-1}" == 1 ]]; then
    _pkg_count="${XDG_CACHE_HOME:-$HOME/.cache}/claw/pkg-untracked"
    if [[ -s "$_pkg_count" ]]; then
        _n=$(cat "$_pkg_count" 2>/dev/null)
        [[ "$_n" =~ ^[0-9]+$ && "$_n" -gt 0 ]] && \
            printf "  \e[38;2;%sm●\e[0m \e[38;2;%sm%s untracked tool(s) — \e[38;2;%smclaw pkg track\e[0m\n" \
                "${CLAW_RGB_AMBER:-227;179;65}" "${CLAW_RGB_MUTED:-139;148;158}" "$_n" "${CLAW_RGB_FG:-201;209;217}"
    fi
    _pkg_stamp="${XDG_CACHE_HOME:-$HOME/.cache}/claw/pkgscan-$(date +%Y%m%d)"
    if [[ ! -f "$_pkg_stamp" ]]; then
        mkdir -p "${_pkg_stamp:h}" 2>/dev/null && touch "$_pkg_stamp"
        ( bash "$DOTFILES_DIR/scripts/utils/pkg-manifest.sh" scan 2>/dev/null \
            | command grep -cE '^    [a-zA-Z0-9]' > "$_pkg_count" 2>/dev/null ) &!
    fi
    unset _pkg_count _pkg_stamp _n
fi

# ── claw_spin — run a command under a spinner (gum if present) ──────────────
# Usage: claw_spin "Installing X" brew install x
claw_spin() {
    local msg="$1"; shift
    [[ $# -eq 0 ]] && return 0
    if command -v gum &>/dev/null; then
        gum spin --spinner dot --title "$msg" -- "$@"
    else
        printf "  \e[38;2;%sm◐\e[0m %s…" "${CLAW_RGB_BLUE:-88;166;255}" "$msg"
        "$@"; local rc=$?
        if [[ $rc -eq 0 ]]; then printf "\r  \e[38;2;%sm✓\e[0m %s   \n" "${CLAW_RGB_GREEN:-63;185;80}" "$msg"
        else printf "\r  \e[38;2;%sm✗\e[0m %s   \n" "${CLAW_RGB_RED:-255;123;114}" "$msg"; fi
        return $rc
    fi
}
