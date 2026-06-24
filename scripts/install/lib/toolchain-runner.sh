#!/usr/bin/env bash
################################################################################
# scripts/install/lib/toolchain-runner.sh
#
# Shared engine for the domain toolchain installers (cloud/security/devops/ai/
# research/cortex/deck/demo/design/homelab/ai-workstation/ai-skills). Each
# *-toolchain.sh sources THIS file, declares a data table, then calls
# `toolchain_run`. All install logic, banners, section rendering, and the
# install summary live here — the per-domain files are pure data + extras.
#
# CONTRACT consumed from the sourcing toolchain script:
#   TOOLCHAIN_TITLE / TOOLCHAIN_CLASS / TOOLCHAIN_TAG   — banner strings
#   TOOLCHAIN_MAP=( "id|brew|apt|fallback|notes" ... )  — one row per tool
#   declare -A TOOLCHAIN_SECTIONS=( [idx]="NN|Title" )  — header before row idx
#   toolchain_preflight_extras()  (optional)  — run before the loop
#   toolchain_extras()            (optional)  — run after the loop
#
# fallback field grammar (used only when brew/apt name is "?" or unavailable):
#   none            → no fallback; report as unavailable
#   manual:URL      → print the URL for the operator (counts as "manual")
#   curl:URL        → download (tar.gz → extract binary | script → run | raw → bin)
#   go:PKG          → go install PKG@latest
#   pipx | gem | cargo  → install id via that manager
#
# Honors: DRY_RUN=1 (print, don't execute), TOOLCHAIN_ONLY="id1 id2" (subset).
################################################################################
set -uo pipefail

# Require bash >= 4 for `declare -A` (associative arrays) used by every
# *-toolchain.sh that sources this runner. macOS ships /bin/bash 3.2, and
# `#!/usr/bin/env bash` resolves to it on a fresh box before Homebrew bash
# is on PATH. Re-exec under a modern bash if available, else fail loudly
# instead of dying cryptically at the first `declare -A` line.
if (( BASH_VERSINFO[0] < 4 )); then
    for _b in /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash; do
        [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
    done
    echo "error: toolchain installer requires bash >= 4 (found ${BASH_VERSION}). Install with: brew install bash" >&2
    exit 1
fi

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_UTILS_DIR="$(cd "$_LIB_DIR/../../utils" && pwd)"

# Logging, colors, _section, _banner_basic, log_skip — all from cinematic.sh.
# shellcheck source=/dev/null
source "$_UTILS_DIR/cinematic.sh" 2>/dev/null || {
    c_reset=$'\e[0m'; c_white=$'\e[1m'; c_dim=$'\e[2m'; c_green=$'\e[32m'
    c_red=$'\e[31m'; c_yellow=$'\e[33m'; c_cyan=$'\e[36m'; c_bold=$'\e[1m'
    log_info(){ printf "  ▸ %s\n" "$1"; }; log_success(){ printf "  ✓ %s\n" "$1"; }
    log_warning(){ printf "  ! %s\n" "$1"; }; log_error(){ printf "  ✗ %s\n" "$1" >&2; }
    log_skip(){ printf "  · %s\n" "$1"; }
    _section(){ printf "\n  ${c_cyan}── %s ─ %s ──${c_reset}\n" "$1" "$2"; }
    _banner_basic(){ printf "\n  ${c_bold}%s${c_reset}\n  ${c_dim}%s · %s${c_reset}\n\n" "$1" "$2" "$3"; }
}
# OS_TYPE + PKG_MANAGER.
# shellcheck source=/dev/null
source "$_UTILS_DIR/detect-os.sh" 2>/dev/null && detect_os || {
    OS_TYPE="$(uname -s | tr '[:upper:]' '[:lower:]')"
    command -v brew &>/dev/null && PKG_MANAGER="brew" || PKG_MANAGER="apt"
}

DRY_RUN="${DRY_RUN:-0}"
mkdir -p "$HOME/.local/bin" 2>/dev/null || true
# cinematic.sh banners reference $USER; always set on a login shell, but guard
# for non-login/CI contexts so `set -u` doesn't abort the run.
export USER="${USER:-$(id -un 2>/dev/null || echo user)}"

# Result accounting — extras append to these; the summary reads them.
RESULT_INSTALLED=(); RESULT_SKIPPED=(); RESULT_FAILED=(); RESULT_MANUAL=()

_run() { if [[ "$DRY_RUN" == "1" ]]; then log_info "DRY: $*"; return 0; fi; "$@"; }

# ── Fallback installers ─────────────────────────────────────────────────────
_fb_curl() {  # _fb_curl <id> <url>
    local id="$1" url="$2" tmp; tmp="$(mktemp -d)"
    log_info "fetching ${c_white}$id${c_reset} ← ${c_dim}${url##*/}${c_reset}"
    [[ "$DRY_RUN" == "1" ]] && { log_info "DRY: curl $url"; return 0; }
    if ! curl -fsSL "$url" -o "$tmp/dl"; then rm -rf "$tmp"; return 1; fi
    if file "$tmp/dl" 2>/dev/null | grep -qiE 'gzip|tar'; then
        tar -xf "$tmp/dl" -C "$tmp" 2>/dev/null
        local bin; bin="$(find "$tmp" -type f -name "$id" -perm -u+x 2>/dev/null | head -1)"
        [[ -z "$bin" ]] && bin="$(find "$tmp" -type f \( -name "$id" -o -name "${id}_*" \) 2>/dev/null | head -1)"
        [[ -z "$bin" ]] && { rm -rf "$tmp"; return 1; }
        install -m755 "$bin" "$HOME/.local/bin/$id"
    elif head -c2 "$tmp/dl" | grep -q '#!'; then     # install script → run it
        chmod +x "$tmp/dl"; "$tmp/dl" || { rm -rf "$tmp"; return 1; }
    else                                              # assume raw binary
        install -m755 "$tmp/dl" "$HOME/.local/bin/$id"
    fi
    rm -rf "$tmp"
}

_install_one() {  # _install_one <id> <brew> <apt> <fallback>
    local id="$1" brew="$2" apt="$3" fb="$4"
    if command -v "$id" &>/dev/null; then log_skip "$id (present)"; RESULT_SKIPPED+=("$id"); return; fi

    # Native package manager first (skip when name is unknown "?").
    if [[ "$PKG_MANAGER" == "brew" && "$brew" != "?" && -n "$brew" ]]; then
        if _run brew install "$brew" 2>/dev/null; then log_success "$id (brew)"; RESULT_INSTALLED+=("$id"); return; fi
    elif [[ "$PKG_MANAGER" == "apt" && "$apt" != "?" && -n "$apt" ]]; then
        if _run sudo apt-get install -y "$apt" 2>/dev/null; then log_success "$id (apt)"; RESULT_INSTALLED+=("$id"); return; fi
    fi

    # Fallbacks.
    case "$fb" in
        none|"")          log_warning "$id — no install path for $PKG_MANAGER"; RESULT_FAILED+=("$id") ;;
        manual:*)         log_info "$id — manual: ${c_dim}${fb#manual:}${c_reset}"; RESULT_MANUAL+=("$id") ;;
        curl:*)           if _fb_curl "$id" "${fb#curl:}"; then log_success "$id (binary)"; RESULT_INSTALLED+=("$id"); else log_warning "$id (curl failed)"; RESULT_FAILED+=("$id"); fi ;;
        go:*)             command -v go &>/dev/null   && _run go install "${fb#go:}@latest" && { log_success "$id (go)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (go unavailable)"; RESULT_FAILED+=("$id"); } ;;
        eget:*)           command -v eget &>/dev/null && _run eget "${fb#eget:}" --to "$HOME/.local/bin/$id" && { log_success "$id (eget)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (eget unavailable — run: claw install nextgen)"; RESULT_FAILED+=("$id"); } ;;
        pipx)             command -v pipx &>/dev/null && _run pipx install "$id" && { log_success "$id (pipx)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (pipx unavailable)"; RESULT_FAILED+=("$id"); } ;;
        gem)              command -v gem &>/dev/null  && _run gem install "$id" && { log_success "$id (gem)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (gem unavailable)"; RESULT_FAILED+=("$id"); } ;;
        cargo)            command -v cargo &>/dev/null && _run cargo install "$id" && { log_success "$id (cargo)"; RESULT_INSTALLED+=("$id"); } || { log_warning "$id (cargo unavailable)"; RESULT_FAILED+=("$id"); } ;;
        *)                log_warning "$id — unknown fallback '$fb'"; RESULT_FAILED+=("$id") ;;
    esac
}

