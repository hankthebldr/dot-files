# =============================================================================
# OPEN CLAW — p10k configure guard
# =============================================================================
# This repo ships a hand-tuned ~/.p10k.zsh, stowed as a symlink into
# ~/.dotfiles/shell/.p10k.zsh. Running `p10k configure` overwrites that file
# with a vanilla wizard config AND replaces the stow symlink with a plain file —
# which is what previously dropped the fastfetch/profile/prompt work.
#
# `p10k` is a function defined by powerlevel10k during framework init. We copy
# the original to `_p10k_orig`, then wrap `p10k` so the `configure` subcommand is
# blocked with guidance. Every other subcommand passes straight through.
#
# Deliberate override (you really do want the wizard): run `_p10k_orig configure`.
# Sourced at the end of ~/.zshrc, after the theme has loaded.
# =============================================================================

if typeset -f p10k >/dev/null 2>&1 && ! typeset -f _p10k_orig >/dev/null 2>&1; then
  functions -c p10k _p10k_orig
  p10k() {
    if [[ "${1:-}" == "configure" ]]; then
      print -P ""
      print -P "  %F{214}⚠ Blocked: 'p10k configure' would overwrite your pre-tuned prompt.%f"
      print -P "  %F{245}~/.p10k.zsh is a stow symlink into ~/.dotfiles/shell/.p10k.zsh — the%f"
      print -P "  %F{245}wizard replaces it with a vanilla file and breaks the symlink. That is%f"
      print -P "  %F{245}what dropped the fastfetch / profile work last time.%f"
      print -P ""
      print -P "  Tweak the theme:        edit %F{39}\$DOTFILES_DIR/shell/.p10k.zsh%f then %F{39}exec zsh%f"
      print -P "  Relink a broken symlink:%F{39}claw restore-shell%f"
      print -P "  Run the wizard anyway:  %F{245}_p10k_orig configure%f  %F{245}(then commit the result)%f"
      print -P ""
      return 1
    fi
    _p10k_orig "$@"
  }
fi
