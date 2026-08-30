#!/usr/bin/env bash
# ============================================
# OPEN CLAW — Integrity / Tamper-Check Tool
# ============================================
# Builds and verifies a SHA-256 manifest of every shell script, profile,
# config file, and TUI helper in this dotfiles repo. Lets a user prove that
# the install they ran matches the upstream repo and that nothing has been
# silently swapped under them (malicious profile, replaced installer, etc).
#
# Manifest format (one record per line, NUL-safe ordering):
#   <sha256>  <relative/path/from/repo/root>
#
# Stored at: config/integrity/manifest.sha256
# Ignore rules: config/integrity/.integrityignore  (gitignore-style globs)
#
# Subcommands:
#   generate   write a fresh manifest (run after pulling/editing the repo)
#   verify     compare on-disk files to the manifest; exit 1 on mismatch
#   audit      verify + report missing/extra/changed files in a styled table
#   show       print the manifest path + summary stats
#   ignore     print the active ignore patterns
#
# Exit codes:
#   0  manifest matches (or generated successfully)
#   1  drift detected — extra, missing, or changed files
#   2  manifest file missing / unreadable
#   3  dependency missing (sha256sum / shasum)

set -e

# pwd -P: resolve to the PHYSICAL path. When invoked via the ~/.dotfiles
# symlink, the logical path makes `find` see a symlink argument (which it does
# not follow) → 0 files hashed → an empty manifest that verify vacuously
# passes. That silently disabled tamper detection.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
MANIFEST_DIR="$REPO_ROOT/config/integrity"
MANIFEST_FILE="$MANIFEST_DIR/manifest.sha256"
IGNORE_FILE="$MANIFEST_DIR/.integrityignore"

# Source styling — preserves the GitHub-dark theme used across claw scripts.
# tui-style.sh exports c_* colors and tui_section / tui_footer helpers.
source "$SCRIPT_DIR/tui-style.sh"

# ============================================
# SHA256 PORTABILITY
# ============================================
# macOS ships `shasum -a 256`; Linux ships `sha256sum`. Wrap both so the
# rest of the script doesn't care which platform it's on.
_sha256() {
    if command -v sha256sum &>/dev/null; then
        sha256sum "$1" | awk '{print $1}'
    elif command -v shasum &>/dev/null; then
        shasum -a 256 "$1" | awk '{print $1}'
    else
        echo ""
        return 3
    fi
}

_ensure_hasher() {
    if ! command -v sha256sum &>/dev/null && ! command -v shasum &>/dev/null; then
        printf "  ${c_red}✗${c_reset} no sha256 binary found (need sha256sum or shasum)\n" >&2
        exit 3
    fi
}

# ============================================
# IGNORE RULES
# ============================================
# The default ignore set covers: VCS internals, generated/transient state,
# user secrets, backups, the manifest itself (chicken-and-egg), and binary
# artifacts that legitimately drift between installs (fonts, archives).
_default_ignore_patterns=(
    '.git/'
    'node_modules/'
    '__pycache__/'
    '.venv/'
    'venv/'
    'env/'
    '.cache/'
    'dist/'
    'build/'
    '*.log'
    '*.tmp'
    '*.bak'
    '*.swp'
    '.DS_Store'
    '.env'
    '.env.local'
    'config/integrity/manifest.sha256'
    'config/integrity/manifest.sha256.prev'
    'browser-profiles/'
    '.remember/'
    '*.sqlite'
    '*.db'
    '*.pem'
    '*.key'
    '*.crt'
    '*.tar.gz'
    '*.tar.xz'
    '*.zip'
)

_ensure_ignore_file() {
    mkdir -p "$MANIFEST_DIR"
    if [[ ! -f "$IGNORE_FILE" ]]; then
        {
            echo "# Open Claw integrity-check ignore patterns (gitignore-style globs)."
            echo "# One pattern per line. Lines starting with # are comments."
            echo "# Patterns are matched against the file path relative to the repo root."
            echo ""
            for p in "${_default_ignore_patterns[@]}"; do
                echo "$p"
            done
        } > "$IGNORE_FILE"
    fi
}

