# shell/profiles/default/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="default"
PROFILE_CLASS="PIXEL-DRIFTER"
PROFILE_TIER="1"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"
PROFILE_TAG="the chill one — just wants a nice prompt and z to work"
PROFILE_FLAIR="zoxide warm · starship lit · just enough fastfetch"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# empty on purpose — the daily driver never relocates you
PROFILE_START_DIR=""

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN=""
PROFILE_KEY_TOOLS="zoxide starship fzf rg bat eza"
