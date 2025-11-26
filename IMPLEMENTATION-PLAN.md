# Dot-Files Repository - Implementation Plan

## Overview

This document provides a step-by-step implementation plan to transform the current dot-files repository into a complete CLI configuration system.

## Phase-by-Phase Implementation

### Phase 1: Foundation & Directory Structure (2-3 hours)

#### Step 1.1: Create Directory Structure
```bash
# Create all directories
mkdir -p {shell,git,vim,tmux,terminal,tools,scripts/{install,backup,setup,utils},config/{ssh,aws,docker},docs,tests,legacy}

# Create subdirectories
mkdir -p vim/.config/nvim
mkdir -p terminal/{kitty,alacritty}
mkdir -p tools/.config/{bat,bottom,lazygit}
mkdir -p scripts/install/packages
```

**Files to create:**
- All directories listed in SETUP-STRATEGY.md

#### Step 1.2: Move Existing Files
```bash
# Move to legacy first (preserve originals)
mv activate-optimizations.sh legacy/
mv install-missing-tools.sh legacy/
mv dot-files-condensed legacy/

# Copy/adapt current files
cp aliases.zsh shell/aliases.zsh
cp cli-config/starship.toml terminal/starship.toml
```

**Files to move/copy:**
- `aliases.zsh` → `shell/aliases.zsh`
- `activate-optimizations.sh` → `legacy/`
- `install-missing-tools.sh` → `legacy/`
- `cli-config/starship.toml` → `terminal/starship.toml`
- Documentation files → `docs/`

#### Step 1.3: Create Core Dotfiles

**shell/.zshrc**
```bash
# Create modular .zshrc that sources other files
# - path.zsh (first)
# - exports.zsh
# - aliases.zsh
# - functions.zsh
# - Local overrides (~/.zshrc.local)
```

**git/.gitconfig**
```bash
# Core git configuration
# - User info (to be filled during setup)
# - Aliases
# - Delta integration
# - Sensible defaults
```

**tmux/.tmux.conf**
```bash
# Modern tmux configuration
# - Better key bindings
# - Mouse support
# - Status bar styling
# - Plugin support (TPM)
```

**vim/.vimrc**
```bash
# Sensible vim defaults
# - Plugin manager (vim-plug)
# - Basic plugins
# - Key mappings
```

**Deliverables:**
- Complete directory structure
- Core dotfiles created
- Existing files organized
- Legacy files preserved

---

### Phase 2: Utility Scripts (3-4 hours)

#### Step 2.1: OS Detection
**File:** `scripts/utils/detect-os.sh`

```bash
#!/usr/bin/env bash
# Detect operating system and set variables

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        PKG_MANAGER="brew"
    elif [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|parrot)
                OS_TYPE="$ID"
                PKG_MANAGER="apt"
                ;;
            fedora|rhel|centos)
                OS_TYPE="$ID"
                PKG_MANAGER="dnf"
                ;;
            arch|manjaro)
                OS_TYPE="$ID"
                PKG_MANAGER="pacman"
                ;;
        esac
    fi

    export OS_TYPE PKG_MANAGER
}
```

#### Step 2.2: Logging Functions
**File:** `scripts/utils/logger.sh`

```bash
#!/usr/bin/env bash
# Logging and output functions

log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_warning() { echo -e "\033[0;33m[WARNING]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*"; }
```

#### Step 2.3: Validators
**File:** `scripts/utils/validators.sh`

```bash
#!/usr/bin/env bash
# Validation functions

check_internet() { ... }
check_disk_space() { ... }
check_command() { ... }
verify_installation() { ... }
```

**Deliverables:**
- OS detection working
- Logging functions available
- Validation utilities ready
- All utils tested

---

### Phase 3: Backup & Restore System (2-3 hours)

#### Step 3.1: Backup Script
**File:** `scripts/backup/backup.sh`

