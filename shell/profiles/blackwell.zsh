# shell/profiles/blackwell.zsh — dispatcher (per-OS sub-files in blackwell/)
# GPU/ML on BD790i Blackwell card. mac=remote (SSH+nvtop wrappers), linux=native.
# See docs/profiles/architecture.md.
_PROFILE_DIR="${0:A:h}/blackwell"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
