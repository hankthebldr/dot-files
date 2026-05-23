# shell/profiles/cloud.zsh — dispatcher (per-OS sub-files in cloud/)
# See docs/profiles/architecture.md for the pattern.
_PROFILE_DIR="${0:A:h}/cloud"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
