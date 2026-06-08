# ============================================================================
# OPEN CLAW — Ghostty terminfo guard
# ============================================================================
# Ghostty launches with TERM=xterm-ghostty. If that terminfo entry is not in
# the local database, clear / colors / full-screen apps (vim, less, fzf) and
# ssh sessions misbehave — and Powerlevel10k's gitstatus can fail to init.
#
# terminfo lives in ~/.terminfo (per-machine, NOT stowed by these dotfiles),
# so this self-heals: on first launch inside Ghostty, copy the canonical entry
# from Ghostty's own bundled terminfo into ~/.terminfo. After that the entry
# exists and the cheap `-e` test short-circuits (no subprocess on later starts).
#
# Sourced from .zshrc step 2.5 — before the Welcome TUI which needs the terminal.
# ============================================================================

if [[ "$TERM" == xterm-ghostty && ! -e "$HOME/.terminfo/x/xterm-ghostty" ]]; then
  for _gti in \
    /snap/ghostty/current/share/terminfo \
    /opt/homebrew/opt/ghostty/share/terminfo \
    /usr/local/opt/ghostty/share/terminfo \
    /Applications/Ghostty.app/Contents/Resources/terminfo \
    /usr/share/terminfo \
  ; do
    if [[ -f "$_gti/x/xterm-ghostty" ]]; then
      mkdir -p "$HOME/.terminfo/x" \
        && cp "$_gti/x/xterm-ghostty" "$HOME/.terminfo/x/xterm-ghostty"
      break
    fi
  done
  unset _gti
fi
