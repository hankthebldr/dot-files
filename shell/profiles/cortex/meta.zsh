# shell/profiles/cortex/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="cortex"
PROFILE_CLASS="GHOST-IN-THE-XSIAM"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="knows what XSOAR stands for · actually likes it"
PROFILE_FLAIR="XSIAM tenants on speed-dial · panos-cli for the rest"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="cortex-toolchain.sh"
PROFILE_KEY_TOOLS="demisto-sdk panos-cli pipx python3"
