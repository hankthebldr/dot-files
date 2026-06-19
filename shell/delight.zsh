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
    [[ -z "$line" ]] && return
    # Themed printf (no `gum style`): gum also probes the terminal on each call,
    # which can desync right after the dashboard moves the cursor. printf is
    # query-free + deterministic, and renders backticks/em-dashes literally.
    printf "  \e[38;2;%sm✦\e[0m \e[38;2;%sm%s\e[0m\n" \
        "${CLAW_RGB_PURPLE:-188;140;255}" "${CLAW_RGB_MUTED:-139;148;158}" "$line"
}
# One fact per day on interactive login (skip SSH-pipe / non-tty).
if [[ -o interactive && -t 1 && -z "${SSH_CONNECTION:-}" && "${CLAW_FACT:-1}" == 1 ]]; then
    _claw_fact_stamp="${XDG_CACHE_HOME:-$HOME/.cache}/claw/fact-$(date +%Y%m%d)"
    if [[ ! -f "$_claw_fact_stamp" ]]; then
        mkdir -p "${_claw_fact_stamp:h}" 2>/dev/null && touch "$_claw_fact_stamp" && claw_fact
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
            | grep -cE '^    [a-zA-Z0-9]' > "$_pkg_count" 2>/dev/null ) &!
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
