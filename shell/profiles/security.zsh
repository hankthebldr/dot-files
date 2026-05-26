# shell/profiles/security.zsh — dispatcher (per-OS sub-files in security/)
# See docs/profiles/architecture.md for the pattern.
_PROFILE_DIR="${0:A:h}/security"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
