#!/usr/bin/env bash
# scripts/utils/claude-snapshot.sh
#
# Capture the current Mac's Claude Code state into dot-files/claude/manifests/
# so it can be replayed on another machine (e.g. BD790i) via claude-sync.sh.
#
# Snapshots:
#   - claude/manifests/marketplaces.json   plugin marketplaces to register
#   - claude/manifests/plugins.txt         one `name@marketplace` per line
#   - claude/manifests/agent-skills.lock.json   sourced ~/.agents/ skills
#   - claude/agent-skills/<name>/SKILL.md  orphan skills tracked as content
#
# Run from anywhere; resolves DOTFILES from env or default location.

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

require() {
    command -v "$1" &>/dev/null || { log_error "missing dependency: $1"; return 1; }
}

require jq || exit 1

mkdir -p "$MANIFEST_DIR" "$AGENT_SKILLS_DIR"

# ----------------------------------------------------------------------
# 1. Marketplaces — copy verbatim minus machine-specific installLocation
# ----------------------------------------------------------------------
snapshot_marketplaces() {
    local src="$CLAUDE_HOME/plugins/known_marketplaces.json"
    if [[ ! -f "$src" ]]; then
        log_warning "no marketplaces file at $src — skipping"
        return 0
    fi
    # Strip installLocation + lastUpdated; portable across machines
    jq 'with_entries(.value |= {source: .source})' "$src" \
        > "$MANIFEST_DIR/marketplaces.json"
    log_success "marketplaces: $(jq 'length' "$MANIFEST_DIR/marketplaces.json") registered"
}

# ----------------------------------------------------------------------
# 2. Plugins — extract name@marketplace, sorted, deduped
# ----------------------------------------------------------------------
snapshot_plugins() {
    local src="$CLAUDE_HOME/plugins/installed_plugins.json"
    if [[ ! -f "$src" ]]; then
        log_warning "no installed_plugins.json — skipping"
        return 0
    fi
    jq -r '.plugins | keys[]' "$src" | sort -u > "$MANIFEST_DIR/plugins.txt"
    log_success "plugins: $(wc -l < "$MANIFEST_DIR/plugins.txt" | tr -d ' ') captured"
}

# ----------------------------------------------------------------------
# 3. Agent skills — sourced (from .skill-lock.json) + orphan SKILL.md
# ----------------------------------------------------------------------
snapshot_agent_skills() {
    local lock="$AGENTS_HOME/.skill-lock.json"
    local skills_dir="$AGENTS_HOME/skills"

    if [[ ! -d "$skills_dir" ]]; then
        log_warning "no $skills_dir — skipping agent skills"
        return 0
    fi

    # 3a. Lockfile (skills with a known source/url)
    if [[ -f "$lock" ]]; then
        jq '.' "$lock" > "$MANIFEST_DIR/agent-skills.lock.json"
        log_success "agent-skills lockfile: $(jq '.skills | length' "$lock") sourced"
    else
        echo '{"version":3,"skills":{},"dismissed":{}}' \
            > "$MANIFEST_DIR/agent-skills.lock.json"
        log_warning "no .skill-lock.json — wrote empty"
    fi

    # 3b. Orphan SKILL.md files — anything in skills_dir not in the lockfile
    local locked
    locked=$(jq -r '.skills | keys[]?' "$MANIFEST_DIR/agent-skills.lock.json" 2>/dev/null || true)

    local copied=0
    for skill_path in "$skills_dir"/*/; do
        [[ -d "$skill_path" ]] || continue
        local name
        name=$(basename "$skill_path")
        # Skip skills covered by the lockfile (those get reinstalled from source)
        if echo "$locked" | grep -qx "$name"; then
            continue
        fi
        local src_skill="$skill_path/SKILL.md"
        [[ -f "$src_skill" ]] || continue
        mkdir -p "$AGENT_SKILLS_DIR/$name"
        cp "$src_skill" "$AGENT_SKILLS_DIR/$name/SKILL.md"
        # Copy any auxiliary files (references, scripts) the skill may use
        find "$skill_path" -mindepth 1 -maxdepth 1 ! -name 'SKILL.md' \
            -exec cp -R {} "$AGENT_SKILLS_DIR/$name/" \; 2>/dev/null || true
        copied=$((copied + 1))
    done
    log_success "orphan SKILL.md files: $copied tracked"

    # 3c. Prune skills from repo that no longer exist on Mac
    if [[ -d "$AGENT_SKILLS_DIR" ]]; then
        for tracked in "$AGENT_SKILLS_DIR"/*/; do
            [[ -d "$tracked" ]] || continue
            local name
            name=$(basename "$tracked")
            if [[ ! -d "$skills_dir/$name" ]]; then
                log_warning "pruning $name (no longer present on Mac)"
                rm -rf "$tracked"
            fi
        done
    fi
}

# ----------------------------------------------------------------------
# 4. Provenance — when, from what machine, against what Claude version
# ----------------------------------------------------------------------
snapshot_provenance() {
    local out="$MANIFEST_DIR/SNAPSHOT.json"
    local claude_ver="unknown"
    command -v claude &>/dev/null && claude_ver=$(claude --version 2>/dev/null || echo unknown)
    cat > "$out" <<EOF
{
  "snapshotAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "hostname": "$(hostname -s)",
  "uname": "$(uname -sm)",
  "claudeVersion": "$claude_ver"
}
EOF
    log_success "provenance written: $out"
}

main() {
    log_info "Snapshotting Claude state → $MANIFEST_DIR"
    snapshot_marketplaces
    snapshot_plugins
    snapshot_agent_skills
    snapshot_provenance
    log_info ""
    log_info "Next: review the diff, then commit:"
    log_info "  git -C \"$DOTFILES\" diff -- claude/manifests claude/agent-skills"
    log_info "  git -C \"$DOTFILES\" add  claude/manifests claude/agent-skills"
}

main "$@"
