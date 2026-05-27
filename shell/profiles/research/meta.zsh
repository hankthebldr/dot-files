# shell/profiles/research/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="research"
PROFILE_CLASS="DATA-DJ"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="dosbbs"
PROFILE_TAG="scraped the entire internet last weekend · organizing it by vibe"
PROFILE_FLAIR="ripgrep over 200GB · pandoc converting · scrapy crawling"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="research-toolchain.sh"
PROFILE_KEY_TOOLS="rg jq pandoc yt-dlp scrapy"