# Read patterns from .integrityignore, stripping comments and blanks.
_read_ignore_patterns() {
    _ensure_ignore_file
    grep -Ev '^\s*(#|$)' "$IGNORE_FILE" 2>/dev/null || true
}

# ── Git-ignored files are never repo CONTENT ────────────────────────────────
# The manifest is COMMITTED, so it must describe the repo's own files only.
# Hashing git-ignored paths (vendored skills, __pycache__, machine-local state)
# made a tracked file machine-DEPENDENT: regenerating on another box silently
# dropped those rows, and `verify` then cried EXTRA for every such file the
# other machine happened to have. Skipping what git already declares "not
# content" makes the manifest deterministic everywhere — and self-maintaining,
# since a new .gitignore entry needs no matching .integrityignore edit.
#
# One `git ls-files` call builds the set, newline-delimited and newline-BOUNDED
# so membership is an exact whole-line match done with bash pattern matching —
# no fork per file (bash 3.2 has no associative arrays, and _is_ignored runs
# once per file in both generate and verify, which repo-sync now calls after
# every pull). "$rel" is quoted inside the pattern, so a filename containing
# glob metacharacters is matched literally. A tarball install with no git, or
# no .git dir, degrades to the .integrityignore patterns alone.
_GIT_IGNORED=""
_GIT_IGNORED_LOADED=""
_load_git_ignored() {
    [[ -n "$_GIT_IGNORED_LOADED" ]] && return 0
    _GIT_IGNORED_LOADED=1
    command -v git &>/dev/null || return 0
    git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null || return 0
    local listed
    listed="$(git -C "$REPO_ROOT" ls-files --others --ignored --exclude-standard 2>/dev/null || true)"
    # Bound with leading/trailing newlines so *\n<rel>\n* can only match a
    # whole line (the equivalent of grep -qxF, without the process).
    [[ -n "$listed" ]] && _GIT_IGNORED=$'\n'"$listed"$'\n'
    return 0
}

# Should this relative path be ignored? Matches against either a literal
# directory prefix (pattern ending in /) or a glob via `case` matching.
_is_ignored() {
    local rel="$1"
    local pat
    # Git's own ignore rules first — cheapest and the broadest correct signal.
    _load_git_ignored
    if [[ -n "$_GIT_IGNORED" && "$_GIT_IGNORED" == *$'\n'"$rel"$'\n'* ]]; then
        return 0
    fi
    while IFS= read -r pat; do
        [[ -z "$pat" ]] && continue
        if [[ "$pat" == */ ]]; then
            # Directory prefix — match if relative path starts with it.
            [[ "$rel" == "$pat"* ]] && return 0
            [[ "$rel" == */"$pat"* ]] && return 0
        else
            # Glob — basename or full-path match.
            # shellcheck disable=SC2053
            [[ "$(basename "$rel")" == $pat ]] && return 0
            # shellcheck disable=SC2053
            [[ "$rel" == $pat ]] && return 0
            # shellcheck disable=SC2053
            [[ "$rel" == */$pat ]] && return 0
        fi
    done < <(_read_ignore_patterns)
    return 1
}

