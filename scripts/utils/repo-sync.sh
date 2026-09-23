#!/usr/bin/env bash
# scripts/utils/repo-sync.sh — phase 1 of `claw update`: the dotfiles update themselves.
#
# Conservative by design (spine: one updater front door, ff-only repo phase):
#   - fast-forward pull ONLY — a dirty tree, missing upstream, or diverged
#     branch SKIPS the pull with a printed reason and exits 0. Never
#     auto-stash, never merge, never rebase.
#   - after a real pull, only the derived artifacts the pull actually touched
#     are regenerated (from `git diff --name-only <old>..<new>`):
#       scripts/utils/gen-fastfetch.py → re-run the generator (needs python3)
#       shell/…                        → stow -R shell (non-fatal; hint: claw restore-shell)
#       claude/…                       → scripts/setup/link-claude.sh
#       any pull                       → integrity generate (quiet)
#     Regen failures are warnings only — exit stays 0 unless git itself errors.
#
# argv:
#   --dry-run           fetch + report what a pull would do; pull nothing, no regens
#   --non-interactive   accepted for phase symmetry with system-update.sh
#                       (repo-sync never prompts, so it is a no-op here)
#
# Prints one status line: `repo: <old>..<new>` | `repo: up-to-date` |
# `repo: skipped (<reason>)`. Appends one receipt row per run to
# ~/.cache/claw/updates.tsv (ISO-ts \t trigger \t duration_s \t ok|fail \t detail).
set -uo pipefail

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAW_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claw"
RECEIPTS="$CLAW_CACHE_DIR/updates.tsv"
TRIGGER="${CLAW_UPDATE_TRIGGER:-manual}"

# ============================================
# THEME — active Open Claw palette (theme.sh single source of truth).
# Refined-dark fallbacks so repo-sync renders mid-bootstrap too.
# ============================================
# shellcheck source=/dev/null
[ -r "$SCRIPT_DIR/theme.sh" ] && . "$SCRIPT_DIR/theme.sh" 2>/dev/null || true
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m'
c_green=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
c_purple=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"$'m'
c_red=$'\e[38;2;'"${CLAW_RGB_RED:-255;123;114}"$'m'
c_dim=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m'
c_bold=$'\e[1m'

err()  { printf "  ${c_red}✗${c_reset} %s\n" "$*" >&2; }
info() { printf "  ${c_cyan}●${c_reset} %s\n" "$*"; }
ok()   { printf "  ${c_green}✓${c_reset} %s\n" "$*"; }

# ============================================
# CLI
# ============================================
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run)         DRY_RUN=1 ;;
        --non-interactive) ;;  # phase symmetry only — repo-sync never prompts
        -h|--help)         sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                 err "unknown flag: $arg"; exit 2 ;;
    esac
done

# GNU `timeout` is absent on stock macOS (brew coreutils ships only gtimeout).
# The fetch/pull below are timeout-bounded so a blackholed remote can't wedge
# the weekly timer; shim like update-status.sh — unbounded beats exit 127.
if ! command -v timeout >/dev/null 2>&1; then
    if command -v gtimeout >/dev/null 2>&1; then
        timeout() { gtimeout "$@"; }
    else
        timeout() { shift; "$@"; }
    fi
fi

# ============================================
# RECEIPT — one TSV row per run (shared updates.tsv, read by claw update --last)
# ============================================
_receipt() {  # _receipt <ok|fail> <detail>
    {
        mkdir -p "$CLAW_CACHE_DIR" &&
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TRIGGER" "$SECONDS" "$1" "$2" \
            >> "$RECEIPTS"
    } 2>/dev/null || true
}

# _finish <exit-code> <ok|fail> <detail> — receipt then exit, single exit path.
_finish() { _receipt "$2" "$3"; exit "$1"; }

# _skip <reason-slug> <printed reason> [hint] — conservative skip: exit 0.
_skip() {
    printf "  ${c_cyan}●${c_reset} repo: skipped (%s)" "$2"
    [ -n "${3:-}" ] && printf " ${c_dim}— %s${c_reset}" "$3"
    printf "\n"
    _finish 0 ok "phase=repo skipped=$1"
}

printf "\n  ${c_purple}${c_bold}repo sync${c_reset}  ${c_dim}— %s${c_reset}\n" "$DOTFILES"

# ============================================
# GUARDS — dirty / no-upstream / diverged all skip (exit 0), per design.
# ============================================
cd "$DOTFILES" 2>/dev/null || { err "dotfiles not found: $DOTFILES"; _finish 1 fail "phase=repo error=missing-dir"; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
    _skip "not-a-repo" "not a git checkout" "tarball install? clone the repo to pull updates"

# The integrity manifest is regenerated after every pull (below) and hashes
# untracked machine-local files, so on a live box it ALWAYS drifts from the
# committed copy — bootstrap Step 9b rewrites it on day 0. Local drift in it
# must never wedge the pull (the first post-pull regen would deadlock every
# later sync), so it is excluded from the dirty check and reset before pulling.
MANIFEST_REL="config/integrity/manifest.sha256"

# -uno: untracked files (e.g. .env, ~/.zshrc.local backups) never block a
# fast-forward pull — only modified/staged tracked files make the tree dirty.
[ -n "$(git status --porcelain -uno -- . ":(exclude)$MANIFEST_REL" 2>/dev/null)" ] && \
    _skip "dirty-tree" "dirty tree" "commit or stash local edits, then re-run claw update --repo"

git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1 || \
    _skip "no-upstream" "no upstream" "set one: git branch --set-upstream-to origin/<branch>"

if ! timeout 30 git fetch --quiet 2>/dev/null; then
    err "repo: fetch failed ${c_dim}(offline? remote unreachable?)${c_reset}"
    _finish 1 fail "phase=repo error=fetch-failed"
fi

behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)

