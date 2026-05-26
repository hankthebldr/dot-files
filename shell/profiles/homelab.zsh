# shell/profiles/homelab.zsh — dispatcher (per-OS sub-files in homelab/)
# BD790i operations. mac=remote (SSH wrappers), linux=native (direct daemons).
# See docs/profiles/architecture.md.
_PROFILE_DIR="${0:A:h}/homelab"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
