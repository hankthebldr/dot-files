# MacBook Pro CLI Poweruser Setup
## Comprehensive Developer & InfoSec Workstation Configuration

**System Audit Results:**
- macOS: 26.1 (25B77)
- Shell: zsh
- Homebrew: 4.6.20
- Python: 3.14.0
- Docker: 28.5.2
- Git: 2.51.2

---

## 🎯 Strategy Overview

This setup transforms your MacBook Pro into an elite development and security research workstation with:
1. **Advanced Development Tools** - Multiple language runtimes, IDEs, and productivity tools
2. **Information Security Arsenal** - Penetration testing, network analysis, and forensics tools
3. **DevOps & Cloud Infrastructure** - Container orchestration, IaC, and cloud CLI tools
4. **Network Engineering** - Advanced networking, monitoring, and analysis capabilities
5. **System Optimization** - Performance tuning, shell enhancements, and automation

---

## 📦 Tool Categories & Installation Plan

### 1. SHELL & TERMINAL ENHANCEMENTS

#### Core Shell Tools
```bash
# Modern CLI replacements
brew install eza              # Modern ls replacement with icons
brew install fd               # Fast alternative to find
brew install ripgrep          # Ultra-fast grep alternative (rg)
brew install fzf              # Fuzzy finder for command history
brew install zoxide           # Smarter cd command (z)
brew install starship         # Minimal, fast shell prompt
brew install tmux             # Terminal multiplexer
brew install neovim           # Modern vim replacement

# Productivity & Utilities
brew install thefuck          # Corrects previous console command
brew install tldr             # Simplified man pages
brew install trash-cli        # Safer rm alternative
brew install tree             # Directory visualization
brew install watch            # Execute commands periodically
brew install htop             # Better top replacement
brew install glances          # System monitoring
brew install procs            # Modern ps replacement
```

#### Terminal Emulators & Multiplexers
```bash
brew install --cask iterm2    # Advanced terminal emulator
brew install --cask wezterm   # GPU-accelerated terminal
brew install zellij           # Modern tmux alternative
```

---

### 2. DEVELOPMENT TOOLS

#### Version Control & Collaboration
```bash
brew install gh               # GitHub CLI
brew install gitlab-runner    # GitLab CI/CD runner
brew install git-lfs          # Large file storage
brew install git-delta        # Better git diff
brew install lazygit          # Terminal UI for git
brew install tig              # Text-mode interface for git
brew install pre-commit       # Git hook framework
```

#### Programming Languages & Runtimes
```bash
# Node.js ecosystem
brew install node             # Node.js runtime
brew install nvm              # Node version manager
brew install yarn             # Package manager
brew install pnpm             # Fast package manager
brew install bun              # Fast all-in-one JS runtime

# Python ecosystem
brew install pyenv            # Python version manager
brew install pipenv           # Python package manager
brew install poetry           # Dependency management
brew install black            # Code formatter
brew install ruff             # Fast Python linter

# Go
brew install go               # Go language
brew install gopls            # Go language server

# Rust
brew install rust             # Rust language
brew install rust-analyzer    # Rust language server

# Java/JVM
brew install openjdk          # Java Development Kit
brew install maven            # Build automation
brew install gradle           # Build tool
brew install kotlin           # JVM language

# Ruby
brew install ruby             # Ruby language
brew install rbenv            # Ruby version manager

# Other languages
brew install elixir           # Functional language
brew install lua              # Scripting language
brew install r                # Statistical computing
brew install scala            # JVM language
```

#### Databases & Data Tools
```bash
brew install postgresql@16    # PostgreSQL database
brew install mysql            # MySQL database
brew install redis            # In-memory data store
brew install mongodb-community # MongoDB
brew install sqlite           # Lightweight database
brew install duckdb           # Analytical database
brew install mongosh          # MongoDB shell
brew install pgcli            # Better postgres CLI
brew install mycli            # Better mysql CLI
brew install litecli          # Better sqlite CLI
brew install usql             # Universal SQL CLI
```

#### API Development & Testing
```bash
brew install httpie           # Modern HTTP client
brew install curl             # HTTP client
brew install wget             # File downloader
brew install postman          # API testing (cask)
brew install --cask insomnia  # API client
brew install grpcurl          # gRPC curl
brew install websocat         # WebSocket client
```

