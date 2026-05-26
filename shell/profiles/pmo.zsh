# shell/profiles/pmo.zsh — dispatcher (per-OS sub-files in pmo/)
_PROFILE_DIR="${0:A:h}/pmo"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
