# shell/profiles/devops/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="devops"
PROFILE_CLASS="WRENCH-MAGE"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"
PROFILE_TAG="speaks fluent YAML · has opinions about Kubernetes — strong ones"
PROFILE_FLAIR="terraform plans before breakfast · helm charts after"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="devops-toolchain.sh"
PROFILE_KEY_TOOLS="docker kubectl terraform helm ansible gh"
