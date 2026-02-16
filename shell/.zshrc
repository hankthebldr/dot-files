# .zshrc
# Main Zsh configuration file

# 1. Source exports first
source $HOME/.dotfiles/shell/exports.zsh

# 2. Source aliases
source $HOME/.dotfiles/shell/aliases.zsh
source $HOME/.dotfiles/shell/security.zsh

# Integrated Help
alias dothelp='$HOME/.dotfiles/scripts/utils/help.sh'


# 3. Initialize Zoxide (Smart CD)
if command -v zoxide &> /dev/null; then
  eval "$(zoxide init zsh)"
fi

# 4. Initialize Starship (Prompt)
if command -v starship &> /dev/null; then
  export STARSHIP_CONFIG="$HOME/.config/starship.toml"
  eval "$(starship init zsh)"
fi

# 5. FZF Configuration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# 6. Atuin (Magical Shell History)
if command -v atuin &> /dev/null; then
  eval "$(atuin init zsh)"
fi

# 7. Syntax Highlighting & Autosuggestions (if installed via brew)
if [ -d /opt/homebrew/share/zsh-syntax-highlighting ]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
if [ -d /opt/homebrew/share/zsh-autosuggestions ]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# 7. Local Overrides
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
