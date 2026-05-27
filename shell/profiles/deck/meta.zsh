# shell/profiles/deck/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="deck"
PROFILE_CLASS="DECK-SMITH"
PROFILE_TIER="5"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="vhs"
PROFILE_TAG="ships customer artifacts on a 6-hour deadline"
PROFILE_FLAIR="every screenshot crops itself · every GIF stays under 4 MB"

# OS SUPPORT
# Mac is the primary slide-building machine (Office 365, Hammerspoon hotkeys,
# native screencapture). Linux variant uses LibreOffice for PPTX export and
# Wayland-native screenshot/recording tools.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="deck-toolchain.sh"     # to be built in Phase B2 follow-up
PROFILE_KEY_TOOLS="marp pandoc gifski asciinema imagemagick"
