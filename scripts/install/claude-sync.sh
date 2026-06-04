#!/usr/bin/env bash
# scripts/install/claude-sync.sh
#
# Replay a Claude Code state captured by claude-snapshot.sh.
# Run this on any machine (e.g. BD790i) AFTER `git pull` so its
# ~/.claude/ and ~/.agents/ match the dot-files manifests.
#
# Policy: warn-and-continue. Each step logs its own failure and the
# script keeps going. Final exit code is 0 (with a tail summary) so
# this can run unattended in a bootstrap flow.
#
# Manual override:
#   CLAUDE_SYNC_DRY_RUN=1   print actions without executing
#   CLAUDE_SYNC_FORCE=1     reinstall plugins even if already present
#
# Usage:
#   bash scripts/install/claude-sync.sh

set -e

DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
[[ -d "$DOTFILES" ]] || DOTFILES="$HOME/Github/Github_desktop/dot-files"

# shellcheck source=/dev/null
source "$DOTFILES/scripts/utils/logger.sh" 2>/dev/null || {
    log_info()    { echo "[INFO] $*"; }
    log_success() { echo "[OK]   $*"; }
    log_warning() { echo "[WARN] $*"; }
    log_error()   { echo "[ERR]  $*" >&2; }
}

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
AGENTS_HOME="${AGENTS_HOME:-$HOME/.agents}"
MANIFEST_DIR="$DOTFILES/claude/manifests"
AGENT_SKILLS_DIR="$DOTFILES/claude/agent-skills"

DRY_RUN="${CLAUDE_SYNC_DRY_RUN:-0}"
FORCE="${CLAUDE_SYNC_FORCE:-0}"

# Counters for the tail summary
declare -i n_installed=0 n_skipped=0 n_already=0 n_failed=0

run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "DRY-RUN: $*"
        return 0
    fi
    "$@"
}

# ======================================================================
# Henry's contribution slot — edit this function.
# ======================================================================
#
# should_skip_plugin <plugin_id>
#   Return 0 (true) to skip the plugin on this machine.
#   Return 1 (false) to proceed with installation.
#
# WHY THIS MATTERS:
#   BD790i is headless Linux. Some plugins on your Mac are mac-only
#   (Messages, AppleScript, computer-use), GUI-bound (browser MCPs),
#   or require interactive auth that doesn't make sense on a server.
#   Installing them anyway wastes time and clutters the plugin cache.
#
# CONSTRAINTS:
#   - $plugin_id is the form `name@marketplace`, e.g.
#     `imessage@claude-plugins-official`.
#   - $(uname -s) is "Darwin" on Mac, "Linux" on BD790i.
#   - When skipping, log_warning with a one-line reason so the tail
#     summary tells you what was excluded and why.
#
# THINGS TO CONSIDER:
#   - Pure Mac-only: imessage. Skip on Linux.
#   - Headless-incompatible (browser/GUI): playwright is fine on Linux
#     (runs Chromium). figma/firebase need interactive auth — your call.
#   - Heavy LSPs (jdtls-lsp, swift-lsp, pyright-lsp, typescript-lsp):
#     useful on BD790i? Depends on what you code there.
#   - Plugins you've never used: cheap to install, but you might want a
#     curated list per machine.
#
# TODO(henry): Implement the policy. Default is "install everything".
should_skip_plugin() {
    local plugin_id="$1"
    local host_os
    host_os=$(uname -s)

    # >>> YOUR CODE HERE <<<
    # Example shape (delete and replace with real policy):
    # case "$plugin_id" in
    #     imessage@*)
    #         [[ "$host_os" != "Darwin" ]] && {
    #             log_warning "skip $plugin_id (macOS-only, host is $host_os)"
    #             return 0
    #         }
    #         ;;
    # esac

    return 1  # default: install everything
}
# ======================================================================
# End contribution slot
# ======================================================================

