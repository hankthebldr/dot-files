# Quick Start Guide - MacBook Pro Poweruser Setup

## 🚀 Getting Started

Your comprehensive poweruser setup is ready! Follow these steps to transform your MacBook Pro into an elite development and security workstation.

---

## 📋 What You Have

1. **macbook-pro-poweruser-setup.md** - Complete documentation of all tools and configurations
2. **install-poweruser-tools.sh** - Automated installation script
3. **zshrc-poweruser-additions.sh** - Shell configuration enhancements
4. **security-hardening.sh** - Security hardening script
5. **starship.toml** - Modern shell prompt configuration
6. **.ripgreprc** - Ripgrep search configuration

---

## ⚡ Quick Installation (Recommended)

### Step 1: Install All Tools (Takes 30-60 minutes)
```bash
cd ~
bash install-poweruser-tools.sh all
```

Or install specific categories:
```bash
bash install-poweruser-tools.sh shell     # Shell enhancements only
bash install-poweruser-tools.sh dev       # Development tools only
bash install-poweruser-tools.sh security  # Security tools only
bash install-poweruser-tools.sh devops    # DevOps tools only
bash install-poweruser-tools.sh network   # Network tools only
bash install-poweruser-tools.sh data      # Data processing tools only
```

### Step 2: Configure Shell
```bash
# Backup your current .zshrc
cp ~/.zshrc ~/.zshrc.backup

# Apply poweruser configurations
bash zshrc-poweruser-additions.sh
```

### Step 3: Install Starship Prompt
```bash
# Move starship config to correct location
mkdir -p ~/.config
mv ~/starship.toml ~/.config/starship.toml

# Reload shell
source ~/.zshrc
```

### Step 4: Security Hardening (Optional but Recommended)
```bash
bash security-hardening.sh
```

---

## 🎯 Essential First Commands

After installation, try these commands:

### Modern CLI Tools
```bash
# Directory listing with icons
ll

# Interactive file search
fd <pattern> | fzf

# Fast code search
rg "function" --type js

# System monitoring
btop

# Directory navigation
z <partial-path>  # Jump to frequently used directories

# Git with better diff
git diff  # Uses delta for colorized output
```

### Development
```bash
# Check installed languages
node --version
python3 --version
go version
rustc --version

# Start a quick HTTP server
serve 8080

# API testing
http GET https://api.github.com/users/github
```

### Security Tools
```bash
# Quick port scan
nmap -T4 -F <target>

# Web application scan
whatweb <url>

# Network capture
sudo tcpdump -i any -n

# Container vulnerability scan
trivy image <image-name>

# SSL/TLS test
testssl.sh <domain>
```

### Kubernetes & Docker
```bash
# Quick container status
d ps

# Kubernetes pods
k get pods

# Interactive Kubernetes dashboard
k9s

# Switch Kubernetes context
kubectx
```

---

## 📚 Key Aliases & Functions

### Navigation
- `..` - Go up one directory
- `...` - Go up two directories
- `proj` - Go to ~/Projects
- `z <partial>` - Jump to frequently used directory

### File Operations
- `ll` - Detailed listing with icons
- `lt` - Tree view
- `cat <file>` - Syntax highlighted file viewing
- `find <pattern>` - Fast file finding

### Git
- `g` - git
- `gst` - git status
- `gc` - git commit
- `gp` - git push
- `gl` - pretty git log

### Docker & Kubernetes
- `d` - docker
- `dc` - docker-compose
- `k` - kubectl
- `kgp` - kubectl get pods
- `kctx` - switch kubernetes context

### System
- `sysinfo` - Display system information
- `ports` - Show listening ports
- `myip` - Show public IP
- `speedtest` - Test internet speed

### Custom Functions
- `mkcd <dir>` - Create and enter directory
- `extract <file>` - Extract any archive
- `backup <file>` - Create timestamped backup
- `serve [port]` - Start HTTP server (default 8000)
- `weather [city]` - Show weather
- `cheat <command>` - Show command cheatsheet
- `json <file>` - Pretty print JSON
- `portcheck <host> <port>` - Check if port is open

