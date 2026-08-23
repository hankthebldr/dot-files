# shell/profiles/ai/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="ai"
PROFILE_CLASS="NEUROMANCER"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="prompted their way out of a parking ticket · 70B model on a thumb drive"
PROFILE_FLAIR="Ollama serving · vLLM warming · langchain debugging itself"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# local weights + notebooks; created by common.zsh
PROFILE_START_DIR="${AI_WORKSPACE:-$HOME/ai_models}"

# OS SUPPORT
# All 7 migrated profiles are cross-platform via platform.zsh shims.
# Mac/Linux-specific bits (if any emerge) live in mac.zsh / linux.zsh.
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="ai-toolchain.sh"
PROFILE_KEY_TOOLS="ollama llama-cli python3 pipx"