#### Code Quality & Linting
```bash
brew install shellcheck       # Shell script linter
brew install hadolint         # Dockerfile linter
brew install yamllint         # YAML linter
brew install jsonlint         # JSON linter
brew install tflint           # Terraform linter
brew install eslint           # JavaScript linter
brew install markdownlint-cli # Markdown linter
```

---

### 3. INFORMATION SECURITY TOOLS

#### Network Reconnaissance & Scanning
```bash
brew install nmap             # Network scanner
brew install masscan          # Fast port scanner
brew install zmap             # Network scanner
brew install rustscan         # Modern port scanner
brew install angry-ip-scanner # IP/port scanner (cask)
brew install netcat           # Network utility
brew install socat            # Socket relay
brew install ncat             # Nmap's netcat
```

#### Web Application Security
```bash
brew install nikto            # Web server scanner
brew install sqlmap           # SQL injection tool
brew install dirb             # Web content scanner
brew install gobuster         # Directory brute-forcer
brew install ffuf             # Fast web fuzzer
brew install wfuzz            # Web fuzzer
brew install nuclei           # Vulnerability scanner
brew install whatweb          # Web scanner
brew install wafw00f          # WAF fingerprinting
brew install commix           # Command injection tool
```

#### Password & Hash Tools
```bash
brew install hashcat          # Password cracker
brew install john-jumbo       # John the Ripper
brew install hydra            # Network login cracker
brew install crunch           # Wordlist generator
brew install hashcat-utils    # Hashcat utilities
brew install hash-identifier  # Hash type identifier
```

#### Network Analysis & Sniffing
```bash
brew install --cask wireshark # Network protocol analyzer
brew install tcpdump          # Packet analyzer
brew install tshark           # Terminal wireshark
brew install tcpflow          # TCP flow analyzer
brew install ngrep            # Network grep
brew install dsniff           # Network auditing tools
brew install ettercap         # Network security tool
brew install bettercap        # Network attack framework
brew install mitmproxy        # HTTP proxy
brew install burp-suite       # Web security testing (cask)
```

#### Wireless Security
```bash
brew install aircrack-ng      # WiFi security toolkit
brew install kismet           # Wireless detector
brew install reaver           # WPS cracker
brew install bully            # WPS brute force
```

#### Exploitation & Post-Exploitation
```bash
brew install metasploit       # Exploitation framework
brew install exploit-db       # Exploit database
brew install searchsploit     # Exploit-DB CLI
brew install armitage         # Metasploit GUI (cask)
brew install powershell       # PowerShell for macOS
brew install pwntools         # CTF framework
```

#### Forensics & Reverse Engineering
```bash
brew install binwalk          # Firmware analysis
brew install foremost         # File carving
brew install volatility       # Memory forensics
brew install ghidra           # Reverse engineering (cask)
brew install radare2          # Reverse engineering
brew install rizin            # Radare2 fork
brew install hopper           # Disassembler (cask)
brew install xxd              # Hex dump utility
brew install hexyl            # Modern hex viewer
brew install strings          # Extract strings
brew install exiftool         # Metadata tool
```

#### Cryptography & Encoding
```bash
brew install gnupg            # GPG encryption
brew install openssl          # SSL/TLS toolkit
brew install age              # Modern encryption
brew install sops             # Secrets encryption
brew install base64           # Encoding utility
brew install jwt-cli          # JWT decoder
```

#### SSL/TLS Analysis
```bash
brew install testssl          # SSL/TLS scanner
brew install sslyze           # SSL analyzer
brew install sslscan          # SSL scanner
```

#### Container Security
```bash
brew install trivy            # Container vulnerability scanner
brew install grype            # Vulnerability scanner
brew install syft             # SBOM generator
brew install cosign           # Container signing
brew install docker-bench-security # Docker security
```

---

### 4. DEVOPS & CLOUD INFRASTRUCTURE

#### Container & Orchestration
```bash
brew install docker           # Container platform
brew install docker-compose   # Multi-container apps
brew install podman           # Daemonless container engine
brew install kubernetes-cli   # kubectl
brew install k9s              # Kubernetes TUI
brew install kubectx          # Kubernetes context switcher
brew install helm             # Kubernetes package manager
brew install minikube         # Local Kubernetes
brew install kind             # Kubernetes in Docker
brew install k3d              # K3s in Docker
brew install skaffold         # Kubernetes dev tool
brew install stern            # Multi-pod log tailing
brew install kustomize        # Kubernetes customization
```

