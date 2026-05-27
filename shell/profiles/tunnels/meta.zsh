# shell/profiles/tunnels/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="tunnels"
PROFILE_CLASS="PORT-RUNNER"
PROFILE_TIER="6"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="every host is one port-forward away · multi-hop with the right key"
PROFILE_FLAIR="ControlMaster sockets · Tailscale subnets · SOCKS routes"

# OS SUPPORT — full parity. SSH + Tailscale work identically on both;
# OS divergence is just nice-to-have integrations (pbcopy on Mac, wg on Linux).
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN=""     # no new toolchain — uses ssh + tailscale (already present)
PROFILE_KEY_TOOLS="ssh tailscale yq fzf"
