# shell/profiles/cortex.zsh — dispatcher (per-OS sub-files in cortex/)
# See docs/profiles/architecture.md for the dispatcher pattern.
_PROFILE_DIR="${0:A:h}/cortex"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
