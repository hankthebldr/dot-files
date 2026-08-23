# shell/profiles/claude/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="claude"
PROFILE_CLASS="PROMPT-RIDER"
PROFILE_TIER="3"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"
PROFILE_TAG="talks to AI more than humans · git history is 90% agent commits"
PROFILE_FLAIR="MCP servers · Agent SDK · skill registry curated weekly"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# same dir CLAUDE_WORKSPACE points agents at (common.zsh)
PROFILE_START_DIR="${CLAUDE_WORKSPACE:-$HOME/projects}"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN=""
PROFILE_KEY_TOOLS="claude npm node mcp"
