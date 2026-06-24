#!/usr/bin/env bash
# scripts/utils/harness.sh — engine for `claw harness`.
# bin/claw cmd_harness is a thin dispatcher: `bash harness.sh "$@"`.
# Subcommands: new <kind> <name> | list [--all] [--fzf] | sync [--dry-run]
#            | deploy [--dry-run] | path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
HARNESS="$DOTFILES_DIR/claude/harness"
TEMPLATES="$HARNESS/_templates"
CLAUDE_DST="${CLAUDE_HOME:-$HOME/.claude}"

if [[ -f "$DOTFILES_DIR/scripts/utils/logger.sh" ]]; then
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/scripts/utils/logger.sh"
else
  log_info(){ printf '  • %s\n' "$*"; }
  log_success(){ printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
  log_warning(){ printf '  ! %s\n' "$*" >&2; }
  log_error(){ printf '  \033[0;31m✗\033[0m %s\n' "$*" >&2; }
fi

_valid_name(){ [[ "$1" =~ ^[a-zA-Z0-9._-]+$ ]]; }

# _scaffold_file <template> <dest> <name> — copy a template, substitute __NAME__.
_scaffold_file(){
  local tpl="$1" dest="$2" name="$3"
  [[ -f "$tpl" ]] || { log_error "template missing: $tpl"; return 1; }
  [[ -e "$dest" ]] && { log_error "already exists: $dest"; return 1; }
  mkdir -p "$(dirname "$dest")"
  sed "s/__NAME__/$name/g" "$tpl" > "$dest"
}

harness_new(){
  local kind name
  if [[ $# -eq 1 ]]; then kind="skill"; name="$1"
  elif [[ $# -ge 2 ]]; then kind="$1"; name="$2"
  else log_error "usage: claw harness new [skill|command|agent|plugin] <name>"; return 1; fi
  _valid_name "$name" || { log_error "invalid name: '$name' (use [a-zA-Z0-9._-])"; return 1; }
  case "$kind" in
    skill)
      [[ -e "$HARNESS/skills/$name" ]] && { log_error "already exists: $HARNESS/skills/$name"; return 1; }
      _scaffold_file "$TEMPLATES/SKILL.md" "$HARNESS/skills/$name/SKILL.md" "$name" || return 1
      log_success "scaffolded skill: claude/harness/skills/$name/SKILL.md" ;;
    command)
      _scaffold_file "$TEMPLATES/command.md" "$HARNESS/commands/$name.md" "$name" || return 1
      log_success "scaffolded command: claude/harness/commands/$name.md" ;;
    agent)
      _scaffold_file "$TEMPLATES/agent.md" "$HARNESS/agents/$name.md" "$name" || return 1
      log_success "scaffolded agent: claude/harness/agents/$name.md" ;;
    plugin)
      [[ -e "$HARNESS/plugins/$name" ]] && { log_error "already exists: $HARNESS/plugins/$name"; return 1; }
      cp -R "$TEMPLATES/plugin" "$HARNESS/plugins/$name"
      find "$HARNESS/plugins/$name" -type f -exec sed -i.bak "s/__NAME__/$name/g" {} \; -exec rm -f {}.bak \;
      log_success "scaffolded plugin: claude/harness/plugins/$name/ (register manually)" ;;
    *)
      log_error "unknown kind: '$kind' (skill|command|agent|plugin)"; return 1 ;;
  esac
  log_info "edit it, then: claw harness deploy"
}

# _desc <file> — extract the YAML frontmatter `description:` as one trimmed line.
# Handles inline (`description: text`) and folded (`description: >-` then indented).
_desc(){
  awk '
    /^---[[:space:]]*$/ { fm++; if (fm==2) exit; next }
    fm==1 {
      if ($0 ~ /^description:/) {
        sub(/^description:[[:space:]]*/, "")
        if ($0 ~ /^[>|]-?[[:space:]]*$/) { folded=1; next }   # folder marker only
        print; exit
      }
      if (folded) {
        if ($0 ~ /^[A-Za-z0-9_-]+:/) exit                     # next key ends it
        sub(/^[[:space:]]+/, ""); printf "%s ", $0
      }
    }
  ' "$1" 2>/dev/null | tr -s ' ' | sed 's/[[:space:]]*$//' | cut -c1-72
}

# _emit_item <kind> <name> <descfile> — print one formatted row.
_emit_item(){
  local kind="$1" name="$2" df="$3" mark="○"
  [[ -e "$CLAUDE_DST/$kind/$name" || -e "$CLAUDE_DST/$kind/${name%.md}" ]] && mark="✓"
  local d; d="$(_desc "$df" 2>/dev/null)"; [[ -z "$d" ]] && d="(no description)"
  printf "    %s %-22s %s\n" "$mark" "$name" "$d"
}

