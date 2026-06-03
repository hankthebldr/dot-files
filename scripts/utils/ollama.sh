#!/usr/bin/env bash
# scripts/utils/ollama.sh — cross-platform ollama daemon helpers.
# Sourced by bin/hermes (--serve) and scripts/install/hermes.sh (ensure_daemon).
# ollama_serve_cmd  : echo the right "start the daemon" command for this host (pure).
# ollama_up         : true if the daemon answers on :11434.
# ollama_ensure_up  : probe → start (via ollama_serve_cmd) → re-probe.
#
# Test seams: OS_TYPE, _OLLAMA_HAS_SYSTEMCTL, _OLLAMA_HAS_BREW may be preset by tests.

ollama_up() {
  curl -fsS --max-time 3 http://localhost:11434/api/tags &>/dev/null
}

ollama_serve_cmd() {
  local os="${OS_TYPE:-}"
  local has_systemctl="${_OLLAMA_HAS_SYSTEMCTL:-$(command -v systemctl &>/dev/null && echo 1 || echo 0)}"
  local has_brew="${_OLLAMA_HAS_BREW:-$(command -v brew &>/dev/null && echo 1 || echo 0)}"

  # Any systemd host (ubuntu/debian/fedora/rhel/arch/…) → managed service.
  if [[ "$has_systemctl" == 1 ]]; then
    echo "sudo systemctl enable --now ollama"; return
  fi
  # macOS → brew services. (Guarded to macOS: Linuxbrew's `brew services` is unreliable.)
  if [[ "$os" == macos && "$has_brew" == 1 ]]; then
    echo "brew services start ollama"; return
  fi
  echo "nohup ollama serve >/dev/null 2>&1 & disown"
}

# Bring the daemon up if it isn't. Returns 0 if reachable afterwards.
ollama_ensure_up() {
  ollama_up && return 0
  local cmd; cmd="$(ollama_serve_cmd)"
  echo "ollama: starting daemon → $cmd" >&2
  # eval is safe here: $cmd is one of three hard-coded literals from
  # ollama_serve_cmd — never external/user input.
  eval "$cmd" || echo "ollama: start command returned non-zero (continuing)" >&2
  # Give the daemon a moment, then re-probe a few times.
  local i
  for i in 1 2 3 4 5; do
    ollama_up && return 0
    sleep 1
  done
  ollama_up
}
