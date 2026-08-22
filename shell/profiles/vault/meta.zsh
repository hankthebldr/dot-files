# shell/profiles/vault/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="vault"
PROFILE_CLASS="KNOWLEDGE-KEEPER"
PROFILE_TIER="4"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="dosbbs"
PROFILE_TAG="scraped your second brain and organized it by vibe"
PROFILE_FLAIR="every note links to three others — somehow they all matter"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# @vault = the registered Obsidian vault ROOT (~/hr-vault-main-pa) — the whole
# second brain, not one profile-scoped folder (that would be @vault-folder).
PROFILE_START_DIR="@vault"

# OS SUPPORT
# Vault tooling is mostly OS-agnostic (ripgrep, fzf, Obsidian via URL scheme).
# Mac-specific bits: Spotlight (mdfind), Granola audio capture.
# Linux-specific bits: ripgrep-only search (no Spotlight), inotify watchers.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN=""
PROFILE_KEY_TOOLS="rg fzf glow bat pandoc yq obsidian"
