# shell/claw-completion.zsh — zsh tab completion for the `claw` dispatcher.
# Sourced from ~/.zshrc after claw-fn.zsh (compinit has already run via OMZ).
# Two levels: top-level subcommands, then context-aware args for the common
# ones (ai-services actions + service names, theme names, install toolchains,
# profiles, integrity/gateway/docker actions).

_claw() {
  local curcontext="$curcontext" state line
  typeset -A opt_args
  local dotfiles="${DOTFILES_DIR:-$HOME/.dotfiles}"

  local -a top=(
    'menu:interactive menu'
    'help:show help'
    'doctor:environment health check'
    'validate:full install validation'
    'stats:usage statistics'
    'update:phased update — repo sync then packages'
    'tools:interactive tool updater'
    'install:install a domain toolchain'
    'ai-services:manage self-hosted AI/web stacks'
    'docker:grouped overview of all containers'
    'theme:switch color theme'
    'tun:SSH tunnel manager'
    'mcp:MCP server manager'
    'mcp-sync:render MCP registry to clients'
    'homelab:SSH topology manager'
    'toolkit:interactive workflow launcher'
    'skills:browse Claude skills'
    'obsidian:Obsidian vault integration'
    'onboard:gamified onboarding'
    'integrity:integrity manifest (generate/verify/audit)'
    'load:load a workflow profile'
    'profiles:profile contracts (lint) + start dirs (paths)'
    'off:reset to a plain shell'
    'restore-shell:relink shell dotfiles'
    'lock-shell:make shell symlinks immutable'
    'unlock-shell:lift the shell-symlink lock'
    'gpu:GPU / Blackwell node tools'
    'gateway:OpenShell gateway management'
    'secret:secrets manager'
    'provision:machine provisioning'
    'pkg:package manifest'
    'handoff:session handoff'
    'selfupdate:weekly auto-update timer (now/install/status/uninstall)'
    'cheatsheet:command cheatsheet'
    'docs-sync:sync docs to the vault'
    'capture-tasks:capture tasks'
    'agent:run or list registered agents'
    'claude-sync:sync Claude config'
    'uninstall:uninstall Open Claw'
  )

  _arguments -C '1: :->cmd' '*:: :->args' && return 0

  case $state in
    cmd)
      _describe -t commands 'claw command' top
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
        load)
          local -a profiles; profiles=($dotfiles/shell/profiles/*.zsh(N:t:r))
          _values 'profile' $profiles
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