# ----------------------------------------------------------------------
# 0. Activate the dotfiles pre-commit guard. core.hooksPath is LOCAL git
#    config (not pushed), so every clone must opt in once — doing it here
#    means each synced box gets the skill-injection guard automatically.
# ----------------------------------------------------------------------
activate_git_hooks() {
    [[ -d "$DOTFILES/.git" || -f "$DOTFILES/.git" ]] || {
        log_warning "dotfiles is not a git repo — skip hook activation"
        return 0
    }
    [[ -f "$DOTFILES/git-hooks/pre-commit" ]] || {
        log_warning "git-hooks/pre-commit missing — skip hook activation"
        return 0
    }
    if [[ "$(git -C "$DOTFILES" config --get core.hooksPath 2>/dev/null)" == "git-hooks" ]]; then
        log_info "pre-commit guard already active (core.hooksPath=git-hooks)"
    else
        run git -C "$DOTFILES" config core.hooksPath git-hooks \
            && log_success "activated pre-commit guard (core.hooksPath=git-hooks)" \
            || log_warning "could not set core.hooksPath (continuing)"
    fi
}

ensure_prereqs() {
    if ! command -v claude &>/dev/null; then
        log_error "claude CLI not on PATH — install Claude Code first"
        exit 1
    fi
    if ! command -v jq &>/dev/null; then
        log_error "jq required for parsing manifests"
        exit 1
    fi
    if [[ ! -d "$MANIFEST_DIR" ]]; then
        log_error "manifest dir not found: $MANIFEST_DIR (run a snapshot first)"
        exit 1
    fi
}

# ----------------------------------------------------------------------
# 1. Register marketplaces (must happen before plugin install)
# ----------------------------------------------------------------------
sync_marketplaces() {
    local src="$MANIFEST_DIR/marketplaces.json"
    if [[ ! -f "$src" ]]; then
        log_warning "no marketplaces manifest — skipping"
        return 0
    fi

    local existing
    existing=$(claude plugin marketplace list 2>/dev/null | awk '{print $1}' || true)

    jq -r 'to_entries[] | "\(.key)\t\(.value.source.repo // .value.source.url // "")"' "$src" |
    while IFS=$'\t' read -r name repo; do
        if echo "$existing" | grep -qx "$name"; then
            log_info "marketplace $name already registered"
            continue
        fi
        if [[ -z "$repo" ]]; then
            log_warning "marketplace $name has no source — skipping"
            continue
        fi
        log_info "registering marketplace: $name ($repo)"
        run claude plugin marketplace add "$repo" \
            || log_warning "failed to add marketplace $name (continuing)"
    done
}