# ============================================
# MANIFEST GENERATION
# ============================================
# Walks the repo, hashes every file that isn't ignored, and writes a
# sorted manifest. Sort order is critical so reruns produce identical
# output (good for git diffs) and verify can do line-by-line comparison.
cmd_generate() {
    _ensure_hasher
    _ensure_ignore_file

    tui_section "Generating integrity manifest"
    printf "  ${c_dim}repo: %s${c_reset}\n" "$REPO_ROOT"
    printf "  ${c_dim}out:  %s${c_reset}\n\n" "$MANIFEST_FILE"

    # Preserve the previous manifest so a user can diff after a rebuild.
    if [[ -f "$MANIFEST_FILE" ]]; then
        cp "$MANIFEST_FILE" "$MANIFEST_FILE.prev"
    fi

    local tmp
    tmp="$(mktemp)"
    local count=0

    # find -print0 + while read -d '' handles paths with spaces and unicode.
    while IFS= read -r -d '' path; do
        local rel="${path#$REPO_ROOT/}"
        # Skip ignored, non-regular, and unreadable files.
        _is_ignored "$rel" && continue
        [[ ! -f "$path" || ! -r "$path" ]] && continue

        local hash
        hash="$(_sha256 "$path")"
        [[ -z "$hash" ]] && continue
        printf '%s  %s\n' "$hash" "$rel" >> "$tmp"
        ((count++)) || true
    done < <(find "$REPO_ROOT" -type f -print0)

    # LC_ALL=C → byte-wise sort, identical on macOS and Linux.
    LC_ALL=C sort "$tmp" > "$MANIFEST_FILE"
    rm -f "$tmp"

    # Header is a comment block at the top, separated from the records by a
    # blank-line-prefixed sort. We use a trick: write header to a second tmp,
    # then concatenate. Keeping the records sorted alone lets `comm` and
    # `diff` work cleanly without header alignment issues.
    local hash_of_manifest
    hash_of_manifest="$(_sha256 "$MANIFEST_FILE")"

    printf "  ${c_green}✓${c_reset} hashed ${c_white}${c_bold}%d${c_reset} files\n" "$count"
    printf "  ${c_green}✓${c_reset} manifest sha256: ${c_dim}%s${c_reset}\n" "$hash_of_manifest"
    printf "  ${c_dim}previous saved to manifest.sha256.prev (if any)${c_reset}\n"
    tui_footer "✓ integrity manifest written"
}

