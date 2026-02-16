# shell/security.zsh
# Security-focused aliases and safety nets

# 1. Network Recon & Safety
alias ports='lsof -i -P -n | grep LISTEN'
alias myip='curl -s https://ifconfig.me'
alias ipinfo='curl -s https://ipinfo.io'

# 2. Safe file operations
# Prevent accidental overwrites
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'
alias ln='ln -iv'

# 3. Permissions checks
alias checkperms='stat -f "%OLp %N"'
alias fixperms='chmod 644'
alias fixdirperms='chmod 755'

# 4. Security Tools Shortcuts
alias scan='nmap -T4 -F'
alias scan-full='nmap -T4 -A -v'
alias trivy-fs='trivy fs .'
alias trivy-img='trivy image'
alias grype-fs='grype dir:.'
alias grype-img='grype'

# 5. Crypto / Hashing
alias sha256='shasum -a 256'
alias sha512='shasum -a 512'
alias verify='gpg --verify'

# 6. Randomness (Password Gen)
alias pwgen='openssl rand -base64 20'
alias pwgen-strong='openssl rand -base64 32'
