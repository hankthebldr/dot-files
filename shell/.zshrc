# .zshrc
# Open Claw — Main Zsh Configuration (stow target)
# This should stay in sync with the root .zshrc

# 1. PATH setup (must be first)
source $HOME/.dotfiles/shell/path.zsh

# 2. Environment exports
source $HOME/.dotfiles/shell/exports.zsh

# 3. Load .env variables (if present)
[[ -f $HOME/.dotfiles/shell/load-env.zsh ]] && source $HOME/.dotfiles/shell/load-env.zsh

# 4. Aliases & functions
source $HOME/.dotfiles/shell/aliases.zsh
source $HOME/.dotfiles/shell/security.zsh
source $HOME/.dotfiles/shell/obsidian.zsh

# Integrated Help
alias dothelp='$HOME/.dotfiles/scripts/utils/help.sh'

# 5. Initialize Zoxide (Smart CD)
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
fi

# 6. Initialize Starship (Prompt)
if command -v starship &> /dev/null; then
    export STARSHIP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
    eval "$(starship init zsh)"
fi

# 7. FZF keybindings
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# 8. Atuin (Magical Shell History)
if command -v atuin &> /dev/null; then
    eval "$(atuin init zsh)"
fi

# 9. TheFuck (command correction)
if command -v thefuck &> /dev/null; then
    eval $(thefuck --alias)
    eval $(thefuck --alias fk)
fi

# 10. Syntax Highlighting & Autosuggestions
if [ -d /opt/homebrew/share/zsh-syntax-highlighting ]; then
    source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
if [ -d /opt/homebrew/share/zsh-autosuggestions ]; then
    source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# 11. Local Overrides
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