#### Infrastructure as Code
```bash
brew install terraform        # Infrastructure provisioning
brew install terragrunt       # Terraform wrapper
brew install ansible          # Configuration management
brew install packer           # Image builder
brew install vagrant          # VM manager
brew install pulumi           # Modern IaC
```

#### Cloud CLI Tools
```bash
brew install awscli           # AWS CLI (already installed)
brew install aws-vault        # AWS credential manager
brew install azure-cli        # Azure CLI
brew install google-cloud-sdk # GCP CLI (already installed)
brew install doctl            # DigitalOcean CLI
brew install linode-cli       # Linode CLI
brew install heroku           # Heroku CLI
```

#### CI/CD & Automation
```bash
brew install jenkins          # Automation server
brew install circleci         # CircleCI CLI
brew install act              # Run GitHub Actions locally
brew install drone            # CI/CD platform
brew install buildkit         # Docker build engine
```

#### Monitoring & Observability
```bash
brew install prometheus       # Monitoring system
brew install grafana          # Visualization platform
brew install telegraf         # Metrics agent
brew install influxdb         # Time series database
brew install elasticsearch    # Search engine
brew install logstash         # Log pipeline
brew install kibana           # Visualization (cask)
brew install datadog-agent    # Monitoring agent
```

---

### 5. NETWORKING & SYSTEMS

#### Network Tools
```bash
brew install ipcalc           # IP calculator
brew install whois            # Domain lookup
brew install dig              # DNS lookup
brew install nslookup         # DNS query
brew install host             # DNS lookup
brew install mtr              # Network diagnostic
brew install iperf3           # Network performance
brew install speedtest-cli    # Internet speed test
brew install bandwhich        # Bandwidth monitor
brew install gping            # Ping with graph
brew install dog              # Modern dig
brew install aria2            # Download utility
```

#### System Utilities
```bash
brew install coreutils        # GNU core utilities
brew install findutils        # GNU find utilities
brew install gnu-sed          # GNU sed
brew install gnu-tar          # GNU tar
brew install gawk             # GNU awk
brew install grep             # GNU grep
brew install gzip             # Compression
brew install xz               # Compression
brew install p7zip            # 7-Zip compression
brew install unrar            # RAR extraction
brew install pigz             # Parallel gzip
```

#### Process & Resource Management
```bash
brew install bottom           # System monitor (btm)
brew install btop             # Already installed
brew install ncdu             # Disk usage analyzer
brew install duf              # Modern df
brew install dust             # Modern du
brew install hyperfine        # Benchmarking tool
```

---

### 6. DATA PROCESSING & ANALYSIS

#### Text & Data Processing
```bash
brew install jq               # JSON processor
brew install yq               # YAML processor
brew install xq               # XML processor
brew install csvkit           # CSV toolkit
brew install miller           # CSV/JSON processor
brew install xmlstarlet       # XML processor
brew install pandoc           # Document converter
brew install grex             # Regex generator
```

#### Data Transfer & Sync
```bash
brew install rsync            # File sync
brew install rclone           # Cloud storage sync
brew install syncthing        # Continuous sync
brew install restic           # Backup program
brew install borg             # Deduplicating backup
```

---

### 7. ADDITIONAL POWER TOOLS

#### Productivity
```bash
brew install maccy            # Clipboard manager (cask)
brew install rectangle        # Window manager (cask)
brew install karabiner-elements # Keyboard customizer (cask)
brew install alfred           # Productivity app (cask)
brew install notion           # Note-taking (cask)
```

#### Documentation & Reading
```bash
brew install cheat            # Cheatsheets
brew install howdoi           # Code answers
brew install man-db           # Manual pages
brew install mdcat            # Markdown viewer
brew install glow             # Markdown renderer
```

#### Virtualization
```bash
brew install --cask utm       # Virtual machines
brew install --cask virtualbox # VM platform
brew install qemu             # Emulator
```

---

## 🔧 SHELL CONFIGURATION OPTIMIZATION

### ZSH Enhancements

