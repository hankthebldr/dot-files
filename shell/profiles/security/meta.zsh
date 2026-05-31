# shell/profiles/security/meta.zsh
# Profile metadata — see docs/profiles/architecture.md for schema.

# IDENTITY
PROFILE_NAME="security"
PROFILE_HELP_CMD="sec-help"   # help card is sec-help, not security-help
PROFILE_CLASS="NIGHTHACKER"
PROFILE_TIER="2"

# VISUAL IDENTITY
PROFILE_THEME_DEFAULT="matrix"
PROFILE_TAG="thinks your password is cute"
PROFILE_FLAIR="has been in your router since Tuesday"

# OS SUPPORT
# Linux (especially Parrot/Kali) has the strongest native tooling story;
# Mac runs the same toolkit via Homebrew with a few package-name differences
# (netcat vs ncat, john-jumbo vs john).
PROFILE_OS_SUPPORT="mac+linux"

# INSTALL TOOLING
PROFILE_TOOLCHAIN="security-toolchain.sh"
PROFILE_KEY_TOOLS="nmap sqlmap hashcat hydra ffuf gobuster nikto trivy msfconsole tshark binwalk"
