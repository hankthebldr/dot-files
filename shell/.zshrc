# .zshrc - Main Zsh Configuration

# 1. Path Configuration
source "$HOME/.dotfiles/shell/path.zsh"

# 2. Environment Variables
source "$HOME/.dotfiles/shell/exports.zsh"

# 3. Aliases
[[ -f "$HOME/.dotfiles/shell/aliases.zsh" ]] && source "$HOME/.dotfiles/shell/aliases.zsh"

# 4. Functions
[[ -f "$HOME/.dotfiles/shell/functions.zsh" ]] && source "$HOME/.dotfiles/shell/functions.zsh"

# 5. Zsh Settings & History
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE      # Don't save commands starting with space (Security)
setopt HIST_VERIFY
setopt SHARE_HISTORY

# 6. Prompt (Starship)
if command -v starship &>/dev/null; then
    eval "$(starship init zsh)"
fi

# 7. Plugins (Manual or Manager)
# Example: source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# 8. Security Profile (ParrotOS Interoperability)
# If on a security distro or requested, load security tools
if [[ -f "$HOME/.dotfiles/shell/security.zsh" ]]; then
    source "$HOME/.dotfiles/shell/security.zsh"
fi

# 9. Local Overrides (Last)
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