# ============================================
# VERIFY
# ============================================
# Walks current files the same way and diffs against the manifest. Three
# kinds of drift are reported:
#   - CHANGED: file present in both but hash differs (tamper or local edit)
#   - MISSING: in manifest, not on disk (deleted, partial install)
#   - EXTRA:   on disk, not in manifest (added without regenerating)
cmd_verify() {
    _ensure_hasher
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        printf "  ${c_red}✗${c_reset} no manifest at %s\n" "$MANIFEST_FILE" >&2
        printf "  ${c_dim}run: claw integrity generate${c_reset}\n" >&2
        exit 2
    fi

    tui_section "Verifying integrity"
    printf "  ${c_dim}manifest: %s${c_reset}\n\n" "$MANIFEST_FILE"

    # Build the on-disk manifest in memory (same shape).
    local current
    current="$(mktemp)"
    while IFS= read -r -d '' path; do
        local rel="${path#$REPO_ROOT/}"
        _is_ignored "$rel" && continue
        [[ ! -f "$path" || ! -r "$path" ]] && continue
        local hash
        hash="$(_sha256 "$path")"
        [[ -z "$hash" ]] && continue
        printf '%s  %s\n' "$hash" "$rel" >> "$current"
    done < <(find "$REPO_ROOT" -type f -print0)
    LC_ALL=C sort -o "$current" "$current"

    # Three-way diff: extract `path` columns into sets, then compare hashes
    # for the intersection. awk pulls col2..end so paths with spaces survive.
    local manifest_paths current_paths
    manifest_paths="$(mktemp)"
    current_paths="$(mktemp)"
    awk '{$1=""; sub(/^  /,""); print}' "$MANIFEST_FILE" | LC_ALL=C sort > "$manifest_paths"
    awk '{$1=""; sub(/^  /,""); print}' "$current"        | LC_ALL=C sort > "$current_paths"

    # comm does its OWN collation comparison and rejects input unless it's
    # sorted under the SAME locale. The path lists above are byte-sorted
    # (LC_ALL=C), so comm must run under LC_ALL=C too or it errors with
    # "input is not in sorted order" and silently produces wrong results.
    local missing extra
    missing="$(LC_ALL=C comm -23 "$manifest_paths" "$current_paths")"   # in manifest, not on disk
    extra="$(  LC_ALL=C comm -13 "$manifest_paths" "$current_paths")"   # on disk, not in manifest

    # Changed = paths in both with different hashes. Cheap implementation:
    # diff -u sorted manifests, keep lines starting with - that aren't only
    # in missing.
    local changed
    changed="$(diff "$MANIFEST_FILE" "$current" 2>/dev/null \
        | awk '/^< /{print substr($0,3)} /^> /{print substr($0,3)}' \
        | awk '{$1=""; sub(/^  /,""); print}' \
        | LC_ALL=C sort -u \
        | LC_ALL=C comm -12 - "$manifest_paths" \
        | LC_ALL=C comm -12 - "$current_paths")" || true
    # `|| true` is load-bearing: this pipeline exits non-zero whenever there IS
    # drift, and `set -e` (line 29) would kill cmd_verify right here — before a
    # single CHANGED/MISSING/EXTRA line is printed. The net effect was a tamper
    # detector that exited 1 and reported nothing exactly when it mattered.

    local m_count e_count c_count
    m_count=$(printf '%s\n' "$missing" | grep -c '[^[:space:]]' || true)
    e_count=$(printf '%s\n' "$extra"   | grep -c '[^[:space:]]' || true)
    c_count=$(printf '%s\n' "$changed" | grep -c '[^[:space:]]' || true)

    if [[ -n "$changed" ]]; then
        printf "  ${c_red}${c_bold}CHANGED${c_reset}  ${c_dim}(content differs from manifest)${c_reset}\n"
        printf '%s\n' "$changed" | sed "s|^|    ${c_red}~${c_reset} |" | sed "s|$|${c_reset}|"
        echo ""
    fi
    if [[ -n "$missing" ]]; then
        printf "  ${c_orange}${c_bold}MISSING${c_reset}  ${c_dim}(in manifest, not on disk)${c_reset}\n"
        printf '%s\n' "$missing" | sed "s|^|    ${c_orange}-${c_reset} |"
        echo ""
    fi
    if [[ -n "$extra" ]]; then
        printf "  ${c_cyan}${c_bold}EXTRA${c_reset}    ${c_dim}(on disk, not in manifest)${c_reset}\n"
        printf '%s\n' "$extra" | sed "s|^|    ${c_cyan}+${c_reset} |"
        echo ""
    fi

    rm -f "$current" "$manifest_paths" "$current_paths"

    if (( m_count == 0 && e_count == 0 && c_count == 0 )); then
        tui_footer "✓ integrity OK — no drift detected"
        return 0
    fi

    printf "  ${c_dim}summary: ${c_red}%d changed${c_dim} · ${c_orange}%d missing${c_dim} · ${c_cyan}%d extra${c_reset}\n" \
        "$c_count" "$m_count" "$e_count"
    printf "  ${c_dim}if these are intentional edits, run: claw integrity generate${c_reset}\n"
    echo ""
    return 1
}

