# shell/path.zsh
# Centralized PATH management (cross-platform)

# Homebrew — macOS Apple Silicon
if [[ -d /opt/homebrew ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
# Homebrew — macOS Intel
elif [[ -d /usr/local/Homebrew ]]; then
    export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
# Homebrew — Linux (Linuxbrew)
elif [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || \
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
fi

# User binaries
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH"

# Language toolchains
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"     # Rust
[[ -d "$HOME/go/bin" ]]     && export PATH="$HOME/go/bin:$PATH"         # Go

# Dotfiles utilities
export PATH="${DOTFILES_DIR:-$HOME/.dotfiles}/scripts/utils:$PATH"
