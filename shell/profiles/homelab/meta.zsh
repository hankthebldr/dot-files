# shell/profiles/homelab/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="homelab"
PROFILE_CLASS="RACK-WIZARD"
PROFILE_TIER="6"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="owns the BD790i and its 47 unread alerts"
PROFILE_FLAIR="k3s · tailscale · gitea · n8n · ollama — all on one mini-PC"

# START DIRECTORY
# Where `claw load` / a welcome-TUI pick drops you. Grammar + precedence:
# shell/profile-helpers.zsh (@vault tokens, `|` candidates, empty = stay put).
# the compose/k3s manifests you actually edit during ops
PROFILE_START_DIR="${HOMELAB_REPO:-$HOME/homelab}"

# OS SUPPORT — first profile with split semantics:
#   mac   → cockpit mode: SSH wrappers, status panes, remote command launchers
#   linux → native mode: direct K3s/Tailscale/Docker daemon control
PROFILE_OS_SUPPORT="mac=remote, linux=native"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="homelab-toolchain.sh"     # Linux-only (Tailscale, Docker, K3s, Ollama)
PROFILE_KEY_TOOLS="tailscale docker kubectl k3s ollama"
