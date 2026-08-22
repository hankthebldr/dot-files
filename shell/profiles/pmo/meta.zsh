# shell/profiles/pmo/meta.zsh
PROFILE_NAME="pmo"
PROFILE_CLASS="SCRIBE-OPERATOR"
PROFILE_TIER="4"
PROFILE_THEME_DEFAULT="dosbbs"
PROFILE_TAG="Things 3 is the inbox. the repo is the truth. PR is the receipt."
PROFILE_FLAIR="closes the loop between what you said you'd build and what you built"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# the vault folder mapped to pmo (WWTS - Projects), vault root if absent
PROFILE_START_DIR="@vault-folder"

# Mac-primary because Things 3 (the system of record) is macOS-only.
# Linux gets a stub with taskwarrior + SSH-to-Mac fallback hints.
PROFILE_OS_SUPPORT="mac-primary"

PROFILE_TOOLCHAIN=""   # no installer — Things 3 + sync-docs skill are config, not packages
PROFILE_KEY_TOOLS="claude git gh"
