#!/usr/bin/env bash
################################################################################
# pkg-manifest.sh — the self-aware tool registry.
#
# THE INTEROP LOOP the operator asked for:
#   1. You install something manually   (brew/cargo/go/pipx/eget/npm/apt)
#   2. `claw pkg track`  detects it, appends it to config/manifest/tools.list,
#      and (optionally) commits — so the repo's tool list stays CURRENT.
#   3. `claw pkg update` / `claw update`  includes it in bulk update ops.
#   4. `claw provision` on a fresh box reinstalls EVERYTHING tracked here.
#
# Manifest format (config/manifest/tools.list), one tool per line:
#   id|source            source ∈ brew apt cargo pipx gem npm eget:<repo> go:<pkg> curl:<url> manual
#   # comments + blank lines ignored; "## Section" lines are kept for grouping.
#
# Usage:
#   claw pkg list                  show tracked tools
#   claw pkg scan                  show installed-but-UNtracked CLI tools
#   claw pkg track [--commit]      add untracked tools to the manifest (+commit)
#   claw pkg add <id> [source]     add one tool manually
#   claw pkg install [id|all]      install tracked tool(s) via their source
#   claw pkg update                update everything (topgrade, else per-source)
################################################################################
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
MANIFEST="$DOTFILES/config/manifest/tools.list"
_U="$DOTFILES/scripts/utils"
# shellcheck source=/dev/null
source "$_U/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; log_skip(){ echo "· $*"; }; c_white=''; c_dim=''; c_green=''; c_reset=''; c_cyan=''; }
# shellcheck source=/dev/null
source "$_U/detect-os.sh" 2>/dev/null && detect_os || PKG_MANAGER=brew
# shellcheck source=/dev/null
source "$_U/claw-progress.sh" 2>/dev/null || true
export USER="${USER:-$(id -un 2>/dev/null||echo user)}"
mkdir -p "$(dirname "$MANIFEST")" "$HOME/.local/bin" 2>/dev/null || true
[[ -f "$MANIFEST" ]] || : > "$MANIFEST"

# ── manifest parsing ────────────────────────────────────────────────────────
_m_ids()    { grep -vE '^\s*#|^\s*$' "$MANIFEST" 2>/dev/null | cut -d'|' -f1 | tr -d ' '; }
_m_source() { grep -E "^\s*$1\s*\|" "$MANIFEST" 2>/dev/null | head -1 | cut -d'|' -f2 | tr -d ' '; }
_m_has()    { _m_ids | grep -qxF "$1"; }

# ── discover installed CLI tools from user-managed sources ──────────────────
# Only the channels a user adds *CLI tools* through — avoids dragging in the
# entire apt system package set. Each prints bare tool ids on stdout.
_discover() {
    { command -v brew  &>/dev/null && brew leaves 2>/dev/null | sed 's#.*/##'; } || true
    { command -v cargo &>/dev/null && cargo install --list 2>/dev/null | grep -E '^\S+ v' | awk '{print $1}'; } || true
    { command -v pipx  &>/dev/null && pipx list --short 2>/dev/null | awk '{print $1}'; } || true
    { command -v npm   &>/dev/null && npm ls -g --depth=0 --parseable 2>/dev/null | sed 's#.*/##' | grep -v '^npm$'; } || true
    # user-space binaries (eget/go/manual installs land here)
    local d
    for d in "$HOME/.local/bin" "$HOME/go/bin"; do
        [[ -d "$d" ]] && find "$d" -maxdepth 1 -type f -perm -u+x -printf '%f\n' 2>/dev/null
    done
}
# Ignore obvious non-CLI noise (drivers, python shims, dir headers).
_discover_clean() { _discover | grep -vE '^\s*$|:$|^(chromedriver|geckodriver|activate|python[0-9.]*|pip[0-9.]*)$' | sort -u; }

# Per-source discovery that announces a scan phase for the live panel, then
# feeds the same clean tool list. Used by pkg_track / pkg_scan.
# NOTE (deviation from plan Task 7): the claw_prog_* announce calls are
# redirected to stderr (>&2). These run inside `< <( … )` process substitution
# whose stdout is the tool-id stream the caller's `while read` consumes; in rich
# mode an un-redirected repaint would inject ANSI escapes into that stream and
# corrupt parsing. Sending the panel to stderr keeps stdout = clean tool ids.
_discover_announced() {
    local src
    for src in brew cargo pipx npm userbin; do
        { claw_prog_item "$src"; claw_prog_phase scan; } >&2
    done
    _discover_clean
}

# ── commands ────────────────────────────────────────────────────────────────
pkg_list() {
    local n; n=$(_m_ids | grep -c . || true)
    printf "\n  ${c_cyan}tracked tools${c_reset} ${c_dim}(%s) — %s${c_reset}\n\n" "$n" "$MANIFEST"
    awk -F'|' '/^##/{printf "  \033[1m%s\033[0m\n", substr($0,3); next}
               /^#|^$/{next}
               {printf "    %-22s \033[2m%s\033[0m\n", $1, $2}' "$MANIFEST"
}

