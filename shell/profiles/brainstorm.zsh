# shell/profiles/brainstorm.zsh — dispatcher (per-OS sub-files in brainstorm/)
_PROFILE_DIR="${0:A:h}/brainstorm"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
