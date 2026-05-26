# shell/profiles/vault.zsh — dispatcher (per-OS sub-files in vault/)
# Builds on top of the global shell/obsidian.zsh module — see
# docs/profiles/architecture.md for the dispatcher pattern.
_PROFILE_DIR="${0:A:h}/vault"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