```bash
#!/usr/bin/env bash
# Backup existing configurations

# Create timestamped backup directory
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Files to backup
DOTFILES=(
    .zshrc .bashrc .zprofile .zshenv
    .gitconfig .gitignore_global
    .vimrc .vim
    .tmux.conf
    .config/nvim
)

# Backup each file if exists
# Create manifest.json
# Compress backup (optional)
```

#### Step 3.2: Restore Script
**File:** `scripts/backup/restore.sh`

```bash
#!/usr/bin/env bash
# Restore from backup

# List available backups
# Prompt user to select
# Remove current symlinks
# Restore files from backup
# Verify restoration
```

**Deliverables:**
- Backup script tested
- Restore script tested
- Manifest tracking works
- No data loss possible

---

### Phase 4: Package Installation Scripts (4-5 hours)

#### Step 4.1: Package Manager Installer
**File:** `scripts/install/brew.sh`

```bash
#!/usr/bin/env bash
# Install Homebrew (macOS and Linux)

if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
```

#### Step 4.2: Common Package Installer
**File:** `scripts/install/packages/common.sh`

```bash
#!/usr/bin/env bash
# Install cross-platform packages

install_package() {
    local package=$1
    case $PKG_MANAGER in
        brew) brew install "$package" ;;
        apt)  sudo apt install -y "$package" ;;
        dnf)  sudo dnf install -y "$package" ;;
        pacman) sudo pacman -S --noconfirm "$package" ;;
    esac
}

# Essential packages
for pkg in git curl wget vim tmux zsh; do
    install_package "$pkg"
done
```

#### Step 4.3: Modern CLI Tools
**File:** `scripts/install/packages/modern-cli.sh`

```bash
#!/usr/bin/env bash
# Install modern CLI replacements

TOOLS=(
    bat ripgrep fd-find eza zoxide
    fzf tree htop btop jq yq
)

for tool in "${TOOLS[@]}"; do
    install_package "$tool"
done
```

#### Step 4.4: Developer Tools
**File:** `scripts/install/packages/dev-tools.sh`

```bash
#!/usr/bin/env bash
# Install development tools

# Node.js
# Python 3
# Go
# Rust
# Version managers (nvm, pyenv, rbenv)
```

#### Step 4.5: DevOps Tools
**File:** `scripts/install/packages/devops-tools.sh`

```bash
#!/usr/bin/env bash
# Install DevOps tools

# Docker & Docker Compose
# Kubectl, Helm, K9s
# Terraform, Ansible
# AWS CLI, gcloud, azure-cli
```

#### Step 4.6: Platform-Specific Installers
**File:** `scripts/install/macos.sh`
- Use Brewfile
- Install casks
- Set up macOS defaults

**File:** `scripts/install/linux.sh`
- Use apt/dnf
- Install from repos
- Add PPAs if needed

**Deliverables:**
- Package installers work on macOS
- Package installers work on Linux
- All tools from aliases.zsh supported
- Error handling implemented

---

### Phase 5: Symlink Management (2-3 hours)

#### Step 5.1: Install GNU Stow
```bash
# Add to bootstrap.sh
if ! command -v stow &>/dev/null; then
    install_package "stow"
fi
```

#### Step 5.2: Symlink Creation Script
**File:** `scripts/setup/symlinks.sh`

```bash
#!/usr/bin/env bash
# Create symlinks using GNU stow

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Stow each module
for module in shell git vim tmux terminal tools; do
    if [[ -d "$DOTFILES_DIR/$module" ]]; then
        stow -d "$DOTFILES_DIR" -t "$HOME" "$module"
        log_success "Linked $module"
    fi
done
```

#### Step 5.3: Install Script
**File:** `install.sh`

```bash
#!/usr/bin/env bash
# Main symlink installer

# Parse arguments
# Backup existing files
# Run stow for selected modules
# Verify links created
```

**Deliverables:**
- Symlinks created correctly
- No overwrites without backup
- Selective module installation works
- Uninstall removes links cleanly

