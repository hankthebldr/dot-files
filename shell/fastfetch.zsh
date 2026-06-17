# shell/fastfetch.zsh — terminal-aware fastfetch launcher for profile dashboards.
#
# Ghostty 1.3.x / Kitty / iTerm on a live LOCAL tty get the real raster brand
# logo via the kitty/iterm graphics protocol (logo-<profile>.png); everything
# else — SSH, tmux (passthrough is fragile and Ghostty has crashed on kitty
# images in tmux), dumb/linux/screen terminals, piped stdout, or a profile with
# no .png — falls back to the config's pre-rendered quad-block text logo
# (logo-<profile>.txt). The graphics logo is pinned to 28x14 cells so it shares
# the exact footprint the dashboards are laid out around.
#
# Why a shim and not `--logo-type auto`: fastfetch's auto does NOT probe terminal
# graphics capability and has no image->text fallback over SSH (verified against
# fastfetch 2.63 + upstream docs), so graceful degradation must be scripted.

# True only on a real local tty in a graphics-capable, non-SSH, non-tmux context.
_claw_ff_graphics_ok() {
  emulate -L zsh
  [[ -t 1 ]] || return 1                            # real tty only (never piped)
  [[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]] || return 1   # not over SSH
  [[ -z "${TMUX:-}" ]] || return 1                  # not inside tmux
  case "$TERM" in dumb | linux | screen* | tmux*) return 1 ;; esac
  return 0
}

# claw_ff <profile> <config-path> — render a profile dashboard with the best
# logo the current terminal supports. Safe to call from non-interactive shells
# (it no-ops when fastfetch or the config is missing).
claw_ff() {
  emulate -L zsh
  command -v fastfetch &>/dev/null || return 0
  local prof="$1" cfg="$2"
  [[ -n "$prof" && -f "$cfg" ]] || return 0
  local png="${DOTFILES_DIR:-$HOME/.dotfiles}/config/.config/fastfetch/logo-$prof.png"
  local -a logo=()
  if [[ -f "$png" ]] && _claw_ff_graphics_ok; then
    case "${TERM_PROGRAM:-}" in
      ghostty | WezTerm) logo=(--logo-type kitty --logo "$png" --logo-width 28 --logo-height 14) ;;
      iTerm.app)         logo=(--logo-type iterm --logo "$png" --logo-width 28 --logo-height 14) ;;
      *) [[ -n "${KITTY_WINDOW_ID:-}" ]] && logo=(--logo-type kitty --logo "$png" --logo-width 28 --logo-height 14) ;;
    esac
  fi
  fastfetch -c "$cfg" "${logo[@]}" 2>/dev/null
}
