#!/usr/bin/env bash
################################################################################
# scripts/utils/claude-config-policy.sh
#
# Enforces the Claude Code (CLI) vs Claude Desktop config boundary defined in
# docs/claude-config-boundaries.md.
#
# Policy summary (macOS):
#   - Desktop owns MCP server registry. Sever the dot-files mcp.json symlink.
#   - dot-files keeps owning CLI-only concerns (CLAUDE.md, hooks, scope, commands).
#
# Idempotent. Run dry-run first to see what would change:
#   bash scripts/utils/claude-config-policy.sh           # dry-run (default)
#   bash scripts/utils/claude-config-policy.sh --apply   # actually apply
#
# On Linux this script no-ops (no competing Desktop on that platform).
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/cinematic.sh"

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
DESKTOP_CONFIG_DIR="$HOME/Library/Application Support/Claude"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOTFILES_MCP_TARGET="$DOTFILES_DIR/claude/mcp.json"

_banner_basic "CLAUDE CONFIG POLICY" "BOUNDARY ENFORCER" "Desktop wins on Mac · CLI-only items stay symlinked"

# ── Detect platform ─────────────────────────────────────────────────────────
case "$(uname -s)" in
    Darwin)
        PLATFORM="mac"
        DESKTOP_INSTALLED=0
        if [[ -d "$DESKTOP_CONFIG_DIR" ]]; then
            DESKTOP_INSTALLED=1
        fi
        ;;
    Linux)
        PLATFORM="linux"
        DESKTOP_INSTALLED=0   # no Desktop on Linux as of 2026-05
        ;;
    *)
        log_warning "Unknown platform $(uname -s) — exiting"
        exit 0
        ;;
esac

log_info "platform: ${c_white}${PLATFORM}${c_reset}  ·  desktop: $([[ $DESKTOP_INSTALLED == 1 ]] && echo "installed" || echo "absent")"
log_info "claude home: ${c_white}${CLAUDE_HOME}${c_reset}"
log_info "mode: ${c_white}$([[ $APPLY == 1 ]] && echo "APPLY" || echo "DRY-RUN")${c_reset}"

if [[ "$PLATFORM" != "mac" ]] || (( DESKTOP_INSTALLED == 0 )); then
    log_skip "no Desktop on this platform — policy is a no-op"
    exit 0
fi

# ── Check 1: mcp.json symlink ──────────────────────────────────────────────
_section 1 "MCP  Registry  Boundary"

MCP_SYMLINK="$CLAUDE_HOME/mcp.json"

if [[ -L "$MCP_SYMLINK" ]]; then
    TARGET="$(readlink "$MCP_SYMLINK")"
    log_info "found symlink: ${c_dim}${MCP_SYMLINK} → ${TARGET}${c_reset}"

    # Only act if it points into the dot-files repo (avoid clobbering user customizations).
    if [[ "$TARGET" == *"/dot-files/claude/mcp.json" ]]; then
        log_warning "dot-files-managed mcp.json detected — Desktop owns MCP on macOS"
        if (( APPLY == 1 )); then
            rm -f "$MCP_SYMLINK"
            log_success "removed symlink (CLI will fall back to ~/.claude/settings.json mcpServers)"
        else
            log_info "would remove: ${c_yellow}rm $MCP_SYMLINK${c_reset}"
        fi
    else
        log_skip "symlink points outside dot-files — leaving alone"
    fi
elif [[ -e "$MCP_SYMLINK" ]]; then
    log_skip "${MCP_SYMLINK} is a real file (not a symlink) — leaving alone"
else
    log_success "no mcp.json symlink — boundary already enforced"
fi

# ── Check 2: confirm CLI-only symlinks are intact ──────────────────────────
_section 2 "CLI-only  Symlinks  (should remain)"

declare -a CLI_ONLY=(
    "CLAUDE.md:claude/CLAUDE.md"
    "scope.txt:claude/scope.txt"
    "hooks:claude/hooks"
    "commands:claude/commands"
)

for entry in "${CLI_ONLY[@]}"; do
    name="${entry%%:*}"
    rel_target="${entry##*:}"
    path="$CLAUDE_HOME/$name"

    if [[ -L "$path" ]]; then
        target="$(readlink "$path")"
        if [[ "$target" == *"/dot-files/$rel_target" ]]; then
            log_success "$name → dot-files (CLI-only, kept)"
        else
            log_warning "$name symlink points elsewhere: $target"
        fi
    elif [[ -e "$path" ]]; then
        log_warning "$name exists as real file (not symlinked) — manual setup?"
    else
        log_warning "$name missing — bootstrap may need re-run"
    fi
done

# ── Summary ────────────────────────────────────────────────────────────────
_section 3 "Summary"
if (( APPLY == 1 )); then
    log_success "policy applied"
    log_info "next: open Claude Desktop, manage MCP via Extensions UI"
    log_info "next: any CLI-side MCP need? use ${c_white}claude mcp add --user <name> <cmd>${c_reset}"
else
    log_info "dry-run complete — re-run with ${c_white}--apply${c_reset} to make changes"
fi
echo ""
