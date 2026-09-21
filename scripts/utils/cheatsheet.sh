#!/usr/bin/env bash
# cheatsheet.sh — one-screen reference for the commands you'd otherwise only
# find by reading source. claw cheatsheet (alias: claw cheat).
set -uo pipefail
# Colours come from the ONE theme engine (F-13): source theme.sh unless the
# shell already exported a palette, then derive from CLAW_RGB_* with
# refined-dark fallbacks. T1 swaps this for `claw_theme_emit tui`.
# ── begin palette block ──
_cs_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
[ -n "${CLAW_C_BG:-}" ] || { [ -r "$_cs_dots/scripts/utils/theme.sh" ] && . "$_cs_dots/scripts/utils/theme.sh" 2>/dev/null; }
r=$'\e[0m'; b=$'\e[1m'
B=$'\e[38;2;'"${CLAW_RGB_BLUE:-88;166;255}"$'m';   G=$'\e[38;2;'"${CLAW_RGB_GREEN:-63;185;80}"$'m'
P=$'\e[38;2;'"${CLAW_RGB_PURPLE:-188;140;255}"$'m'; O=$'\e[38;2;'"${CLAW_RGB_AMBER:-227;179;65}"$'m'
D=$'\e[38;2;'"${CLAW_RGB_MUTED:-139;148;158}"$'m';  W=$'\e[38;2;'"${CLAW_RGB_FG:-201;209;217}"$'m'
unset _cs_dots
# ── end palette block ──
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
# Profile count from the ONE registry (spine contract 5) — never a literal.
_cs_dots="${DOTFILES_DIR:-$HOME/.dotfiles}"
_cs_np="$(DOTFILES_DIR="$_cs_dots" bash "$_cs_dots/scripts/utils/registry.sh" ids profiles \
          2>/dev/null | grep -c . || true)"
[ "${_cs_np:-0}" -gt 0 ] 2>/dev/null || _cs_np="?"
c "claw load <profile> / off" "source/unset a profile ($_cs_np available)"
unset _cs_dots _cs_np
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
c "claw output" "persist display: mode rich/plain · frame · banner"
c "progress on|off|status" "live status panel master switch (long pkg ops)"
printf "\n"
