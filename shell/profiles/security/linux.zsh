# shell/profiles/security/linux.zsh — Linux-specific security profile
# Parrot/Kali/Ubuntu all converge on /usr/share/wordlists/SecLists per the
# security-toolchain installer's path-resolution logic.

export WORDLISTS="${WORDLISTS:-/usr/share/wordlists/SecLists}"

# On Linux, `nc` may be the BSD netcat (-traditional) or ncat (nmap-ncat).
# Both behave the same for our `listen` alias's flags (`-lvnp`). If you need
# nmap-ncat features specifically, `which ncat` and call ncat directly.

_security_install_hint() {
    case "$1" in
        nmap|sqlmap|hashcat|hydra|ffuf|gobuster|nikto)
            echo "sudo apt install $1"
            ;;
        wireshark)
            # tshark ships separately from the GUI; we probe for tshark anyway
            echo "sudo apt install tshark    # GUI: wireshark-qt"
            ;;
        metasploit)
            if [[ -f /etc/os-release ]] && command grep -qE '^ID=(parrot|kali)' /etc/os-release; then
                echo "sudo apt install metasploit-framework"
            else
                echo "see scripts/install/security-toolchain.sh (Rapid7 omnibus)"
            fi
            ;;
        trivy|grype)
            echo "see scripts/install/security-toolchain.sh (aqua/anchore vendor scripts)"
            ;;
        *)
            echo "claw install security"
            ;;
    esac
}
