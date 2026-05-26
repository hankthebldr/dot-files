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

# OS SUPPORT
# Both OSes get the same engage/disengage flow. Tools differ:
#   Mac:   shortcuts CLI (DND), caffeinate, osascript notifications
#   Linux: dunstctl (DND), caffeine daemon, dbus notification toggle
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="demo-toolchain.sh"
PROFILE_KEY_TOOLS="asciinema agg gum"
