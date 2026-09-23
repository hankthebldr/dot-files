#!/usr/bin/env bash
# scripts/utils/worktree.sh — engine for `claw wt` (worktree-per-task).
# bin/claw dispatches: `bash worktree.sh "$@"`. Contract: docs/BRANCHING.md.
#
#   claw wt new <branch>            branch off origin/<base> into .claude/worktrees/<slug>
#   claw wt ls                      every worktree: branch · ahead/behind base · state · path
#   claw wt rm <branch> [--force]   remove the worktree AND the local branch
#   claw wt path <branch>           print the worktree directory  →  cd "$(claw wt path x)"
#
# The deployed tree ($DOTFILES_DIR, ~/.dotfiles) is never checked out, reset or
# pulled here. `new` fetches origin/<base> and branches from that remote-tracking
# ref, so the deployed checkout can be behind and still spawn a current branch.
# <base> is CLAW_REPO_BRANCH (default master) — the same knob claw doctor repo reads.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
# Physical path: ~/.dotfiles is a symlink and git reports real paths, so
# `ls` can print worktrees relative to the deployed tree.
DOTFILES_DIR="$(cd "$DOTFILES_DIR" && pwd -P)"
BASE="${CLAW_REPO_BRANCH:-master}"
WT_ROOT="$DOTFILES_DIR/.claude/worktrees"
if [[ -f "$DOTFILES_DIR/scripts/utils/logger.sh" ]]; then
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/scripts/utils/logger.sh"
else
  log_info(){ printf '  • %s\n' "$*"; }
  log_success(){ printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
  log_warning(){ printf '  ! %s\n' "$*" >&2; }
  log_error(){ printf '  \033[0;31m✗\033[0m %s\n' "$*" >&2; }
fi

g(){ git -C "$DOTFILES_DIR" "$@"; }
_slug(){ printf '%s' "$1" | tr '/' '-'; }

# ── Branch-name policy ───────────────────────────────────────────────────────
# _wt_valid_branch <name> → 0 if `claw wt new` may create it, else 1.
# git's own ref grammar is checked BEFORE this is called (wt_new), so this is
# purely the house policy: which prefixes are legal, whether claude/ session
# branches may be pushed or must stay local, whether a ticket/date slug is
# required. Keep it pure — string tests only, no git calls, no output — so it
# stays unit-testable. Documented in docs/BRANCHING.md "Branch names".
#
# TODO(henry): replace the placeholder body with the house rule.
# Placeholder = the minimum structural shape: exactly one '/', both halves
# non-empty. Everything git accepts beyond that currently passes.
_wt_valid_branch(){
  local name="$1"
  [[ "$name" == ?*/?* && "$name" != */*/* ]]
}

# ── Internals ────────────────────────────────────────────────────────────────
# Main (deployed) worktree = first block of the porcelain listing.
_main_wt(){ g worktree list --porcelain | awk 'NR==1{print substr($0,10); exit}'; }

# Worktree dir for a branch, from git's own registry (so it also finds
# worktrees added by hand or by Claude Code, wherever they live).
_wt_dir_of(){
  g worktree list --porcelain | awk -v b="refs/heads/$1" '
    /^worktree /{p=substr($0,10)}
    /^branch /  {if ($2==b) {print p; exit}}'
}

# origin/<base> when known, else local <base> (a never-fetched clone).
_base_ref(){
  if g show-ref --verify --quiet "refs/remotes/origin/$BASE"; then printf 'origin/%s' "$BASE"
  else printf '%s' "$BASE"; fi
}

# Best-effort refresh of origin/<base> only. Offline → non-zero, caller decides.
_fetch_base(){
  local spec="+refs/heads/$BASE:refs/remotes/origin/$BASE"
  if command -v timeout >/dev/null 2>&1; then
    timeout 30 git -C "$DOTFILES_DIR" fetch -q origin "$spec" 2>/dev/null
  else
    git -C "$DOTFILES_DIR" fetch -q origin "$spec" 2>/dev/null
  fi
}

# ── Subcommands ──────────────────────────────────────────────────────────────
wt_new(){
  local br="${1:-}"
  [[ -n "$br" ]] || { log_error "usage: claw wt new <branch>"; return 2; }
  git check-ref-format --branch "$br" >/dev/null 2>&1 \
    || { log_error "invalid branch name: '$br' (git refuses it)"; return 2; }
  _wt_valid_branch "$br" \
    || { log_error "invalid branch name: '$br' — house rule is <prefix>/<slug> (docs/BRANCHING.md)"; return 2; }
  if g show-ref --verify --quiet "refs/heads/$br" || g show-ref --verify --quiet "refs/remotes/origin/$br"; then
    log_error "branch exists: $br  (claw wt path $br · claw wt ls)"; return 1
  fi
  local dir; dir="$WT_ROOT/$(_slug "$br")"
  [[ -e "$dir" ]] && { log_error "directory exists: $dir"; return 1; }

  if ! _fetch_base; then
    log_warning "fetch failed (offline?) — branching from last-known $(_base_ref), which may be behind"
  fi
  local start; start="$(_base_ref)"
  mkdir -p "$WT_ROOT"
  g worktree add -q --no-track -b "$br" "$dir" "$start"
  log_success "worktree $br  ←  $start @ $(g rev-parse --short "$start")"
  printf '  cd "%s"\n' "$dir"
}

wt_path(){
  local br="${1:-}"
  [[ -n "$br" ]] || { log_error "usage: claw wt path <branch>"; return 2; }
  local d; d="$(_wt_dir_of "$br")"
  [[ -n "$d" ]] || { log_error "no worktree for branch: $br"; return 1; }
  printf '%s\n' "$d"
}

_ls_row(){
  local p="$1" b="$2" main="$3" ref="$4" ahead="-" behind="-" st rel
  [[ -n "$p" ]] || return 0
  if [[ -n "$b" && "$b" != "(detached)" && "$b" != "$BASE" ]]; then
    ahead="+$(g rev-list --count "$ref..$b" 2>/dev/null || echo 0)"
    behind="-$(g rev-list --count "$b..$ref" 2>/dev/null || echo 0)"
  fi
  if [[ -n "$(git -C "$p" status --porcelain -uno 2>/dev/null)" ]]; then st="dirty"; else st="clean"; fi
  if [[ "$p" == "$main" ]]; then rel=". (deployed)"; else rel="${p#"$DOTFILES_DIR"/}"; fi
  printf '  %-36s %-6s %-7s %-6s %s\n' "${b:-(detached)}" "$ahead" "$behind" "$st" "$rel"
}

wt_ls(){
  local main ref p="" b="" line
  main="$(_main_wt)"; ref="$(_base_ref)"
  printf '  %-36s %-6s %-7s %-6s %s\n' "BRANCH (vs $ref)" AHEAD BEHIND STATE PATH
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) p="${line#worktree }"; b="" ;;
      "branch "*)   b="${line#branch refs/heads/}" ;;
      detached)     b="(detached)" ;;
      "")           _ls_row "$p" "$b" "$main" "$ref"; p="" ;;
    esac
  done < <(g worktree list --porcelain; echo)
}

wt_rm(){
  local br="${1:-}" force=0 a d main ref
  [[ -n "$br" ]] || { log_error "usage: claw wt rm <branch> [--force]"; return 2; }
  shift
  for a in "$@"; do [[ "$a" == "--force" || "$a" == "-f" ]] && force=1; done
  [[ "$br" == "$BASE" ]] && { log_error "refusing: $BASE is the deployed branch (docs/BRANCHING.md)"; return 1; }
  d="$(_wt_dir_of "$br")"; main="$(_main_wt)"
  [[ -n "$d" && "$d" == "$main" ]] && { log_error "refusing: $br is checked out in the deployed tree $main"; return 1; }

  # Pre-flight BEFORE touching anything, so a refusal leaves the tree intact.
  if (( ! force )); then
    if [[ -n "$d" && -n "$(git -C "$d" status --porcelain 2>/dev/null)" ]]; then
      log_error "worktree is dirty: $d — commit it, or: claw wt rm $br --force"; return 1
    fi
    if g show-ref --verify --quiet "refs/heads/$br"; then
      _fetch_base || true
      ref="$(_base_ref)"
      if ! g merge-base --is-ancestor "$br" "$ref" 2>/dev/null; then
        log_error "branch $br is not merged into $ref — merge it first, or: claw wt rm $br --force"; return 1
      fi
    fi
  fi

  if [[ -n "$d" ]]; then
    if (( force )); then g worktree remove --force "$d"; else g worktree remove "$d"; fi
    log_success "removed worktree $d"
  else
    log_info "no worktree for $br (branch only)"
  fi
  if g show-ref --verify --quiet "refs/heads/$br"; then
    if (( force )); then g branch -q -D "$br"; else g branch -q -d "$br"; fi
    log_success "deleted branch $br"
  fi
  g worktree prune
}

wt_help(){
  cat <<HELP
usage: claw wt <new|ls|rm|path> …
  claw wt new <branch>            branch off origin/$BASE into .claude/worktrees/<slug>
  claw wt ls                      every worktree: branch · ahead/behind · state · path
  claw wt rm <branch> [--force]   remove the worktree and the local branch (refuses dirty/unmerged)
  claw wt path <branch>           print the worktree dir  →  cd "\$(claw wt path <branch>)"
contract: docs/BRANCHING.md · guard: claw doctor repo
HELP
}

main(){
  local sub="${1:-ls}"; shift || true
  case "$sub" in
    new|add)        wt_new "$@" ;;
    ls|list)        wt_ls ;;
    rm|remove)      wt_rm "$@" ;;
    path|dir)       wt_path "$@" ;;
    -h|--help|help) wt_help ;;
    *) log_error "unknown: claw wt $sub"; wt_help >&2; return 1 ;;
  esac
}
main "$@"
