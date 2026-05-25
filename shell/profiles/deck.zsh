# shell/profiles/deck.zsh — dispatcher (per-OS sub-files in deck/)
# Customer-facing artifacts: Cortex decks, marp slides, screenshots, GIFs.
# See docs/profiles/architecture.md for the dispatcher pattern.
_PROFILE_DIR="${0:A:h}/deck"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