# ----------------------------------------------------------------------
# 2. Install plugins
# ----------------------------------------------------------------------
sync_plugins() {
    local src="$MANIFEST_DIR/plugins.txt"
    if [[ ! -f "$src" ]]; then
        log_warning "no plugins manifest — skipping"
        return 0
    fi

    # `claude plugin list` formats each entry as "  ❯ name@marketplace" plus
    # several indented metadata lines — grep the marker line and trim.
    local installed
    installed=$(claude plugin list 2>/dev/null | grep '❯ .*@' | sed 's/.*❯ //; s/ *$//' || true)

    while IFS= read -r plugin_id; do
        [[ -z "$plugin_id" || "$plugin_id" =~ ^# ]] && continue

        if should_skip_plugin "$plugin_id"; then
            n_skipped+=1
            continue
        fi

        if [[ "$FORCE" != "1" ]] && echo "$installed" | grep -qxF "$plugin_id"; then
            log_info "plugin $plugin_id already installed"
            n_already+=1
            continue
        fi

        log_info "installing $plugin_id"
        if run claude plugin install "$plugin_id"; then
            n_installed+=1
        else
            log_warning "failed to install $plugin_id (continuing)"
            n_failed+=1
        fi
    done < "$src"
}

# ----------------------------------------------------------------------
# 3. Replay agent skills — orphan SKILL.md + sourced (from lock)
# ----------------------------------------------------------------------
sync_agent_skills() {
    local target_skills="$AGENTS_HOME/skills"
    mkdir -p "$target_skills"

    # 3a. Orphan skills — copy SKILL.md (+ any auxiliary files) into place
    if [[ -d "$AGENT_SKILLS_DIR" ]]; then
        for skill in "$AGENT_SKILLS_DIR"/*/; do
            [[ -d "$skill" ]] || continue
            local name
            name=$(basename "$skill")
            local dest="$target_skills/$name"
            if [[ -d "$dest" ]] && [[ "$FORCE" != "1" ]]; then
                log_info "agent skill $name already present"
                continue
            fi
            log_info "deploying agent skill: $name"
            run mkdir -p "$dest"
            run cp -R "$skill"/* "$dest/" 2>/dev/null \
                || log_warning "failed to copy $name (continuing)"
        done
    fi

    # 3b. Sourced skills from lockfile — we can't reliably re-install
    # without knowing the agents CLI; just copy the lockfile so the
    # agents tool can re-sync next time it runs.
    local lock_src="$MANIFEST_DIR/agent-skills.lock.json"
    local lock_dst="$AGENTS_HOME/.skill-lock.json"
    if [[ -f "$lock_src" ]]; then
        if [[ ! -f "$lock_dst" ]] || ! cmp -s "$lock_src" "$lock_dst"; then
            log_info "updating .skill-lock.json"
            run cp "$lock_src" "$lock_dst"
        fi
    fi
}

# ----------------------------------------------------------------------
# 3.5 Scan synced skills for prompt-injection / XSS (defense-in-depth).
#     The pre-commit hook only guards commits INTO this repo; skills
#     synced from external sources (lockfile repos, marketplaces) land in
#     ~/.agents directly and never cross that boundary. This is the control
#     that catches a poisoned skill on the box where it actually lands.
#     Non-fatal by default (warn-and-continue); CLAUDE_SYNC_STRICT=1 aborts.
# ----------------------------------------------------------------------
scan_skills() {
    local scanner="$DOTFILES/claude/scan-skills.sh"
    [[ -x "$scanner" ]] || {
        log_warning "scan-skills.sh missing — skipping skill scan"
        return 0
    }
    log_info "scanning synced skills for injection/XSS"
    local out
    if out=$("$scanner" "$AGENTS_HOME/skills" "$AGENT_SKILLS_DIR" 2>&1); then
        log_success "skill scan clean"
    else
        log_error "⚠ POISONED SKILL DETECTED in synced skills:"
        printf '%s\n' "$out" | grep -E '^(FAIL|WARN|RESULT)' >&2 || printf '%s\n' "$out" >&2
        log_error "  the live ~/.agents copy is NOT overwritten by a normal sync if it"
        log_error "  already exists — re-run clean: CLAUDE_SYNC_FORCE=1 bash scripts/install/claude-sync.sh"
        n_failed+=1
        [[ "${CLAUDE_SYNC_STRICT:-0}" == "1" ]] && {
            log_error "CLAUDE_SYNC_STRICT=1 → aborting sync"
            exit 1
        }
    fi
}

# ----------------------------------------------------------------------
# 4. Summary
# ----------------------------------------------------------------------
print_summary() {
    log_info ""
    log_info "─── claude-sync summary ───"
    log_info "  installed:    $n_installed"
    log_info "  already-set:  $n_already"
    log_info "  skipped:      $n_skipped  (see warnings above)"
    if (( n_failed > 0 )); then
        log_warning "  failed:       $n_failed  (see warnings above)"
    else
        log_info "  failed:       0"
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
        log_warning "(DRY-RUN mode: nothing was actually changed)"
    fi
}

main() {
    log_info "Syncing Claude state from $MANIFEST_DIR"
    log_info "Host: $(uname -sm) — DRY_RUN=$DRY_RUN  FORCE=$FORCE"
    ensure_prereqs
    activate_git_hooks
    sync_marketplaces
    sync_plugins
    sync_agent_skills
    scan_skills
    print_summary
}

main "$@"