---

### Phase 6: Master Bootstrap Script (5-6 hours)

#### Step 6.1: Bootstrap Script Structure
**File:** `bootstrap.sh`

```bash
#!/usr/bin/env bash
#
# Bootstrap script for dot-files setup
# Usage: ./bootstrap.sh [options]
#

set -e

# Source utilities
source scripts/utils/detect-os.sh
source scripts/utils/logger.sh
source scripts/utils/validators.sh

# Parse command-line arguments
parse_args() { ... }

# Pre-flight checks
preflight_checks() {
    log_info "Running pre-flight checks..."
    check_internet
    check_disk_space
    check_sudo
}

# Backup existing configs
backup_configs() {
    log_info "Backing up existing configurations..."
    scripts/backup/backup.sh
}

# Install package manager
install_package_manager() {
    if [[ $OS_TYPE == "macos" ]]; then
        scripts/install/brew.sh
    fi
}

# Install packages
install_packages() {
    log_info "Installing packages..."

    scripts/install/packages/common.sh
    scripts/install/packages/modern-cli.sh

    if [[ $INSTALL_LEVEL == "full" ]]; then
        scripts/install/packages/dev-tools.sh
        scripts/install/packages/devops-tools.sh
    fi
}

# Create symlinks
create_symlinks() {
    log_info "Creating symlinks..."
    scripts/setup/symlinks.sh
}

# Configure Git
configure_git() {
    log_info "Configuring Git..."
    read -p "Enter your name: " name
    read -p "Enter your email: " email

    git config --global user.name "$name"
    git config --global user.email "$email"
}

# Set default shell
set_default_shell() {
    if [[ $SHELL != *"zsh" ]]; then
        log_info "Setting zsh as default shell..."
        chsh -s "$(which zsh)"
    fi
}

# Apply macOS defaults
apply_macos_defaults() {
    if [[ $OS_TYPE == "macos" ]]; then
        log_info "Applying macOS defaults..."
        scripts/setup/macos-defaults.sh
    fi
}

# Security hardening
apply_security() {
    log_info "Applying security hardening..."
    scripts/setup/security.sh
}

# Install fonts
install_fonts() {
    log_info "Installing Nerd Fonts..."
    # Install Meslo Nerd Font, etc.
}

# Validate installation
validate_install() {
    log_info "Validating installation..."
    tests/test-runner.sh --quick
}

# Print post-install message
print_success_message() {
    log_success "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Restart your terminal or run: exec zsh"
    echo "  2. Review configuration in ~/.dotfiles"
    echo "  3. Customize: ~/.zshrc.local for local overrides"
    echo ""
}

# Main function
main() {
    log_info "Starting dot-files setup..."

    parse_args "$@"
    detect_os
    preflight_checks
    backup_configs
    install_package_manager
    install_packages
    create_symlinks
    configure_git
    set_default_shell
    apply_macos_defaults
    apply_security
    install_fonts
    validate_install
    print_success_message
}

main "$@"
```

#### Step 6.2: Add Options Support
```bash
--minimal       # Only essential tools
--full          # Everything (default)
--no-packages   # Skip packages
--no-symlinks   # Skip symlinks
--backup        # Backup only
--dry-run       # Show what would happen
--update        # Update existing install
--help          # Show help
```

**Deliverables:**
- Bootstrap script fully functional
- All options work correctly
- Tested on clean macOS
- Tested on clean Linux VM
- Error handling robust
- Progress indicators clear

---

### Phase 7: Testing Suite (3-4 hours)

#### Step 7.1: Test Runner
**File:** `tests/test-runner.sh`

```bash
#!/usr/bin/env bash
# Main test runner

# Run all tests
run_all_tests() {
    tests/test-tools.sh
    tests/test-aliases.sh
    tests/test-configs.sh
}
```

#### Step 7.2: Tool Tests
**File:** `tests/test-tools.sh`

