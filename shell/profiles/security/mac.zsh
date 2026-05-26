# shell/profiles/security/mac.zsh — macOS-specific security profile

# Homebrew installs SecLists to /usr/local/share/wordlists/SecLists (Intel)
# or /opt/homebrew/share/wordlists/SecLists (Apple Silicon). The security
# toolchain installer follows the brew prefix; we just point at the prefix.
if [[ -d "/opt/homebrew/share/wordlists/SecLists" ]]; then
    export WORDLISTS="/opt/homebrew/share/wordlists/SecLists"
elif [[ -d "/usr/local/share/wordlists/SecLists" ]]; then
    export WORDLISTS="/usr/local/share/wordlists/SecLists"
fi

# On macOS, `nc` is the BSD netcat from base system — no special handling.
# `listen` alias from common.zsh works as-is.

_security_install_hint() {
    case "$1" in
        nmap|sqlmap|hashcat|hydra|ffuf|gobuster|nikto|trivy|grype)
            echo "brew install $1"
            ;;
        metasploit)
            echo "see scripts/install/security-toolchain.sh (Rapid7 omnibus)"
            ;;
        wireshark)
            echo "brew install --cask wireshark"
            ;;
        *)
            echo "claw install security"
            ;;
    esac
}
