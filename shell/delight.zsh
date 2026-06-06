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
# Uses a curated facts file if present, else `fortune`. Rendered with gum/glow
# if available. Silent if neither source exists.
claw_fact() {
    local facts="${DOTFILES_DIR:-$HOME/.dotfiles}/config/facts.txt" line
    if [[ -f "$facts" ]]; then
        line=$(LC_ALL=C sort -R "$facts" 2>/dev/null | grep -v '^#' | grep -v '^$' | head -1)
    elif command -v fortune &>/dev/null; then
        line=$(fortune -s 2>/dev/null)
    fi
    [[ -z "$line" ]] && return
    if command -v gum &>/dev/null; then
        gum style --foreground 141 --border none --margin "0 2" "  $line"
    else
        printf "  \e[38;2;188;140;255m✦\e[0m \e[38;2;139;148;158m%s\e[0m\n" "$line"
    fi
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
            printf "  \e[38;2;210;153;34m●\e[0m \e[38;2;139;148;158m%s untracked tool(s) — \e[38;2;201;209;217mclaw pkg track\e[0m\n" "$_n"
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
        printf "  \e[38;2;88;166;255m◐\e[0m %s…" "$msg"
        "$@"; local rc=$?
        if [[ $rc -eq 0 ]]; then printf "\r  \e[38;2;63;185;80m✓\e[0m %s   \n" "$msg"
        else printf "\r  \e[38;2;255;123;114m✗\e[0m %s   \n" "$msg"; fi
        return $rc
    fi
}
