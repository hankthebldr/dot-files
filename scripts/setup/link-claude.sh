#!/usr/bin/env bash
# scripts/setup/link-claude.sh
#
# Deploy the repo's Claude Code tree into ~/.claude/ with item-level symlinks.
#
# Why not GNU Stow? The `claude/` package is laid out as claude/CLAUDE.md,
# claude/hooks/, claude/skills/… — stowing it would splatter those into $HOME,
# not $HOME/.claude. And ~/.claude/skills is a REAL directory full of managed
# marketplace symlinks, so a directory-level link would clobber them. This
# linker is therefore surgical: it links individual files/dirs, backs up real
# collisions, and skips (never overwrites) managed skills it didn't create.
#
# Idempotent. Honors DRY_RUN=1 / --dry-run. Safe to run on every bootstrap.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLAUDE_SRC="$DOTFILES_DIR/claude"
CLAUDE_DST="${CLAUDE_HOME:-$HOME/.claude}"
HARNESS="$CLAUDE_SRC/harness"

# Logging — reuse the repo's logger if present, else minimal fallbacks.
if [[ -f "$DOTFILES_DIR/scripts/utils/logger.sh" ]]; then
    # shellcheck disable=SC1091
    source "$DOTFILES_DIR/scripts/utils/logger.sh"
else
    log_info()    { printf '  • %s\n' "$*"; }
    log_success() { printf '  ✓ %s\n' "$*"; }
    log_warning() { printf '  ! %s\n' "$*" >&2; }
    log_error()   { printf '  ✗ %s\n' "$*" >&2; }
fi

DRY_RUN="${DRY_RUN:-0}"
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY_RUN=1

BACKUP_DIR="$HOME/.dotfiles-backups/claude-$(date +%Y%m%d-%H%M%S)"
_backed_up=0

_run() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '    [dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# _link <src> <dst> [label]
# Create dst -> src. Already-correct links are a no-op; wrong symlinks are
# repointed; real files/dirs are backed up first. Never silently destroys data.
_link() {
    local src="$1" dst="$2" label="${3:-$(basename "$dst")}"
    [[ -e "$src" ]] || { log_warning "skip $label — source missing: $src"; return 0; }

    if [[ -L "$dst" ]]; then
        local cur; cur="$(readlink -f "$dst" 2>/dev/null || true)"
        if [[ "$cur" == "$(readlink -f "$src")" ]]; then
            return 0   # already correct
        fi
        # A symlink we didn't make (e.g. a managed marketplace skill). Don't
        # touch skill/command/agent targets we don't own — only repoint links
        # that already point inside the dotfiles tree.
        if [[ "$cur" == "$DOTFILES_DIR"/* ]]; then
            _run ln -sfn "$src" "$dst"
            log_success "relinked $label"
        else
            log_warning "skip $label — $dst is a managed symlink (not ours)"
        fi
        return 0
    fi

    if [[ -e "$dst" ]]; then
        # Real file/dir in the way — back it up, then link.
        _run mkdir -p "$BACKUP_DIR"
        _run mv "$dst" "$BACKUP_DIR/"
        _backed_up=1
        log_warning "backed up existing $label -> $BACKUP_DIR/"
    fi
    _run mkdir -p "$(dirname "$dst")"
    _run ln -s "$src" "$dst"
    log_success "linked $label"
}

# Link every entry of a source dir into a destination dir (per-item, so we
# share the dir with managed content instead of replacing it). Skips dotfiles
# and _scaffold dirs. <pattern> filters (e.g. '*.md' or '*' for dirs).
_link_into() {
    local src_dir="$1" dst_dir="$2" find_args=("${@:3}")
    [[ -d "$src_dir" ]] || return 0
    _run mkdir -p "$dst_dir"
    local entry name
    while IFS= read -r entry; do
        name="$(basename "$entry")"
        [[ "$name" == _* || "$name" == .* ]] && continue
        _link "$entry" "$dst_dir/$name" "$(basename "$dst_dir")/$name"
    done < <(find "$src_dir" -mindepth 1 -maxdepth 1 "${find_args[@]}" 2>/dev/null | sort)
}

main() {
    if [[ ! -d "$CLAUDE_SRC" ]]; then
        log_error "no claude/ tree at $CLAUDE_SRC"; exit 1
    fi
    [[ "$DRY_RUN" == "1" ]] && log_info "DRY RUN — no changes will be made"
    log_info "Deploying claude/ → $CLAUDE_DST"

    # 1. Top-level config files + hooks dir.
    _link "$CLAUDE_SRC/CLAUDE.md" "$CLAUDE_DST/CLAUDE.md" "CLAUDE.md"
    [[ -f "$CLAUDE_SRC/scope.txt" ]] && _link "$CLAUDE_SRC/scope.txt" "$CLAUDE_DST/scope.txt" "scope.txt"
    [[ -d "$CLAUDE_SRC/hooks" ]]    && _link "$CLAUDE_SRC/hooks"    "$CLAUDE_DST/hooks"    "hooks/"

    # 2. Slash commands (repo + harness).
    _link_into "$CLAUDE_SRC/commands"   "$CLAUDE_DST/commands" -name '*.md'
    _link_into "$HARNESS/commands"      "$CLAUDE_DST/commands" -name '*.md'

    # 3. Skills — repo security skills, vendored agent-skills, custom harness.
    #    Per-item so we coexist with managed marketplace skills (same-named
    #    managed symlinks are skipped, not clobbered).
    _link_into "$CLAUDE_SRC/skills"       "$CLAUDE_DST/skills" -type d
    _link_into "$CLAUDE_SRC/agent-skills" "$CLAUDE_DST/skills" -type d
    _link_into "$HARNESS/skills"          "$CLAUDE_DST/skills" -type d

    # 4. Custom subagents.
    _link_into "$HARNESS/agents" "$CLAUDE_DST/agents" -name '*.md'

    # 5. Register hooks in settings.json (only if Claude Code is installed).
    if [[ "$DRY_RUN" != "1" && -f "$CLAUDE_DST/settings.json" && -x "$CLAUDE_SRC/install-hooks.sh" ]]; then
        log_info "Registering hooks in settings.json…"
        bash "$CLAUDE_SRC/install-hooks.sh" || log_warning "install-hooks.sh reported an issue"
    elif [[ ! -f "$CLAUDE_DST/settings.json" ]]; then
        log_warning "no $CLAUDE_DST/settings.json — skipping hook registration (is Claude Code installed?)"
    fi

    [[ "$_backed_up" == "1" ]] && log_info "backups saved under $BACKUP_DIR"
    log_success "claude/ deployed"
}

main "$@"