---

## 🔧 Post-Installation Configuration

### 1. Configure Git
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
git config --global core.pager "delta"
git config --global interactive.diffFilter "delta --color-only"
```

### 2. Set Up SSH Keys
```bash
# Generate new SSH key
ssh-keygen -t ed25519 -C "your.email@example.com"

# Start ssh-agent
eval "$(ssh-agent -s)"

# Add key to agent
ssh-add ~/.ssh/id_ed25519

# Copy public key to clipboard
cat ~/.ssh/id_ed25519.pub | pbcopy
```

### 3. Configure GPG for Git Signing
```bash
# Generate GPG key
gpg --full-generate-key

# List keys
gpg --list-secret-keys --keyid-format LONG

# Configure git to use GPG
git config --global user.signingkey <your-key-id>
git config --global commit.gpgsign true
```

### 4. Set Up Python Environment
```bash
# Install Python versions
pyenv install 3.11.0
pyenv install 3.12.0
pyenv global 3.12.0

# Create virtual environment
python -m venv ~/.venv/default
source ~/.venv/default/bin/activate
```

### 5. Set Up Node.js
```bash
# Install Node versions
nvm install 20
nvm install 18
nvm use 20
nvm alias default 20

# Install global packages
npm install -g typescript ts-node prettier eslint
```

### 6. Configure Docker
```bash
# Start Docker Desktop (if installed as cask)
# Or ensure Docker daemon is running

# Test Docker
docker run hello-world

# Configure Docker BuildKit
export DOCKER_BUILDKIT=1
echo "export DOCKER_BUILDKIT=1" >> ~/.zshrc
```

### 7. Set Up Kubernetes
```bash
# Create kubeconfig directory
mkdir -p ~/.kube

# Install kubectl plugins via krew (optional)
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
```

---

## 🔐 Security Best Practices

### Essential Security Steps

1. **Enable FileVault**
   - System Preferences → Security & Privacy → FileVault
   - Turn On FileVault

2. **Install Password Manager**
   ```bash
   brew install --cask 1password
   # OR
   brew install --cask bitwarden
   ```

3. **Set Up VPN**
   ```bash
   brew install --cask mullvadvpn
   # OR
   brew install wireguard-tools
   ```

4. **Enable Firewall** (done by security-hardening.sh)
   - Verify: System Preferences → Security & Privacy → Firewall

5. **Regular Updates**
   ```bash
   # Create alias for full system update
   alias sysupdate='sudo softwareupdate -i -a && brew update && brew upgrade && brew cleanup'
   ```

### Security Monitoring

```bash
# Check listening ports
sudo lsof -iTCP -sTCP:LISTEN -n -P

# Monitor sudo usage
log stream --predicate 'process == "sudo"'

# Check for rootkits (install rkhunter)
brew install rkhunter
sudo rkhunter --check

# Audit Homebrew packages
brew audit --strict --installed
```

---

## 🏠 Home Lab Setup Ideas

### 1. Local Kubernetes Cluster
```bash
# Start minikube
minikube start --cpus=4 --memory=8192

# Or use k3d for lightweight cluster
k3d cluster create dev --agents 2
```

### 2. Local Docker Registry
```bash
docker run -d -p 5000:5000 --restart=always --name registry registry:2
```

### 3. Monitoring Stack
```bash
# Prometheus + Grafana with docker-compose
mkdir ~/monitoring && cd ~/monitoring
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  prometheus:
    image: prom/prometheus
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
EOF

docker-compose up -d
```

### 4. Development Databases
```bash
# PostgreSQL
docker run -d --name postgres -e POSTGRES_PASSWORD=dev -p 5432:5432 postgres:16

# Redis
docker run -d --name redis -p 6379:6379 redis:latest

