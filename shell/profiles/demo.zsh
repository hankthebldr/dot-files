# shell/profiles/demo.zsh — dispatcher (per-OS sub-files in demo/)
# Presales mode: customer-safe terminal, clean prompt, clipboard scrub,
# screen recording, DND. See docs/profiles/architecture.md for the pattern.
_PROFILE_DIR="${0:A:h}/demo"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
