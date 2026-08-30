# shell/profiles/brainstorm/meta.zsh
PROFILE_NAME="brainstorm"
PROFILE_CLASS="SPARK-CATCHER"
PROFILE_TIER="4"
PROFILE_THEME_DEFAULT="vhs"
PROFILE_TAG="catches sparks before they become tasks"
PROFILE_FLAIR="three good ideas, four bad ones, and a song stuck in your head"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# where `spark` appends; vault root until the first spark lands
PROFILE_START_DIR="@vault:_brainstorm|@vault"

PROFILE_OS_SUPPORT="mac+linux"
PROFILE_TOOLCHAIN=""
PROFILE_KEY_TOOLS="rg fzf glow gum markmap mermaid"
