#!/usr/bin/env bash
# cheatsheet.sh — one-screen reference for the commands you'd otherwise only
# find by reading source. claw cheatsheet (alias: claw cheat).
set -uo pipefail
r=$'\e[0m'; b=$'\e[1m'; B=$'\e[38;2;88;166;255m'; G=$'\e[38;2;63;185;80m'
P=$'\e[38;2;188;140;255m'; O=$'\e[38;2;227;179;65m'; D=$'\e[38;2;139;148;158m'; W=$'\e[38;2;201;209;217m'
h(){ printf "\n  ${P}${b}%s${r}\n" "$1"; }
c(){ printf "    ${G}%-26s${r}${D}%s${r}\n" "$1" "$2"; }

printf "\n  ${B}${b}OPEN CLAW — cheatsheet${r}  ${D}(claw help for the full dispatcher)${r}\n"
h "Provision & maintain"
c "claw provision [--dry-run]" "fresh box → fully configured (mac/linux)"
c "claw pkg scan|track|update" "self-aware tool registry (track new tools → repo)"
c "claw selfupdate install" "weekly auto-update (topgrade) timer"
c "claw doctor / validate" "system + profile health · install check"
c "claw install <domain>" "nextgen|cloud|security|devops|ai|… toolchains"
h "Profiles"
c "claw load <profile> / off" "source/unset a profile (18 available)"
c "claw onboard" "arcade wizard → picks your profile"
h "Agents & AI"
c "claw claude|gemini|hermes" "launch a registered agent (one .env)"
c "claw agent doctor" "binary + key + config health per agent"
c "claw agent mcp-sync [--dry-run]" "one registry → Claude Code/Gemini/Desktop"
c "claw ai serve|chat|web|doctor" "local Ollama/aichat/open-webui/n8n stack"
h "Knowledge (Things ↔ Claude ↔ Obsidian)"
c "claw handoff \"topic\"" "session note → vault 00-Inbox (backlinked)"
c "claw capture-tasks [--apply]" "vault '@things' lines → Things 3 tasks"
c "on / os / ov / otoday / ocapture" "obsidian nav + capture"
h "Secrets"
c "claw secret init|env|doctor" "age+sops · .env.sops auto-loads into shell"
h "Daily delight"
c "cpv / mvv  <src> <dst>" "copy/move with rsync progress bar"
c "dlv <url> / xtract <archive>" "download (aria2/xh) / extract with progress"
c "weather [city] · z <dir>" "wttr.in · zoxide jump"
c "CLAW_TUI=1 exec zsh" "opt into the ratatui front-end"
printf "\n"