pkg_scan() {
    local untracked=() t
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        _m_has "$t" || untracked+=("$t")
    done < <(claw_prog_begin "pkg scan" 0 >&2; _discover_announced; claw_prog_end >&2)
    if (( ${#untracked[@]} == 0 )); then
        log_success "manifest is current — no untracked tools"
        return 0
    fi
    printf "\n  ${c_cyan}untracked tools${c_reset} ${c_dim}(installed but not in the manifest)${c_reset}\n\n"
    printf "    %s\n" "${untracked[@]}"
    printf "\n  ${c_dim}run 'claw pkg track' to add them to the repo manifest${c_reset}\n"
    return 0
}

# Best-effort source inference for a discovered tool.
_infer_source() {
    local id="$1"
    command -v brew  &>/dev/null && brew leaves 2>/dev/null | sed 's#.*/##' | grep -qxF "$id" && { echo brew; return; }
    command -v cargo &>/dev/null && cargo install --list 2>/dev/null | grep -qE "^$id v" && { echo cargo; return; }
    command -v pipx  &>/dev/null && pipx list --short 2>/dev/null | awk '{print $1}' | grep -qxF "$id" && { echo pipx; return; }
    command -v npm   &>/dev/null && npm ls -g --depth=0 --parseable 2>/dev/null | sed 's#.*/##' | grep -qxF "$id" && { echo npm; return; }
    [[ -x "$HOME/.local/bin/$id" || -x "$HOME/go/bin/$id" ]] && { echo eget; return; }   # user binary — assume eget-fetchable
    echo manual
}

pkg_track() {
    local commit=0; [[ "${1:-}" == "--commit" ]] && commit=1
    local added=() t src
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        _m_has "$t" && continue
        src="$(_infer_source "$t")"
        printf '%s|%s\n' "$t" "$src" >> "$MANIFEST"
        added+=("$t($src)")
    done < <(claw_prog_begin "pkg track" 0 >&2; _discover_announced; claw_prog_end >&2)
    if (( ${#added[@]} == 0 )); then log_success "nothing new to track"; return 0; fi
    log_success "tracked ${#added[@]}: ${c_dim}${added[*]}${c_reset}"
    if (( commit )) && command -v git &>/dev/null && git -C "$DOTFILES" rev-parse &>/dev/null; then
        git -C "$DOTFILES" add "config/manifest/tools.list" 2>/dev/null
        git -C "$DOTFILES" commit -q -m "pkg: track newly-installed tools (${added[*]})" 2>/dev/null \
            && log_success "committed to repo manifest"
    else
        log_info "review + commit: ${c_white}git -C $DOTFILES add config/manifest/tools.list${c_reset}"
    fi
}

pkg_add() {
    local id="$1" src="${2:-$(_infer_source "$1")}"
    _m_has "$id" && { log_skip "$id already tracked"; return 0; }
    printf '%s|%s\n' "$id" "$src" >> "$MANIFEST"
    log_success "added $id|$src to manifest"
}

# Returns: 0 installed · 10 already-present (skip) · 1 failed/unknown.
_install_via() {  # _install_via <id> <source>
    local id="$1" src="$2"
    command -v "$id" &>/dev/null && return 10
    case "$src" in
        brew)    claw_prog_run install -- brew install "$id" ;;
        apt)     claw_prog_run install -- sudo apt-get install -y "$id" ;;
        cargo)   claw_prog_run build   -- cargo install "$id" ;;
        pipx)    claw_prog_run install -- pipx install "$id" ;;
        gem)     claw_prog_run install -- gem install "$id" ;;
        npm)     claw_prog_run install -- npm install -g "$id" ;;
        go:*)    claw_prog_run build   -- go install "${src#go:}@latest" ;;
        eget|eget:*)
                 claw_prog_run download -- sh -c 'command -v eget >/dev/null && eget "$1" --to "$2" 2>/dev/null || eget "$3" --to "$2" 2>/dev/null' \
                     _ "${src#eget:}" "$HOME/.local/bin/$id" "$id" ;;
        curl:*)  claw_prog_run install -- sh -c "curl -fsSL \"\$1\" | sh" _ "${src#curl:}" ;;
        manual)  return 10 ;;   # nothing to install — treat as present/skip
        *)       return 1 ;;
    esac
}

pkg_install() {
    local want="${1:-all}" id src rc
    local -a tools=()
    while IFS='|' read -r id src _; do
        [[ "$id" =~ ^#|^$ ]] && continue
        id="${id// /}"; src="${src// /}"
        [[ "$want" != "all" && "$want" != "$id" ]] && continue
        tools+=("$id|$src")
    done < "$MANIFEST"

    claw_prog_begin "pkg install" "${#tools[@]}"
    local entry
    for entry in "${tools[@]}"; do
        id="${entry%%|*}"; src="${entry#*|}"
        claw_prog_item "$id" "$src"
        _install_via "$id" "$src"; rc=$?
        case "$rc" in
            0)  claw_prog_ok ;;
            10) claw_prog_skip "present" ;;
            *)  claw_prog_fail ;;
        esac
    done
    claw_prog_end
}

pkg_update() {
    if command -v topgrade &>/dev/null; then
        log_info "updating everything via ${c_white}topgrade${c_reset} (covers all manifest sources)"
        topgrade --disable=containers "$@"; return
    fi
    log_info "topgrade not installed — per-source update (run: claw install nextgen)"
    command -v brew  &>/dev/null && { log_info "brew";  brew update && brew upgrade; }
    [[ "$PKG_MANAGER" == apt ]]   && { log_info "apt";   sudo apt-get update && sudo apt-get upgrade -y; }
    command -v cargo &>/dev/null && command -v cargo-install-update &>/dev/null && { log_info "cargo"; cargo install-update -a; }
    command -v pipx  &>/dev/null && { log_info "pipx";  pipx upgrade-all; }
}

case "${1:-list}" in
    list)     pkg_list ;;
    scan)     pkg_scan ;;
    track)    shift; pkg_track "${1:-}" ;;
    add)      shift; [[ -z "${1:-}" ]] && { echo "usage: claw pkg add <id> [source]"; exit 1; }; pkg_add "$@" ;;
    install)  shift; pkg_install "${1:-all}" ;;
    update)   shift; pkg_update "$@" ;;
    *)        echo "usage: claw pkg {list|scan|track [--commit]|add <id> [src]|install [id|all]|update}" ;;
esac