toolchain_run() {
    _banner_basic "${TOOLCHAIN_TITLE:-TOOLCHAIN}" "${TOOLCHAIN_CLASS:-LOADOUT}" "${TOOLCHAIN_TAG:-}"
    log_info "platform: ${c_white}${OS_TYPE}/${PKG_MANAGER}${c_reset}$([[ "$DRY_RUN" == 1 ]] && echo "  ${c_yellow}(dry-run)${c_reset}")"

    declare -f toolchain_preflight_extras &>/dev/null && toolchain_preflight_extras

    local only=" ${TOOLCHAIN_ONLY:-} "
    local idx=0 row id brew apt fb _notes
    for row in "${TOOLCHAIN_MAP[@]}"; do
        if [[ -n "${TOOLCHAIN_SECTIONS[$idx]:-}" ]]; then
            _section "${TOOLCHAIN_SECTIONS[$idx]%%|*}" "${TOOLCHAIN_SECTIONS[$idx]#*|}"
        fi
        IFS='|' read -r id brew apt fb _notes <<<"$row"
        if [[ "${TOOLCHAIN_ONLY:-}" == "" || "$only" == *" $id "* ]]; then
            _install_one "$id" "$brew" "$apt" "$fb"
        fi
        idx=$((idx + 1))
    done

    declare -f toolchain_extras &>/dev/null && toolchain_extras

    # ── Summary ──
    printf "\n  ${c_bold}── install summary ──${c_reset}\n"
    log_success "installed: ${#RESULT_INSTALLED[@]}"
    log_skip    "already:   ${#RESULT_SKIPPED[@]}"
    [[ ${#RESULT_MANUAL[@]}  -gt 0 ]] && log_info    "manual:    ${#RESULT_MANUAL[@]}  (${c_dim}${RESULT_MANUAL[*]}${c_reset})"
    [[ ${#RESULT_FAILED[@]}  -gt 0 ]] && log_warning "failed:    ${#RESULT_FAILED[@]}  (${c_dim}${RESULT_FAILED[*]}${c_reset})"
    printf "\n"
    return 0
}