Install Oh My Zsh or alternatives:
```bash
# Oh My Zsh (popular)
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# OR Zinit (faster)
bash -c "$(curl --fail --show-error --silent --location https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)"

# OR Antibody (simple)
brew install getantibody/tap/antibody
```

### Essential ZSH Plugins
```bash
# Via Oh My Zsh
plugins=(
  git
  docker
  kubectl
  terraform
  aws
  gcloud
  python
  poetry
  rust
  golang
  npm
  yarn
  sudo
  command-not-found
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf
  autojump
  z
  you-should-use
)
```

### Install Additional Plugins
```bash
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use
```

---

## ⚙️ SYSTEM OPTIMIZATIONS

### Performance Tweaks
```bash
# Disable spotlight indexing for dev directories
sudo mdutil -i off ~/Projects

# Increase file descriptor limits
sudo launchctl limit maxfiles 65536 200000
ulimit -n 65536

# Optimize network settings
sudo sysctl -w net.inet.tcp.win_scale_factor=8
sudo sysctl -w kern.ipc.somaxconn=1024
```

### Security Hardening
```bash
# Enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Disable remote apple events
sudo systemsetup -setremoteappleevents off

# Require password immediately after sleep
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
```

---

## 🚀 AUTOMATED INSTALLATION SCRIPT

See `install-poweruser-tools.sh` for complete automated installation.

---

## 📚 RECOMMENDED CONFIGURATIONS

### ~/.zshrc Essential Additions
```bash
# Modern CLI replacements
alias ls='eza --icons --group-directories-first'
alias ll='eza -lah --icons --group-directories-first'
alias cat='bat'
alias find='fd'
alias grep='rg'
alias top='btop'
alias du='dust'
alias df='duf'
alias ps='procs'

# Safety nets
alias rm='trash'
alias cp='cp -iv'
alias mv='mv -iv'
alias mkdir='mkdir -pv'

# Navigation
eval "$(zoxide init zsh)"
alias cd='z'

# FZF integration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

# Better history
export HISTFILE=~/.zsh_history
export HISTSIZE=1000000
export SAVEHIST=1000000
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS
setopt HIST_REDUCE_BLANKS

# Starship prompt
eval "$(starship init zsh)"

# Atuin history sync
eval "$(atuin init zsh)"

# Path additions
export PATH="/opt/homebrew/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
```

### Git Configuration
```bash
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
git config --global delta.navigate true
git config --global delta.light false
git config --global merge.conflictstyle diff3
git config --global diff.colorMoved default
```

---

## 🔐 SECURITY BEST PRACTICES

1. **Use separate environments for testing/production**
2. **Enable FileVault encryption** (System Preferences → Security)
3. **Use 1Password/Bitwarden** for password management
4. **Enable 2FA** on all critical accounts
5. **Regular backups** with Time Machine + cloud backup
6. **Keep tools updated**: `brew update && brew upgrade`
7. **Use VPN** for public networks
8. **Separate user accounts** for different security contexts
9. **Monitor system logs**: `log stream --predicate 'process == "sudo"'`
10. **Regular security audits**: `brew audit --strict`

---

## 📊 MAINTENANCE COMMANDS

```bash
# Update everything
brew update && brew upgrade && brew cleanup

# Check system health
brew doctor

# Remove old versions
brew cleanup -s

# Audit installed packages
brew audit --installed

# List outdated packages
brew outdated

# Security audit
brew audit --strict --online

# Check for broken symlinks
brew cleanup --prune=all
```

---

## 🎓 LEARNING RESOURCES

- **TryHackMe**: Hands-on security training
- **HackTheBox**: Penetration testing labs
- **OverTheWire**: Wargames
- **OWASP**: Security standards
- **Kubernetes Docs**: Container orchestration
- **AWS Workshops**: Cloud infrastructure
- **GitHub Learning Lab**: DevOps practices

---

## 📝 NEXT STEPS

1. Run the installation script
2. Configure shell (zsh plugins, aliases)
3. Set up development environments (Node, Python, Go)
4. Configure security tools
5. Test homelab setup
6. Create custom automation scripts
7. Set up monitoring and logging
8. Document your workflows

---

**Generated**: 2025-11-05
**System**: macOS 26.1
**Target Audience**: Developers, InfoSec Professionals, System Administrators
