# shell/load-env.zsh
# Loads environment variables from .env file

# Function to load .env file
load_env() {
    local env_file="${1:-.env}"
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/Github/Github_desktop/dot-files}"
    local env_path="$dotfiles_dir/$env_file"

    if [[ -f "$env_path" ]]; then
        # Export all variables from .env file silently
        set -a
        source "$env_path"
        set +a
    fi
}

# Auto-load .env if it exists
if [[ -f "${DOTFILES_DIR:-$HOME/Github/Github_desktop/dot-files}/.env" ]]; then
    load_env
fi
