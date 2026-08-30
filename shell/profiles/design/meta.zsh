# shell/profiles/design/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="design"
PROFILE_CLASS="FRAME-SMITH"
PROFILE_TIER="5"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="vhs"
PROFILE_TAG="every diagram tells the same story, just better"
PROFILE_FLAIR="palette chosen at 2am · pixel-grid alignment is not negotiable"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# diagram + asset scratch space (DESIGN_HOME in common.zsh)
PROFILE_START_DIR="${DESIGN_HOME:-$HOME/Design}"

# OS SUPPORT
# Toolchain (mermaid, d2, imagemagick, excalidraw-cli) runs identically on
# both. OS divergence is GUI integration: Mac has the Figma desktop app and
# native viewers; Linux uses inkscape (CLI) and xdg-open.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="design-toolchain.sh"
PROFILE_KEY_TOOLS="mermaid d2 imagemagick jp2a excalidraw"
