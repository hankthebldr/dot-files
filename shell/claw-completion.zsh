# shell/claw-completion.zsh — zsh tab completion for the `claw` dispatcher.
# Sourced from ~/.zshrc after claw-fn.zsh (compinit has already run via OMZ).
#
# Audit F-15: this file used to carry its own hand-maintained 41-entry copy of
# the dispatcher, which had drifted to 39 real arms and was missing `harness`
# — Henry's most-used verb. The top-level word list is now GENERATED from
# scripts/utils/registry.sh (the same meta.zsh + actions.tsv the palette and
# `claw help` read), so a new verb is one actions.tsv row and nothing else.
#
# Cost: one bash fork on the FIRST Tab of the shell, cached in a zsh global
# for the rest of the session. Never on the login path.

typeset -ga _claw_top_cache

# Static last resort — only used when registry.sh is unreadable (mid-bootstrap,
# a stubbed DOTFILES_DIR). Deliberately tiny: it is not a second taxonomy.
typeset -ga _claw_top_fallback
_claw_top_fallback=(
  'help:show help'
  'doctor:environment health check'
  'update:phased update — repo sync then packages'
  'load:load a workflow profile'
  'registry:rows | palette | check'
)

_claw_top_words() {
  (( ${#_claw_top_cache} )) && return 0
  local dotfiles="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local reg="$dotfiles/scripts/utils/registry.sh"
  if [[ -r $reg ]]; then
    _claw_top_cache=("${(@f)$(DOTFILES_DIR=$dotfiles command bash $reg completion 2>/dev/null)}")
    # `registry.sh completion` emits `id:desc`; drop anything that is not.
    _claw_top_cache=("${(@M)_claw_top_cache:#*:*}")
  fi
  (( ${#_claw_top_cache} )) || _claw_top_cache=("${_claw_top_fallback[@]}")
  return 0
}

# Profile ids straight from the registry (the 18-name list lives in exactly
# one place now); the glob is the no-registry fallback.
_claw_profile_ids() {
  local dotfiles="${DOTFILES_DIR:-$HOME/.dotfiles}"
  local reg="$dotfiles/scripts/utils/registry.sh"
  local -a ids
  [[ -r $reg ]] && ids=("${(@f)$(DOTFILES_DIR=$dotfiles command bash $reg ids profiles 2>/dev/null)}")
  ids=("${(@)ids:#}")
  (( ${#ids} )) || ids=($dotfiles/shell/profiles/*.zsh(N:t:r))
  print -rl -- $ids
}

# Attention ids are runtime data, not registry data: field 2 of attention.tsv
# (tier \t id \t text \t hint \t src \t since), written by situation.sh.
_claw_attention_ids() {
  local att="${XDG_CACHE_HOME:-$HOME/.cache}/claw/attention.tsv"
  [[ -r $att ]] || return 0
  command cut -f2 "$att" 2>/dev/null
}

_claw() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local dotfiles="${DOTFILES_DIR:-$HOME/.dotfiles}"

  _arguments -C '1: :->cmd' '*:: :->args' && return 0

  case $state in
    cmd)
      _claw_top_words
      _describe -t commands 'claw command' _claw_top_cache
      ;;
    args)
      case $words[1] in
        ai-services|aisvc|services)
          if (( CURRENT == 2 )); then
            _values 'action' list status up down restart pull logs prepare url
          else
            _values 'service' open-webui langfuse portainer caddy dify ragflow
          fi
          ;;
        theme|themes|colors)
          if (( CURRENT == 2 )); then
            _values 'action' list current set preview fzf build apply reload
          else
            # Theme libraries live in config/themes/<slug>/; fall back to the
            # legacy flat config/themes/<slug>.theme layout.
            local -a themes
            themes=($dotfiles/config/themes/*/palette.theme(N:h:t) $dotfiles/config/themes/*.theme(N:t:r))
            _values 'theme' $themes
          fi
          ;;
        install)
          _values 'toolchain' nextgen cloud security devops ai ai-workstation \
            ai-skills research cortex homelab deck demo design
          ;;
        load|pin)
          local -a profiles; profiles=("${(@f)$(_claw_profile_ids)}")
          [[ $words[1] == pin ]] && profiles+=(--clear)
          _values 'profile' $profiles
          ;;
        ack)
          if (( CURRENT == 2 )); then
            local -a ids; ids=("${(@f)$(_claw_attention_ids)}")
            ids=("${(@)ids:#}")
            _values 'attention id' $ids
          else
            _values 'flag' --hours
          fi
          ;;
        registry)
          _values 'command' rows palette help completion ids run show check
          ;;
        profiles)
          _values 'action' lint paths
          ;;
        integrity|verify|check)
          _values 'action' generate verify audit
          ;;
        docker|containers)
          _values 'flag' -a --all
          ;;
        gateway|openshell)
          _values 'action' check register status sandbox deploy-cluster
          ;;
        agent)
          _values 'action' list run
          ;;
        tui-stats)
          _values 'flag' \
            '--days[trailing window in days (default 30)]' \
            '--actor[human|agent|all (default human)]'
          ;;
        update|upgrade)
          _values 'flag' \
            '--repo[phase 1 only: ff-only pull + conditional regen]' \
            '--packages[phase 2 only: the one package engine]' \
            '--dry-run[print both phases plan, execute nothing]' \
            '--non-interactive[no clear/pause — what the timer runs]' \
            '--last[pretty-print recent run receipts]' \
            '--tools[curated fast-lane CLI refresh]' \
            '--schedule[weekly auto-update timer]'
          ;;
        selfupdate)
          _values 'action' now install status uninstall
          ;;
      esac
      ;;
  esac
}

compdef _claw claw 2>/dev/null