[ "$behind" -gt 0 ] && [ "$ahead" -gt 0 ] && \
    _skip "diverged" "diverged" "ahead $ahead / behind $behind — reconcile by hand, never auto-merged"

if [ "$behind" -eq 0 ]; then
    ok "repo: up-to-date"
    _finish 0 ok "phase=repo result=up-to-date"
fi

# ============================================
# PULL (ff-only) — or report the would-be pull under --dry-run
# ============================================
old=$(git rev-parse --short HEAD)
if [ "$DRY_RUN" -eq 1 ]; then
    info "repo: ${old}..$(git rev-parse --short '@{u}') ${c_dim}(dry-run — pull + regen skipped, behind $behind)${c_reset}"
    _finish 0 ok "phase=repo dry-run=1 behind=$behind"
fi

# Machine-local manifest drift would make the ff checkout conflict whenever
# the pull also touches it — reset to HEAD first; the post-pull regen below
# rewrites it anyway. Only tracked-modified state matches (-uno hides untracked).
if [ -n "$(git status --porcelain -uno -- "$MANIFEST_REL" 2>/dev/null)" ]; then
    git checkout HEAD -- "$MANIFEST_REL" 2>/dev/null || true
fi

if ! timeout 30 git pull --ff-only --quiet 2>/dev/null; then
    err "repo: pull failed ${c_dim}(ff-only — inspect: git -C $DOTFILES pull --ff-only)${c_reset}"
    _finish 1 fail "phase=repo error=pull-failed"
fi
new=$(git rev-parse --short HEAD)
ok "repo: ${old}..${new} ${c_dim}($behind commit(s))${c_reset}"

# ============================================
# CONDITIONAL REGEN — only what the pull actually changed. All non-fatal:
# the pull already succeeded, so a regen hiccup warns + hints, never exit≠0.
# ============================================
changed="$(git diff --name-only "${old}..${new}" 2>/dev/null || true)"
regens=""

# Herestrings, not `printf | grep -q`: under pipefail an early-exiting grep -q
# SIGPIPEs printf on very large pulls (>pipe buffer of paths), turning a real
# match into rc 141 = false — silently skipping the regen that run needed most.
if grep -q '^scripts/utils/gen-fastfetch\.py$' <<<"$changed"; then
    if command -v python3 &>/dev/null; then
        if python3 "$DOTFILES/scripts/utils/gen-fastfetch.py" >/dev/null 2>&1; then
            ok "regen: fastfetch dashboards ${c_dim}(gen-fastfetch.py changed)${c_reset}"
            regens="${regens}fastfetch,"
        else
            err "regen: gen-fastfetch.py failed ${c_dim}(non-fatal — run: python3 scripts/utils/gen-fastfetch.py)${c_reset}"
        fi
    else
        info "regen: gen-fastfetch.py changed but python3 missing ${c_dim}— skipped${c_reset}"
    fi
fi

if grep -q '^shell/' <<<"$changed"; then
    if ! command -v stow &>/dev/null; then
        info "regen: shell/ changed but stow missing ${c_dim}— skipped (install stow, then: claw restore-shell)${c_reset}"
    elif stow -R -d "$DOTFILES" -t "$HOME" shell 2>/dev/null; then
        ok "regen: shell symlinks refreshed ${c_dim}(stow -R shell)${c_reset}"
        regens="${regens}stow,"
    else
        err "regen: stow -R shell failed ${c_dim}(non-fatal — fix with: claw restore-shell)${c_reset}"
    fi
fi

if grep -q '^claude/' <<<"$changed"; then
    if bash "$DOTFILES/scripts/setup/link-claude.sh" >/dev/null 2>&1; then
        ok "regen: claude/ deployed ${c_dim}(link-claude.sh)${c_reset}"
        regens="${regens}claude,"
    else
        err "regen: link-claude.sh failed ${c_dim}(non-fatal — run: claw harness deploy)${c_reset}"
    fi
fi

# Any real pull refreshes the integrity manifest so verify/audit track upstream.
if [ -r "$DOTFILES/scripts/utils/integrity.sh" ]; then
    if bash "$DOTFILES/scripts/utils/integrity.sh" generate >/dev/null 2>&1; then
        ok "regen: integrity manifest"
        regens="${regens}integrity"
    else
        err "regen: integrity generate failed ${c_dim}(non-fatal — run: claw integrity generate)${c_reset}"
    fi
fi

regens="${regens%,}"
_finish 0 ok "phase=repo pulled=${old}..${new} regen=${regens:-none}"
