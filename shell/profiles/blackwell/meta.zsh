# shell/profiles/blackwell/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="blackwell"
PROFILE_CLASS="PHOSPHOR-GHOST"
PROFILE_TIER="6"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="has a 70B model on a thumb drive · runs the bigger ones too"
PROFILE_FLAIR="FP4 enabled · 24GB VRAM · Tensor cores warm"

# OS SUPPORT — cockpit pattern:
#   mac   → remote — SSH wrappers for nvtop, vLLM submit, model registry
#   linux → native — direct GPU monitor, vLLM serve, training launchers
PROFILE_OS_SUPPORT="mac=remote, linux=native"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="ai-workstation-toolchain.sh"     # Linux-only — NVIDIA R570+, CUDA 12.8, vLLM, etc.
PROFILE_KEY_TOOLS="nvidia-smi nvtop vllm llama-cli ollama"