harness_list(){
  local all=0 use_fzf=0 a
  for a in "$@"; do case "$a" in --all) all=1 ;; --fzf) use_fzf=1 ;; esac; done

  _walk(){  # emits "kind\tname\tdescfile" rows
    local kind dir e name df
    for kind in skills commands agents plugins; do
      dir="$HARNESS/$kind"; [[ -d "$dir" ]] || continue
      while IFS= read -r e; do
        name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
        if [[ -d "$e" ]]; then df="$e/SKILL.md"; else df="$e"; fi
        printf '%s\t%s\t%s\n' "$kind" "$name" "$df"
      done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
    done
    if [[ $all -eq 1 ]]; then
      for kind in skills agent-skills; do
        dir="$DOTFILES_DIR/claude/$kind"; [[ -d "$dir" ]] || continue
        while IFS= read -r e; do
          name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
          printf '%s\t%s\t%s\n' "repo:$kind" "$name" "$e/SKILL.md"
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
      done
    fi
  }

  if [[ $use_fzf -eq 1 ]] && command -v fzf >/dev/null 2>&1; then
    local fzf_opts=(); command -v claw_theme_fzf >/dev/null 2>&1 && IFS=' ' read -r -a fzf_opts <<< "$(claw_theme_fzf 2>/dev/null)"
    _walk | awk -F'\t' '{printf "%s\t%s\t%s\n",$1,$2,$3}' \
      | fzf --with-nth=1,2 --delimiter='\t' "${fzf_opts[@]}" \
            --preview 'cat {3} 2>/dev/null' --preview-window=right:60%
    return 0
  fi

  [[ $use_fzf -eq 1 ]] && ! command -v fzf >/dev/null 2>&1 && log_warning "fzf not on PATH — showing plain list"

  printf "\n  Custom agentic harness (%s)\n\n" "$HARNESS"
  local last="" kind name df
  while IFS=$'\t' read -r kind name df; do
    [[ "$kind" != "$last" ]] && { printf "  %s\n" "$kind"; last="$kind"; }
    _emit_item "${kind#repo:}" "$name" "$df"
  done < <(_walk)
}

harness_deploy(){ bash "$DOTFILES_DIR/scripts/setup/link-claude.sh" "$@"; }
harness_path(){ echo "$HARNESS"; }

harness_sync(){
  local dry=0; [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && dry=1
  git -C "$DOTFILES_DIR" rev-parse --git-dir >/dev/null 2>&1 \
    || { log_error "$DOTFILES_DIR is not a git repo"; return 1; }

  if [[ $dry -eq 1 ]]; then
    log_info "fetching origin…"
    git -C "$DOTFILES_DIR" fetch --quiet 2>/dev/null || log_warning "fetch failed (offline?)"
    if git -C "$DOTFILES_DIR" rev-parse '@{u}' >/dev/null 2>&1; then
      local n; n="$(git -C "$DOTFILES_DIR" rev-list --count HEAD..'@{u}' 2>/dev/null || echo 0)"
      log_info "$n commit(s) incoming:"
      git -C "$DOTFILES_DIR" log --oneline HEAD..'@{u}' 2>/dev/null || true
    else
      log_warning "no upstream tracking branch — nothing to pull"
    fi
    log_info "deploy preview:"
    bash "$DOTFILES_DIR/scripts/setup/link-claude.sh" --dry-run
    return 0
  fi

  log_info "pulling (ff-only)…"
  if ! git -C "$DOTFILES_DIR" pull --ff-only; then
    log_error "can't fast-forward (branch diverged). Reconcile manually, then re-run."
    return 1
  fi
  bash "$DOTFILES_DIR/scripts/setup/link-claude.sh"
  log_success "harness synced + deployed"
}

main(){
  local sub="${1:-list}"; shift || true
  case "$sub" in
    new)          harness_new "$@" ;;
    sync)         harness_sync "$@" ;;
    list|ls)      harness_list "$@" ;;
    deploy|link)  harness_deploy "$@" ;;
    path)         harness_path ;;
    -h|--help|help) printf "usage: claw harness <new|list|sync|deploy|path>\n" ;;
    *) log_error "unknown: claw harness $sub"
       printf "  subcommands: new <kind> <name> · list · sync · deploy · path\n"; return 1 ;;
  esac
}
main "$@"
