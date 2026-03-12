# shell/path.zsh
# Centralized PATH management

# Homebrew (Apple Silicon)
if [[ -d /opt/homebrew ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi

# User binaries
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# Language toolchains
export PATH="$HOME/.cargo/bin:$PATH"    # Rust
export PATH="$HOME/go/bin:$PATH"        # Go

# Dotfiles utilities (DOTFILES_DIR is set by exports.zsh)
export PATH="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils:$PATH"
