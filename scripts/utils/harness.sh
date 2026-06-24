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

# Basic listing — names + deploy state. Enriched in a later task.
harness_list(){
  printf "\n  Custom agentic harness (%s)\n\n" "$HARNESS"
  local kind dir e name found
  for kind in skills commands agents plugins; do
    dir="$HARNESS/$kind"; printf "  %s\n" "$kind"; found=0
    if [[ -d "$dir" ]]; then
      while IFS= read -r e; do
        name="$(basename "$e")"; [[ "$name" == _* || "$name" == .* ]] && continue
        found=1
        if [[ -e "$CLAUDE_DST/$kind/$name" || -e "$CLAUDE_DST/$kind/${name%.md}" ]]; then
          printf "    ✓ %s\n" "$name"
        else
          printf "    ○ %s\n" "$name"
        fi
      done < <(find "$dir" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
    fi
    [[ $found -eq 0 ]] && printf "    (none yet)\n"
  done
}

harness_deploy(){ bash "$DOTFILES_DIR/scripts/setup/link-claude.sh" "$@"; }
harness_path(){ echo "$HARNESS"; }

main(){
  local sub="${1:-list}"; shift || true
  case "$sub" in
    new)          harness_new "$@" ;;
    list|ls)      harness_list "$@" ;;
    deploy|link)  harness_deploy "$@" ;;
    path)         harness_path ;;
    -h|--help|help) printf "usage: claw harness <new|list|sync|deploy|path>\n" ;;
    *) log_error "unknown: claw harness $sub"
       printf "  subcommands: new <kind> <name> · list · sync · deploy · path\n"; return 1 ;;
  esac
}
main "$@"