# MongoDB
docker run -d --name mongo -p 27017:27017 mongo:latest
```

### 5. Pentesting Lab
```bash
# Metasploitable (vulnerable VM for practice)
# DVWA (Damn Vulnerable Web Application)
docker run -d -p 80:80 vulnerables/web-dvwa

# Juice Shop (OWASP vulnerable app)
docker run -d -p 3000:3000 bkimminich/juice-shop
```

---

## 📊 Performance Optimization

### System Tweaks (Already Applied)
```bash
# Verify file descriptor limits
ulimit -n

# Check network settings
sysctl net.inet.tcp.win_scale_factor
sysctl kern.ipc.somaxconn
```

### Homebrew Optimization
```bash
# Regular maintenance
brew update
brew upgrade
brew cleanup -s
brew doctor

# Remove old versions
brew cleanup --prune=all
```

### Shell Performance
```bash
# Benchmark shell startup time
time zsh -i -c exit

# Profile zsh startup (if slow)
zsh -i -c 'zprof'
```

---

## 🎓 Learning Resources

### Command Line
- **Modern Unix**: https://github.com/ibraheemdev/modern-unix
- **The Art of Command Line**: https://github.com/jlevy/the-art-of-command-line
- **ExplainShell**: https://explainshell.com

### Security
- **TryHackMe**: https://tryhackme.com
- **HackTheBox**: https://hackthebox.com
- **OverTheWire**: https://overthewire.org
- **OWASP Top 10**: https://owasp.org/www-project-top-ten

### DevOps
- **Kubernetes Docs**: https://kubernetes.io/docs
- **Docker Docs**: https://docs.docker.com
- **Terraform Tutorials**: https://learn.hashicorp.com/terraform

### Development
- **DevDocs**: https://devdocs.io
- **GitHub Skills**: https://skills.github.com
- **freeCodeCamp**: https://freecodecamp.org

---

## 🔍 Troubleshooting

### Homebrew Issues
```bash
# Fix permissions
sudo chown -R $(whoami) $(brew --prefix)/*

# Reinstall Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Shell Issues
```bash
# Reset to default .zshrc
cp ~/.zshrc.backup ~/.zshrc
source ~/.zshrc

# Check for conflicts
zsh -x -i -c exit 2>&1 | less
```

### Tool Not Found
```bash
# Ensure Homebrew bin is in PATH
echo $PATH | grep homebrew

# Verify installation
brew list | grep <tool-name>

# Reinstall
brew reinstall <tool-name>
```

---

## 📝 Maintenance Schedule

### Daily
- Check for critical security updates
- Run `brewup` alias for updates

### Weekly
- Clean up old containers: `docker system prune`
- Review security logs
- Update development dependencies

### Monthly
- Full system backup
- Security audit with installed tools
- Review and update configurations
- Clean up unused packages: `brew cleanup`

---

## 🎯 Next Steps

1. ✅ Run installation script
2. ✅ Configure shell with poweruser additions
3. ✅ Apply security hardening
4. ⬜ Set up SSH and GPG keys
5. ⬜ Configure development environments
6. ⬜ Set up home lab services
7. ⬜ Create personal automation scripts
8. ⬜ Join security learning platforms
9. ⬜ Build and deploy first project
10. ⬜ Share your setup and contribute back!

---

## 💡 Pro Tips

1. **Use tmux/zellij** for persistent terminal sessions
2. **Create dotfiles repo** to version control your configurations
3. **Set up automated backups** with Time Machine + cloud storage
4. **Join communities**: /r/commandline, /r/netsec, DevOps communities
5. **Practice regularly** on CTF platforms
6. **Document your workflows** in personal wiki/notes
7. **Contribute to open source** tools you use daily
8. **Stay updated** with security newsletters and blogs

---

**Created**: 2025-11-05
**Version**: 1.0
**Maintained by**: You!

Happy hacking! 🚀