# ============================================
# AUDIT — verify + provenance details
# ============================================
cmd_audit() {
    tui_header "OPEN CLAW · Integrity Audit" "tamper-check + install verification"

    # Provenance: git commit, manifest age, hasher version.
    tui_section "Provenance"
    if command -v git &>/dev/null && [[ -d "$REPO_ROOT/.git" ]]; then
        local commit branch dirty
        commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || echo detached)"
        dirty=""
        if ! git -C "$REPO_ROOT" diff --quiet 2>/dev/null \
           || ! git -C "$REPO_ROOT" diff --cached --quiet 2>/dev/null; then
            dirty=" ${c_orange}(working tree dirty)${c_reset}"
        fi
        printf "  ${c_dim}commit:${c_reset}   ${c_white}%s${c_reset} on ${c_cyan}%s${c_reset}%s\n" \
            "$commit" "$branch" "$dirty"
    else
        printf "  ${c_dim}commit:${c_reset}   ${c_dim}(not a git checkout)${c_reset}\n"
    fi

    if [[ -f "$MANIFEST_FILE" ]]; then
        local mhash mage mlines
        mhash="$(_sha256 "$MANIFEST_FILE")"
        # Portable mtime — `stat` flags differ between BSD and GNU.
        if stat -c '%Y' "$MANIFEST_FILE" &>/dev/null; then
            mage="$(stat -c '%Y' "$MANIFEST_FILE")"
        else
            mage="$(stat -f '%m' "$MANIFEST_FILE" 2>/dev/null || echo 0)"
        fi
        mlines="$(wc -l < "$MANIFEST_FILE" | tr -d ' ')"
        printf "  ${c_dim}manifest:${c_reset} ${c_white}%d${c_reset} files · sha256 ${c_dim}%s${c_reset}\n" \
            "$mlines" "${mhash:0:16}…"
        # Human-readable age.
        local now diff days
        now=$(date +%s)
        diff=$(( now - mage ))
        days=$(( diff / 86400 ))
        printf "  ${c_dim}age:${c_reset}      %d days since last regenerate\n" "$days"
    else
        printf "  ${c_red}manifest missing${c_reset} — run: claw integrity generate\n"
    fi
    echo ""

    # Run verify and surface its result. Don't `exit` on failure so the
    # caller can see the styled footer + next-steps hint.
    set +e
    cmd_verify
    local rc=$?
    set -e
    return $rc
}

# ============================================
# SHOW / IGNORE
# ============================================
cmd_show() {
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        printf "  ${c_red}✗${c_reset} no manifest at %s\n" "$MANIFEST_FILE"
        printf "  ${c_dim}run: claw integrity generate${c_reset}\n"
        return 2
    fi
    local lines hash
    lines="$(wc -l < "$MANIFEST_FILE" | tr -d ' ')"
    hash="$(_sha256 "$MANIFEST_FILE")"
    printf "\n  ${c_purple}${c_bold}integrity manifest${c_reset}\n"
    printf "  ${c_dim}path:    %s${c_reset}\n" "$MANIFEST_FILE"
    printf "  ${c_dim}entries: %s${c_reset}\n" "$lines"
    printf "  ${c_dim}sha256:  %s${c_reset}\n\n" "$hash"
}

cmd_ignore() {
    _ensure_ignore_file
    printf "\n  ${c_purple}${c_bold}active ignore patterns${c_reset}  ${c_dim}(%s)${c_reset}\n\n" "$IGNORE_FILE"
    _read_ignore_patterns | sed "s|^|    ${c_dim}·${c_reset} |"
    echo ""
}

# ============================================
# DISPATCH
# ============================================
cmd_help() {
    cat <<EOF

  ${c_purple}${c_bold}claw integrity${c_reset} — ${c_dim}tamper-check + install verification${c_reset}

  ${c_white}claw integrity generate${c_reset}   ${c_dim}write a fresh SHA-256 manifest of the repo${c_reset}
  ${c_white}claw integrity verify${c_reset}     ${c_dim}check on-disk files against the manifest${c_reset}
  ${c_white}claw integrity audit${c_reset}      ${c_dim}verify + provenance + drift breakdown${c_reset}
  ${c_white}claw integrity show${c_reset}       ${c_dim}print manifest path + summary stats${c_reset}
  ${c_white}claw integrity ignore${c_reset}     ${c_dim}print the active ignore patterns${c_reset}

  ${c_dim}Manifest: $MANIFEST_FILE${c_reset}
  ${c_dim}Ignore:   $IGNORE_FILE${c_reset}
EOF
}

case "${1:-help}" in
    generate|gen|new)   cmd_generate ;;
    verify|check)       cmd_verify ;;
    audit|status)       cmd_audit ;;
    show|info)          cmd_show ;;
    ignore|patterns)    cmd_ignore ;;
    help|-h|--help|"")  cmd_help ;;
    *)
        printf "  ${c_red}✗${c_reset} unknown subcommand: %s\n" "$1" >&2
        cmd_help >&2
        exit 1
        ;;
esac
