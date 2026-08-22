# shell/profiles/demo/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="demo"
PROFILE_CLASS="SHOW-RUNNER"
PROFILE_TIER="5"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"
PROFILE_TAG="never accidentally leaks a secret on screen-share"
PROFILE_FLAIR="big font · clean prompt · DND on · history scrubbed"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# canned datasets + demo scripts (DEMO_ASSETS in common.zsh)
PROFILE_START_DIR="${DEMO_ASSETS:-$HOME/Demos}"

# OS SUPPORT
# Both OSes get the same engage/disengage flow. Tools differ:
#   Mac:   shortcuts CLI (DND), caffeinate, osascript notifications
#   Linux: dunstctl (DND), caffeine daemon, dbus notification toggle
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="demo-toolchain.sh"
PROFILE_KEY_TOOLS="asciinema agg gum"
