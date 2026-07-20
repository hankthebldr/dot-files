# shell/load-env.zsh
# Loads environment variables from .env file.
# Optional: resolves op:// references via 1Password CLI when `op` is on PATH.

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

# Resolve op://vault/item/field references via 1Password CLI when available.
# Sustainable + opt-in: no `op` dependency. If `op` is missing the value is
# left literal (and the consumer script will surface a clear error).
#
# Pattern: any env var whose value starts with `op://` is resolved in-place.
_claw_resolve_op_refs() {
    command -v op &>/dev/null || return 0
    local var val
    for var in OPENROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY \
               GOOGLE_API_KEY HUGGINGFACE_TOKEN; do
        val="${(P)var}"
        if [[ "$val" == op://* ]]; then
            local resolved
            resolved=$(op read "$val" 2>/dev/null) && export "$var=$resolved"
        fi
    done
}

# Auto-load .env if it exists, then resolve op:// refs (best-effort, silent)
if [[ -f "${DOTFILES_DIR:-$HOME/Github/Github_desktop/dot-files}/.env" ]]; then
    load_env
    _claw_resolve_op_refs 2>/dev/null
fi

# Decrypt sops-managed secrets into the env. secret.sh runs `set -uo pipefail`;
# run it as a SUBPROCESS emitting `export` lines and eval them, so those options
# never leak into this interactive shell (they would make every later unset-var
# expansion fatal). Silent + guarded.
if [[ -f "$DOTFILES_DIR/config/secrets/.env.sops" ]] && command -v sops &>/dev/null; then
    eval "$(bash "$DOTFILES_DIR/scripts/utils/secret.sh" env-export 2>/dev/null)"
fi
