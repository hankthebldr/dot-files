#!/usr/bin/env bash

# ============================================
# Install Missing CLI Optimization Tools
# For macOS Production Laptop
# ============================================

set -e

echo "🚀 Installing missing CLI optimization tools..."

# Check if Homebrew is installed
if ! command -v brew &> /dev/null; then
    echo "❌ Homebrew not found. Please install it first."
    exit 1
fi

echo "📦 Updating Homebrew..."
brew update

# ============================================
# Modern CLI Replacements
# ============================================

echo ""
echo "🔧 Installing modern CLI replacements..."

# Better ls (actively maintained fork of exa)
if ! command -v eza &> /dev/null; then
    echo "  → Installing eza (modern ls)..."
    brew install eza
else
    echo "  ✓ eza already installed"
fi

# Smarter cd
if ! command -v zoxide &> /dev/null; then
    echo "  → Installing zoxide (smarter cd)..."
    brew install zoxide
else
    echo "  ✓ zoxide already installed"
fi

# Better find
if ! command -v fd &> /dev/null; then
    echo "  → Installing fd (better find)..."
    brew install fd
else
    echo "  ✓ fd already installed"
fi

# Better du
if ! command -v dust &> /dev/null; then
    echo "  → Installing dust (better du)..."
    brew install dust
else
    echo "  ✓ dust already installed"
fi

# Better df
if ! command -v duf &> /dev/null; then
    echo "  → Installing duf (better df)..."
    brew install duf
else
    echo "  ✓ duf already installed"
fi

# Better ps
if ! command -v procs &> /dev/null; then
    echo "  → Installing procs (better ps)..."
    brew install procs
else
    echo "  ✓ procs already installed"
fi

# Better sed
if ! command -v sd &> /dev/null; then
    echo "  → Installing sd (better sed)..."
    brew install sd
else
    echo "  ✓ sd already installed"
fi

# ============================================
# Development Tools
# ============================================

echo ""
echo "💻 Installing development tools..."

# Neovim
if ! command -v nvim &> /dev/null; then
    echo "  → Installing neovim..."
    brew install neovim
else
    echo "  ✓ neovim already installed"
fi

# LazyGit
if ! command -v lazygit &> /dev/null; then
    echo "  → Installing lazygit..."
    brew install lazygit
else
    echo "  ✓ lazygit already installed"
fi

# LazyDocker
if ! command -v lazydocker &> /dev/null; then
    echo "  → Installing lazydocker..."
    brew install lazydocker
else
    echo "  ✓ lazydocker already installed"
fi

# ============================================
# Productivity Tools
# ============================================

echo ""
echo "⚡ Installing productivity tools..."

# Starship prompt (cross-platform)
if ! command -v starship &> /dev/null; then
    echo "  → Installing starship..."
    brew install starship
else
    echo "  ✓ starship already installed"
fi

# Interactive cheatsheet
if ! command -v navi &> /dev/null; then
    echo "  → Installing navi..."
    brew install navi
else
    echo "  ✓ navi already installed"
fi

# Shell history sync
if ! command -v atuin &> /dev/null; then
    echo "  → Installing atuin..."
    brew install atuin
else
    echo "  ✓ atuin already installed"
fi

# Per-directory env vars
if ! command -v direnv &> /dev/null; then
    echo "  → Installing direnv..."
    brew install direnv
else
    echo "  ✓ direnv already installed"
fi

# Command runner (better make)
if ! command -v just &> /dev/null; then
    echo "  → Installing just..."
    brew install just
else
    echo "  ✓ just already installed"
fi

# Benchmarking tool
if ! command -v hyperfine &> /dev/null; then
    echo "  → Installing hyperfine..."
    brew install hyperfine
else
    echo "  ✓ hyperfine already installed"
fi

# Markdown renderer
if ! command -v glow &> /dev/null; then
    echo "  → Installing glow..."
    brew install glow
else
    echo "  ✓ glow already installed"
fi

# GNU stow for dotfile management
if ! command -v stow &> /dev/null; then
    echo "  → Installing stow..."
    brew install stow
else
    echo "  ✓ stow already installed"
fi

# ============================================
# Kubernetes & Container Tools
# ============================================

echo ""
echo "☸️  Installing Kubernetes & Container tools..."

# K9s - Kubernetes TUI
if ! command -v k9s &> /dev/null; then
    echo "  → Installing k9s (Kubernetes TUI)..."
    brew install k9s
