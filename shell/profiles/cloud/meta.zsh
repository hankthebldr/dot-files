# shell/profiles/cloud/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="cloud"
PROFILE_CLASS="SKYSURFER"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="synthwave"
PROFILE_TAG="boots up clusters before breakfast"
PROFILE_FLAIR="owns 4 TLDs you've never heard of"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# IaC working tree if you keep one, else the vault's cloud notes
PROFILE_START_DIR="${CLOUD_WORKSPACE:-$HOME/cloud}|@vault-folder"

# OS SUPPORT
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="cloud-toolchain.sh"
PROFILE_KEY_TOOLS="aws gcloud az kubectl helm terraform terragrunt k9s stern eksctl tfsec checkov jq"
