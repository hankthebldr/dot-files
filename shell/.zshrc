# ============================================
# OPEN CLAW — ZSH Configuration (Cross-Platform)
# ============================================
# Supports: macOS (ARM/Intel), Ubuntu, Debian, Kali, Parrot
#
# Loading order:
#   1. PATH + DOTFILES_DIR (must be first — tools need to be in PATH)
#   2. Platform shims (clipboard, open, IP — cross-platform)
#   3. Welcome TUI (fastfetch + fzf menu — BEFORE p10k instant prompt)
#   4. P10k instant prompt
#   5. Oh-My-Zsh framework + plugins
#   6. Modular sources (exports, aliases, security, obsidian)
#   7. Tool initializations (zoxide, direnv, atuin, eza, thefuck)
#   8. P10k theme config

# ── 1. PATH + DOTFILES_DIR ──────────────────────────────
# Must be FIRST so fastfetch, fzf, and all brew tools are found
export DOTFILES_DIR="$HOME/.dotfiles"

# Homebrew PATH (before anything else needs brew-installed tools)
if [[ -d /opt/homebrew ]]; then
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
elif [[ -d /home/linuxbrew/.linuxbrew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv 2>/dev/null)" || \
    export PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"
elif [[ -d /usr/local/Homebrew ]]; then
    export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
fi
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
[[ -d "$HOME/go/bin" ]]     && export PATH="$HOME/go/bin:$PATH"
export PATH="${DOTFILES_DIR}/scripts/utils:$PATH"

# ── 2. Platform Shims ───────────────────────────────────
[[ -f "$DOTFILES_DIR/shell/platform.zsh" ]] && source "$DOTFILES_DIR/shell/platform.zsh"

# ── 2b. Theme engine (single source of truth for ALL colors) ─────────────────
# Sourcing exports CLAW_C_* / CLAW_RGB_* from the active palette
# (config/themes/<slug>.theme; precedence: CLAW_THEME env → state file →
# refined-dark). Loaded BEFORE the welcome TUI and every shell module so menus,
# dashboards, nudges, and prompts all draw from one palette. `claw theme set X`
# + exec zsh re-themes everything.
[[ -f "$DOTFILES_DIR/scripts/utils/theme.sh" ]] && source "$DOTFILES_DIR/scripts/utils/theme.sh"

# ── 3. Welcome TUI (BEFORE p10k instant prompt) ─────────
# P10k instant prompt suppresses all stdout during init.
# The TUI must run BEFORE that, while we still own the terminal.
if [[ -f "$DOTFILES_DIR/shell/welcome-tui.zsh" ]]; then
    source "$DOTFILES_DIR/shell/welcome-tui.zsh"
    claw_welcome_tui
fi

# ── 4. Powerlevel10k ─────────────────────────────────────
# Instant prompt DISABLED — Open Claw TUI (fastfetch + fzf) provides
# the immediate visual feedback that instant prompt was designed for.
# P10k theme is loaded in step 8 after OMZ initializes.

# ── 5. Oh-My-Zsh Framework ─────────────────────────────
export ZSH="$HOME/.oh-my-zsh"

# Skip compaudit's insecure-directory check — Homebrew's site-functions are
# group-writable on macOS and trigger spurious warnings on every shell start.
ZSH_DISABLE_COMPFIX="true"

if [[ -d "$ZSH" ]]; then
    ZSH_THEME="powerlevel10k/powerlevel10k"

    if [[ -d ${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src ]]; then
        fpath+=${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src
    fi

    HYPHEN_INSENSITIVE="true"
    COMPLETION_WAITING_DOTS="true"
    zstyle ':omz:update' mode auto

    plugins=(
        git gh github aliases sudo vi-mode copybuffer copypath copyfile cp
        colored-man-pages jsontools
        aws azure gcloud kubectl helm kubectx terraform vault ansible
        docker docker-compose istioctl operator-sdk kind
        golang python node npm dotnet brew
        colorize web-search emoji ssh ssh-agent
    )
    [[ "$OSTYPE" == "darwin"* ]] && plugins+=(macos vscode)
    [[ -f /etc/debian_version ]] && plugins+=(ubuntu debian)

    source "$ZSH/oh-my-zsh.sh"
fi

# ── 6. Modular Sources ─────────────────────────────────
# path.zsh already handled in step 1, but source for any extras
[[ -f "$DOTFILES_DIR/shell/exports.zsh" ]] && source "$DOTFILES_DIR/shell/exports.zsh"
[[ -f "$DOTFILES_DIR/shell/load-env.zsh" ]] && source "$DOTFILES_DIR/shell/load-env.zsh"
[[ -f "$DOTFILES_DIR/shell/aliases.zsh" ]] && source "$DOTFILES_DIR/shell/aliases.zsh"
[[ -f "$DOTFILES_DIR/shell/profile-helpers.zsh" ]] && source "$DOTFILES_DIR/shell/profile-helpers.zsh"
[[ -f "$DOTFILES_DIR/shell/claw-fn.zsh" ]] && source "$DOTFILES_DIR/shell/claw-fn.zsh"
[[ -f "$DOTFILES_DIR/shell/security.zsh" ]] && source "$DOTFILES_DIR/shell/security.zsh"
[[ -f "$DOTFILES_DIR/shell/obsidian.zsh" ]] && source "$DOTFILES_DIR/shell/obsidian.zsh"
# Live progress indicator (window title + completion banner + claw_run wrapper)
[[ -f "$DOTFILES_DIR/shell/progress.zsh" ]] && source "$DOTFILES_DIR/shell/progress.zsh"
[[ -f "$DOTFILES_DIR/shell/delight.zsh" ]] && source "$DOTFILES_DIR/shell/delight.zsh"
[[ -f ~/hr-vault-main-pa/_agents/shell-aliases.sh ]] && source ~/hr-vault-main-pa/_agents/shell-aliases.sh

# ── 7. Tool Initializations (all guarded) ───────────────
command -v zoxide &>/dev/null && eval "$(zoxide init zsh)"
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"
command -v atuin &>/dev/null && eval "$(atuin init zsh)"
# TheFuck — lazy-loaded (thefuck --alias is slow, ~400ms)
if command -v thefuck &>/dev/null; then
    fuck() { unfunction fuck; eval $(thefuck --alias); fuck "$@"; }
fi

# Modern CLI replacements (eza/colorls aliases) live in shell/aliases.zsh,
# sourced in step 6 — kept there as the single source of truth.

# zsh-syntax-highlighting (cross-platform)
for _zsh_hl in \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/home/linuxbrew/.linuxbrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "/usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"; do
    if [[ -f "$_zsh_hl" ]]; then source "$_zsh_hl"; break; fi
done
unset _zsh_hl

# zsh-autocomplete — DISABLED.
# This plugin draws a live completion menu under the prompt on every keystroke,
# which fights Powerlevel10k's multi-line prompt: the prompt jumps, inserts
# spaces ("auto-next"), and spams newlines. It is a known p10k incompatibility.
# Tab-completion, history search (atuin), autosuggestions, and syntax
# highlighting all still work without it. To re-enable deliberately, set
# CLAW_ENABLE_ZSH_AUTOCOMPLETE=1 before this file is sourced.
if [[ -n "${CLAW_ENABLE_ZSH_AUTOCOMPLETE-}" ]]; then
    for _zsh_ac in \
        "${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
        "/home/linuxbrew/.linuxbrew/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
        "/usr/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh" \
        "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh"; do
        if [[ -f "$_zsh_ac" ]]; then source "$_zsh_ac" 2>/dev/null; break; fi
    done
    unset _zsh_ac
fi

# Google Cloud SDK
for _gcloud in \
    "$HOME/Downloads/google-cloud-sdk" "/usr/lib/google-cloud-sdk" \
    "/snap/google-cloud-cli/current" "$HOME/google-cloud-sdk"; do
    if [[ -f "$_gcloud/path.zsh.inc" ]]; then
        source "$_gcloud/path.zsh.inc"
        [[ -f "$_gcloud/completion.zsh.inc" ]] && source "$_gcloud/completion.zsh.inc"
        break
    fi
done
unset _gcloud

# ── 8. Powerlevel10k Theme Config ───────────────────────
export EDITOR='nvim'
export VISUAL='nvim'
export CLICOLOR=1

# Profile was loaded by TUI in step 3 — load p10k config for it
if [[ -n "$CLAW_ACTIVE_PROFILE" ]]; then
    PROFILE_PATH="$DOTFILES_DIR/shell/profiles/${CLAW_ACTIVE_PROFILE}.zsh"
    # Profile may already be sourced by TUI, but guard for manual CLAW_ACTIVE_PROFILE sets
    # PROFILE_NAME (set by every profile's meta.zsh) = "already sourced by the
    # TUI" sentinel. The old sentinel was CLAW_PROFILE_THEME, a dead export
    # removed in the P2 theme unification.
    [[ -f "$PROFILE_PATH" && -z "${PROFILE_NAME:-}" ]] && source "$PROFILE_PATH"
fi

# ── Powerlevel10k prompt — sourced from the REPO, not ~/.p10k.zsh ───────────
# Decoupled on purpose. `p10k configure` overwrites ~/.p10k.zsh (and used to
# write 5 ~/.p10k-<profile>.zsh files) with a 1786-line vanilla config carrying
# instant_prompt=verbose — which re-enables instant prompt and breaks the
# fastfetch TUI. Sourcing the tuned theme straight from the repo means a
# clobbered ~/.p10k.zsh can no longer replace the OPEN CLAW prompt; the home
# copy is only a fallback for a machine without the repo checked out.
if [[ -r "$DOTFILES_DIR/shell/.p10k.zsh" ]]; then
    source "$DOTFILES_DIR/shell/.p10k.zsh"
elif [[ -r "$HOME/.p10k.zsh" ]]; then
    source "$HOME/.p10k.zsh"
fi

# Drift guard: if a stow symlink got clobbered into a plain file (the p10k
# configure failure mode), say so once per interactive shell. Near-zero cost.
if [[ -o interactive ]]; then
    for _df in .p10k.zsh .zshrc; do
        if [[ -e "$HOME/$_df" && ! -L "$HOME/$_df" ]]; then
            print -P "  %F{214}⚠%f %F{245}~/$_df is a plain file, not the repo symlink (clobbered?) — fix with %F{39}claw restore-shell%f"
        fi
    done
    unset _df
fi

# Guard: stop `p10k configure` from overwriting the symlinked, pre-tuned prompt.
[[ -f "$DOTFILES_DIR/shell/p10k-guard.zsh" ]] && source "$DOTFILES_DIR/shell/p10k-guard.zsh"

# Terraform completion
_tf_bin="$(command -v terraform 2>/dev/null)"
if [[ -n "$_tf_bin" ]]; then
    autoload -U +X bashcompinit && bashcompinit
    complete -o nospace -C "$_tf_bin" terraform
fi
unset _tf_bin

typeset -g POWERLEVEL9K_KUBECONTEXT_SHOW_ON_COMMAND='kubectl|helm|kubens'

if (( ! ${fpath[(I)/usr/local/share/zsh/site-functions]} )); then
    FPATH=/usr/local/share/zsh/site-functions:$FPATH
fi

alias zshconfig="${EDITOR:-vim} ~/.zshrc"
alias ohmyzsh="${EDITOR:-vim} ~/.oh-my-zsh"

# ── FZF Keybindings (Ctrl+T, Alt+C, Ctrl+R override) ────
for _fzf_init in \
    "$HOME/.fzf.zsh" \
    "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/fzf/shell/key-bindings.zsh" \
    "/usr/share/doc/fzf/examples/key-bindings.zsh" \
    "/usr/share/fzf/key-bindings.zsh"; do
    if [[ -f "$_fzf_init" ]]; then source "$_fzf_init"; break; fi
done
unset _fzf_init

# ── Local Overrides (not tracked in git) ────────────────
[[ -f "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"

# ── Appended PATH (external tools) ──────────────────────
[[ -d "$HOME/.antigravity/antigravity/bin" ]] && export PATH="$HOME/.antigravity/antigravity/bin:$PATH"
[[ -d "$HOME/.lmstudio/bin" ]] && export PATH="$PATH:$HOME/.lmstudio/bin"

# Ollama: store models on LACIE HD (8TB external) — only when the drive is
# actually mounted, else ollama would fail to read/write models on Linux or
# on a Mac without the drive attached.
[[ -d /Volumes/LacieDrive ]] && export OLLAMA_MODELS="/Volumes/LacieDrive/ollama-models"
