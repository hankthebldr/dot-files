#!/usr/bin/env bash
# ai.sh — claw ai: the local + web AI stack (Ollama/aichat/open-webui/n8n).
set -uo pipefail
DOTFILES="${DOTFILES_DIR:-$HOME/.dotfiles}"
source "$DOTFILES/scripts/utils/cinematic.sh" 2>/dev/null || { log_info(){ echo "▸ $*"; }; log_success(){ echo "✓ $*"; }; log_warning(){ echo "! $*"; }; log_skip(){ echo "· $*"; }; c_white=''; c_reset=''; c_dim=''; }
have(){ command -v "$1" &>/dev/null; }
_open(){ command -v claw_open &>/dev/null && claw_open "$1" || { command -v open &>/dev/null && open "$1" || xdg-open "$1" 2>/dev/null; }; }

case "${1:-doctor}" in
  serve)   have ollama && { pgrep -x ollama >/dev/null || { log_info "starting ollama…"; (ollama serve >/dev/null 2>&1 &) ; sleep 1; }; log_success "ollama on :11434"; } || log_warning "ollama not installed (claw provision)";;
  models)  have ollama && ollama list || log_warning "ollama not installed";;
  pull)    shift; have ollama && ollama pull "${1:?usage: claw ai pull <model>}" || log_warning "ollama not installed";;
  chat)    shift; have aichat && aichat "$@" || { have openrouter && openrouter "$@" || log_warning "aichat/openrouter not installed"; };;
  web)     _open "http://localhost:3000"; log_info "open-webui → :3000 (n8n usually :5678)";;
  n8n)     _open "http://localhost:5678";;
  doctor)
    printf "\n  ${c_white}local AI stack${c_reset}\n"
    have ollama && { pgrep -x ollama >/dev/null && log_success "ollama running :11434" || log_warning "ollama installed, not running (claw ai serve)"; } || log_warning "ollama missing"
    have aichat && log_success "aichat $(aichat --version 2>/dev/null|head -1)" || log_skip "aichat missing"
    [[ -n "${OPENROUTER_API_KEY:-}" ]] && log_success "OPENROUTER_API_KEY set" || log_skip "OPENROUTER_API_KEY unset"
    [[ -n "${OLLAMA_OPENAI_BASE:-}" ]] && log_success "OLLAMA_OPENAI_BASE=$OLLAMA_OPENAI_BASE" || true
    ;;
  *) echo "usage: claw ai {serve|models|pull <m>|chat|web|n8n|doctor}";;
esac
