# shell/profiles/tunnels.zsh — dispatcher (per-OS sub-files in tunnels/)
# SSH ControlMaster · Tailscale subnet routes · SOCKS · ASCII topology.
# Wraps scripts/utils/tunnel-manager.sh. See docs/profiles/architecture.md.
_PROFILE_DIR="${0:A:h}/tunnels"
source "${_PROFILE_DIR}/meta.zsh"
source "${_PROFILE_DIR}/common.zsh"
[[ -f "${_PROFILE_DIR}/${OS_FAMILY}.zsh" ]] && source "${_PROFILE_DIR}/${OS_FAMILY}.zsh"
