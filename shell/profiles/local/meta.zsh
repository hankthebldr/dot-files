# shell/profiles/local/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="local"
PROFILE_CLASS="GARAGE-HACKER"
PROFILE_TIER="1"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="dosbbs"
PROFILE_TAG="compiles everything from source · owns 11 unfinished CLI tools"
PROFILE_FLAIR="11 half-finished CLI tools — one of them will ship in 2027"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN=""
PROFILE_KEY_TOOLS="git make tmux nvim fzf"