```bash
#!/usr/bin/env bash
# Test that all tools are installed

REQUIRED_TOOLS=(
    git curl wget vim tmux zsh
    bat rg fd eza zoxide fzf
    jq yq tree btop
)

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" &>/dev/null; then
        log_success "$tool is installed"
    else
        log_error "$tool is NOT installed"
        ((errors++))
    fi
done
```

#### Step 7.3: Alias Tests
**File:** `tests/test-aliases.sh`

```bash
#!/usr/bin/env bash
# Test that aliases work

# Source shell config
source ~/.zshrc

# Test aliases
test_alias "gs" "git status"
test_alias "ll" "eza -l"
# etc.
```

#### Step 7.4: Config Tests
**File:** `tests/test-configs.sh`

```bash
#!/usr/bin/env bash
# Validate config file syntax

# Test .zshrc loads without errors
zsh -c "source ~/.zshrc" || log_error ".zshrc has errors"

# Test git config valid
git config --global --list >/dev/null || log_error "git config invalid"

# Test vim config valid
vim -c "quit" || log_error "vim config invalid"
```

**Deliverables:**
- Test suite covers all tools
- Tests run automatically
- CI/CD integration ready
- Reports clear pass/fail

---

### Phase 8: Documentation (4-5 hours)

#### Step 8.1: Main README
**File:** `README.md`

```markdown
# Dot-Files - Production-Ready CLI Configuration

> Transform your terminal into a powerful development environment in 10 minutes.

## Features
- 150+ optimized aliases and functions
- Modern CLI replacements (bat, ripgrep, eza, etc.)
- Cross-platform (macOS, Linux)
- Modular and customizable
- One-command setup

## Quick Start
\`\`\`bash
git clone https://github.com/username/dot-files.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh
\`\`\`

## What's Included
[List all tools and configs]

## Documentation
- [Installation Guide](docs/INSTALLATION.md)
- [Customization](docs/CUSTOMIZATION.md)
- [Tools Reference](docs/TOOLS.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
```

#### Step 8.2: Installation Guide
**File:** `docs/INSTALLATION.md`
- Detailed step-by-step instructions
- Prerequisites
- Platform-specific notes
- Troubleshooting common issues

#### Step 8.3: Customization Guide
**File:** `docs/CUSTOMIZATION.md`
- How to add your own aliases
- Local overrides (~/.zshrc.local)
- Per-machine configs
- Adding new modules

#### Step 8.4: Tools Reference
**File:** `docs/TOOLS.md`
- Description of every tool
- Why it's included
- How to use it
- Alternatives

#### Step 8.5: Troubleshooting
**File:** `docs/TROUBLESHOOTING.md`
- Common errors and solutions
- Platform-specific issues
- How to report bugs
- Rollback instructions

**Deliverables:**
- Comprehensive README
- All documentation complete
- Examples and screenshots
- Links working
- Markdown properly formatted

---

### Phase 9: Testing & Refinement (3-4 hours)

#### Step 9.1: Clean VM Testing
```bash
# Test on clean macOS VM
1. Clone repo
2. Run ./bootstrap.sh
3. Verify all tools installed
4. Test aliases work
5. Check symlinks correct

# Test on clean Linux VM (Ubuntu)
[Same as above]

# Test on clean Linux VM (Debian)
[Same as above]
```

#### Step 9.2: Edge Case Testing
- Test with existing configs
- Test with missing sudo
- Test with no internet
- Test with low disk space
- Test interrupted install (Ctrl+C)
- Test rollback/restore

#### Step 9.3: Performance Testing
- Shell startup time < 200ms
- Bootstrap completes in < 10 minutes
- No hanging or freezing

**Deliverables:**
- Tested on 3+ platforms
- All edge cases handled
- Performance acceptable
- No critical bugs

---

### Phase 10: Polish & Release (2-3 hours)

#### Step 10.1: Code Cleanup
- Remove commented code
- Consistent formatting
- Add code comments
- Run shellcheck on all scripts