else
    echo "  ✓ k9s already installed"
fi

# kubectx and kubens - context/namespace switching
if ! command -v kubectx &> /dev/null; then
    echo "  → Installing kubectx & kubens..."
    brew install kubectx
else
    echo "  ✓ kubectx already installed"
fi

# Stern - multi-pod log tailing
if ! command -v stern &> /dev/null; then
    echo "  → Installing stern..."
    brew install stern
else
    echo "  ✓ stern already installed"
fi

# Kustomize - Kubernetes manifest management
if ! command -v kustomize &> /dev/null; then
    echo "  → Installing kustomize..."
    brew install kustomize
else
    echo "  ✓ kustomize already installed"
fi

# ============================================
# Infrastructure as Code
# ============================================

echo ""
echo "🏗️  Installing Infrastructure as Code tools..."

# Ansible
if ! command -v ansible &> /dev/null; then
    echo "  → Installing ansible..."
    brew install ansible
else
    echo "  ✓ ansible already installed"
fi

# Packer
if ! command -v packer &> /dev/null; then
    echo "  → Installing packer..."
    brew install packer
else
    echo "  ✓ packer already installed"
fi

# ============================================
# Security & Scanning Tools
# ============================================

echo ""
echo "🔒 Installing security tools..."

# Trivy - vulnerability scanner
if ! command -v trivy &> /dev/null; then
    echo "  → Installing trivy..."
    brew install trivy
else
    echo "  ✓ trivy already installed"
fi

# Grype - vulnerability scanner
if ! command -v grype &> /dev/null; then
    echo "  → Installing grype..."
    brew install grype
else
    echo "  ✓ grype already installed"
fi

# Age - modern encryption tool
if ! command -v age &> /dev/null; then
    echo "  → Installing age..."
    brew install age
else
    echo "  ✓ age already installed"
fi

# SOPS - secrets management
if ! command -v sops &> /dev/null; then
    echo "  → Installing sops..."
    brew install sops
else
    echo "  ✓ sops already installed"
fi

# ============================================
# Data Processing & APIs
# ============================================

echo ""
echo "📊 Installing data processing tools..."

# yq - YAML processor
if ! command -v yq &> /dev/null; then
    echo "  → Installing yq..."
    brew install yq
else
    echo "  ✓ yq already installed"
fi

# HTTPie - better HTTP client
if ! command -v http &> /dev/null; then
    echo "  → Installing httpie..."
    brew install httpie
else
    echo "  ✓ httpie already installed"
fi

# ============================================
# System Monitoring & Utilities
# ============================================

echo ""
echo "📈 Installing system utilities..."

# ncdu - disk usage analyzer
if ! command -v ncdu &> /dev/null; then
    echo "  → Installing ncdu..."
    brew install ncdu
else
    echo "  ✓ ncdu already installed"
fi

# watch - execute commands periodically
if ! command -v watch &> /dev/null; then
    echo "  → Installing watch..."
    brew install watch
else
    echo "  ✓ watch already installed"
fi

# entr - run commands when files change
if ! command -v entr &> /dev/null; then
    echo "  → Installing entr..."
    brew install entr
else
    echo "  ✓ entr already installed"
fi

# ============================================
# Terminal Emulators (Optional)
# ============================================

echo ""
echo "🖥️  Checking terminal emulators..."

# Kitty (for Gruvbox theme)
if ! brew list --cask kitty &> /dev/null; then
    echo "  → Kitty not installed. Install with: brew install --cask kitty"
    read -p "    Install kitty now? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew install --cask kitty
    fi
else
    echo "  ✓ kitty already installed"
fi

# ============================================
# Finalize
# ============================================

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Add this line to your ~/.zshrc:"
echo "     source ~/Github/Github_desktop/dot-files/aliases.zsh"
echo ""
echo "  2. Configure tool integrations:"
echo "     - zoxide: Add to .zshrc: eval \"\$(zoxide init zsh)\""
echo "     - starship: Add to .zshrc: eval \"\$(starship init zsh)\""
echo "     - direnv: Add to .zshrc: eval \"\$(direnv hook zsh)\""
echo "     - atuin: Add to .zshrc: eval \"\$(atuin init zsh)\""
echo ""
echo "  3. Reload shell: source ~/.zshrc"
echo ""
echo "  4. Update aliases in aliases.zsh to use new tools:"
echo "     - ls -> eza"
echo "     - cd -> z (zoxide)"
echo "     - find -> fd"
echo ""