#### Step 10.2: CI/CD Setup
**File:** `.github/workflows/test.yml`
```yaml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: ./tests/test-runner.sh
```

#### Step 10.3: License & Contributing
**File:** `LICENSE`
- Choose license (MIT recommended)

**File:** `CONTRIBUTING.md`
- How to contribute
- Code style
- Pull request process

#### Step 10.4: Release
```bash
# Tag version
git tag -a v1.0.0 -m "Initial release"
git push origin v1.0.0

# Create GitHub release
# Write changelog
# Add release notes
```

**Deliverables:**
- Clean, well-documented code
- CI/CD passing
- License added
- v1.0.0 released

---

## Timeline Summary

| Phase | Duration | Dependencies |
|-------|----------|--------------|
| Phase 1: Foundation | 2-3 hours | None |
| Phase 2: Utilities | 3-4 hours | Phase 1 |
| Phase 3: Backup System | 2-3 hours | Phase 2 |
| Phase 4: Package Installation | 4-5 hours | Phase 2 |
| Phase 5: Symlink Management | 2-3 hours | Phase 1, 3 |
| Phase 6: Bootstrap Script | 5-6 hours | Phase 2, 3, 4, 5 |
| Phase 7: Testing | 3-4 hours | Phase 6 |
| Phase 8: Documentation | 4-5 hours | All phases |
| Phase 9: Testing & Refinement | 3-4 hours | All phases |
| Phase 10: Polish & Release | 2-3 hours | All phases |

**Total Estimated Time:** 30-40 hours

**Realistic Timeline:**
- Week 1: Phases 1-5 (Foundation, utilities, installers)
- Week 2: Phases 6-7 (Bootstrap script, testing)
- Week 3: Phases 8-10 (Documentation, refinement, release)

---

## Success Criteria

The implementation is complete when:

- [ ] Bootstrap script runs successfully on fresh macOS
- [ ] Bootstrap script runs successfully on fresh Ubuntu
- [ ] Bootstrap script runs successfully on fresh Debian
- [ ] All 150+ aliases work correctly
- [ ] All modern CLI tools installed
- [ ] Symlinks created properly with stow
- [ ] Backup/restore system works
- [ ] Tests pass on all platforms
- [ ] Documentation is comprehensive
- [ ] No manual intervention required
- [ ] Setup completes in < 10 minutes
- [ ] Shell startup time < 200ms
- [ ] CI/CD pipeline passing
- [ ] v1.0.0 released with changelog

---

## Quick Start (For Implementer)

```bash
# Clone or navigate to repo
cd ~/.dotfiles

# Create all directories
mkdir -p {shell,git,vim,tmux,terminal,tools,scripts/{install,backup,setup,utils},config/{ssh,aws,docker},docs,tests,legacy}

# Start with Phase 1
# Follow step-by-step instructions above
# Test after each phase
# Commit progress regularly

# When complete, test full flow:
./bootstrap.sh --dry-run  # Preview
./bootstrap.sh            # Real run
tests/test-runner.sh      # Validate
```

---

## Notes

- **Commit Often:** After each phase, commit changes
- **Test Early:** Don't wait until the end to test
- **Document As You Go:** Write docs while building
- **Ask for Feedback:** Have someone test on their machine
- **Keep It Simple:** Don't over-engineer, YAGNI principle
- **Performance Matters:** Profile shell startup time
- **Backup Everything:** Never lose user data
- **Error Handling:** Every script should handle errors gracefully

---

## Maintenance Plan

After v1.0.0 release:

1. **Weekly:** Update package versions in Brewfile
2. **Monthly:** Add new tools/aliases based on usage
3. **Quarterly:** Refactor and optimize
4. **Yearly:** Major version update with breaking changes

---

This plan provides a clear path from the current state to a production-ready dot-files system. Follow it step-by-step, test thoroughly, and you'll have a professional CLI configuration solution.
