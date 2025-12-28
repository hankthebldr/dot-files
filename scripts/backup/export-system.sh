#!/bin/bash

# System Configuration Export Script
# Exports macOS configurations, packages, and dotfiles
# Author: Generated for system backup and migration
# Date: $(date +%Y-%m-%d)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default export directory
DEFAULT_DIR="$HOME/Github/Github_desktop/dog-files"
EXPORT_DIR="${1:-$DEFAULT_DIR}"

echo -e "${BLUE}=== System Configuration Export ===${NC}"
echo -e "${BLUE}Export directory: ${EXPORT_DIR}${NC}\n"

# Create export directory structure
mkdir -p "$EXPORT_DIR"/{dotfiles,packages,applications,system-info,config-dirs,browser-profiles,parseable-configs}

# Function to print section headers
print_section() {
    echo -e "\n${GREEN}[*] $1${NC}"
}

# Function to print success
print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}  ! $1${NC}"
}

# Function to print error
print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

# ============================================================================
# SYSTEM INFORMATION
# ============================================================================
print_section "Gathering System Information"

{
    echo "# System Information"
    echo "Export Date: $(date)"
    echo "Hostname: $(hostname)"
    echo "OS Version: $(sw_vers -productName) $(sw_vers -productVersion)"
    echo "Kernel: $(uname -srm)"
    echo "Architecture: $(uname -m)"
    echo "User: $(whoami)"
    echo "Shell: $SHELL"
} > "$EXPORT_DIR/system-info/system.txt"
print_success "System information saved"

# ============================================================================
# HOMEBREW PACKAGES
# ============================================================================
print_section "Exporting Homebrew Packages"

if command -v brew &> /dev/null; then
    # Export Brewfile
    brew bundle dump --file="$EXPORT_DIR/packages/Brewfile" --force
    print_success "Brewfile created"

    # Export detailed package lists
    brew list --formula > "$EXPORT_DIR/packages/brew-formulae.txt"
    print_success "Formula list saved ($(wc -l < "$EXPORT_DIR/packages/brew-formulae.txt") packages)"

    brew list --cask > "$EXPORT_DIR/packages/brew-casks.txt"
    print_success "Cask list saved ($(wc -l < "$EXPORT_DIR/packages/brew-casks.txt") apps)"

    # Export brew info for all packages
    brew info --json=v2 --installed > "$EXPORT_DIR/packages/brew-info.json"
    print_success "Detailed package info saved"
else
    print_warning "Homebrew not installed"
fi

# ============================================================================
# NODE/NPM PACKAGES
# ============================================================================
print_section "Exporting Node.js/NPM Packages"

if command -v npm &> /dev/null; then
    npm list -g --depth=0 > "$EXPORT_DIR/packages/npm-global.txt" 2>/dev/null || true
    print_success "Global NPM packages saved"

    # Export Node version
    node --version > "$EXPORT_DIR/packages/node-version.txt" 2>/dev/null || true
    npm --version >> "$EXPORT_DIR/packages/node-version.txt" 2>/dev/null || true
    print_success "Node/NPM versions saved"
else
    print_warning "NPM not installed"
fi

if command -v yarn &> /dev/null; then
    yarn global list > "$EXPORT_DIR/packages/yarn-global.txt" 2>/dev/null || true
    print_success "Global Yarn packages saved"
fi

# ============================================================================
# PYTHON PACKAGES
# ============================================================================
print_section "Exporting Python Packages"

if command -v pip3 &> /dev/null; then
    pip3 list --format=freeze > "$EXPORT_DIR/packages/pip3-packages.txt"
    print_success "Pip3 packages saved"
    python3 --version > "$EXPORT_DIR/packages/python-version.txt"
elif command -v pip &> /dev/null; then
    pip list --format=freeze > "$EXPORT_DIR/packages/pip-packages.txt"
    print_success "Pip packages saved"
    python --version > "$EXPORT_DIR/packages/python-version.txt"
else
    print_warning "Python/Pip not installed"
fi

# ============================================================================
# RUBY GEMS
# ============================================================================
print_section "Exporting Ruby Gems"

if command -v gem &> /dev/null; then
    gem list > "$EXPORT_DIR/packages/ruby-gems.txt"
    print_success "Ruby gems saved"
    ruby --version > "$EXPORT_DIR/packages/ruby-version.txt"
else
    print_warning "Ruby not installed"
fi

# ============================================================================
# DOTFILES
# ============================================================================
print_section "Exporting Dotfiles"

# List of common dotfiles to export
DOTFILES=(
    ".bashrc"
    ".bash_profile"
    ".zshrc"
    ".zprofile"
    ".zshenv"
    ".profile"
    ".vimrc"
    ".vim"
    ".tmux.conf"
    ".gitconfig"
    ".gitignore_global"
    ".npmrc"
    ".yarnrc"
    ".gemrc"
    ".curlrc"
    ".wgetrc"
    ".inputrc"
    ".editorconfig"
    ".aliases"
    ".functions"
    ".exports"
)

for dotfile in "${DOTFILES[@]}"; do
    if [ -e "$HOME/$dotfile" ]; then
        if [ -d "$HOME/$dotfile" ]; then
            cp -R "$HOME/$dotfile" "$EXPORT_DIR/dotfiles/"
            print_success "Copied directory: $dotfile"
        else
            cp "$HOME/$dotfile" "$EXPORT_DIR/dotfiles/"
            print_success "Copied file: $dotfile"
        fi
    fi
done

# Export SSH config (without private keys)
if [ -f "$HOME/.ssh/config" ]; then
    mkdir -p "$EXPORT_DIR/dotfiles/.ssh"
    cp "$HOME/.ssh/config" "$EXPORT_DIR/dotfiles/.ssh/"
    print_success "SSH config copied"
fi

# ============================================================================
# CONFIGURATION DIRECTORIES
# ============================================================================
print_section "Exporting Configuration Directories"

# Common config directories
CONFIG_DIRS=(
    ".config/nvim"
    ".config/git"
    ".config/zsh"
    ".config/fish"
    ".config/alacritty"
    ".config/kitty"
    ".config/tmux"
    ".aws"
    ".docker"
)

for config_dir in "${CONFIG_DIRS[@]}"; do
    if [ -d "$HOME/$config_dir" ]; then
        mkdir -p "$EXPORT_DIR/config-dirs/$(dirname "$config_dir")"
        cp -R "$HOME/$config_dir" "$EXPORT_DIR/config-dirs/$config_dir"
        print_success "Copied config: $config_dir"
    fi
done

# ============================================================================
# APPLICATIONS
# ============================================================================
print_section "Listing Installed Applications"

# List all applications in /Applications
ls /Applications > "$EXPORT_DIR/applications/applications-list.txt"
print_success "Applications list saved"

# List user applications
if [ -d "$HOME/Applications" ]; then
    ls "$HOME/Applications" > "$EXPORT_DIR/applications/user-applications-list.txt"
    print_success "User applications list saved"
fi

# ============================================================================
# VS CODE EXTENSIONS
# ============================================================================
print_section "Exporting VS Code Extensions"

if command -v code &> /dev/null; then
    code --list-extensions > "$EXPORT_DIR/applications/vscode-extensions.txt"
    print_success "VS Code extensions saved"
else
    print_warning "VS Code CLI not installed"
fi

# ============================================================================
# SHELL ENVIRONMENT
# ============================================================================
print_section "Exporting Shell Environment"

# Export current PATH
echo "$PATH" > "$EXPORT_DIR/system-info/path.txt"
print_success "PATH saved"

# Export environment variables (filtered for sensitive data)
env | grep -v -E '(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL)' | sort > "$EXPORT_DIR/system-info/environment.txt"
print_success "Environment variables saved"

# Export shell aliases
if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
    alias > "$EXPORT_DIR/system-info/aliases.txt" 2>/dev/null || true
    print_success "Aliases saved"
fi

# ============================================================================
# BROWSER PROFILES AND CONFIGURATIONS
# ============================================================================
print_section "Exporting Browser Configurations"

# Chrome/Chromium browsers
CHROME_PROFILES=(
    "$HOME/Library/Application Support/Google/Chrome"
    "$HOME/Library/Application Support/Chromium"
    "$HOME/Library/Application Support/Brave Browser"
    "$HOME/Library/Application Support/Microsoft Edge"
)

for chrome_path in "${CHROME_PROFILES[@]}"; do
    browser_name=$(basename "$chrome_path")
    if [ -d "$chrome_path" ]; then
        # Check if Default profile exists
        if [ ! -d "$chrome_path/Default" ] && [ ! -d "$chrome_path/Profile 1" ]; then
            print_warning "Found $browser_name but no profiles"
            continue
        fi

        print_success "Found $browser_name"

        # Create directory for this browser
        mkdir -p "$EXPORT_DIR/browser-profiles/$browser_name"

        # Export Default profile if it exists
        if [ -d "$chrome_path/Default" ]; then
            # Export bookmarks
            if [ -f "$chrome_path/Default/Bookmarks" ]; then
                cp "$chrome_path/Default/Bookmarks" "$EXPORT_DIR/browser-profiles/$browser_name/" 2>/dev/null && print_success "  → Bookmarks exported"
            fi

            # Export preferences (contains settings, extensions list, etc.)
            if [ -f "$chrome_path/Default/Preferences" ]; then
                cp "$chrome_path/Default/Preferences" "$EXPORT_DIR/browser-profiles/$browser_name/" 2>/dev/null && print_success "  → Preferences exported"
            fi

            # Export extensions list
            if [ -d "$chrome_path/Default/Extensions" ]; then
                ls "$chrome_path/Default/Extensions" > "$EXPORT_DIR/browser-profiles/$browser_name/extensions-list.txt" 2>/dev/null && print_success "  → Extensions list created"
            fi

            # Export History (optional - can be large)
            if [ -f "$chrome_path/Default/History" ]; then
                cp "$chrome_path/Default/History" "$EXPORT_DIR/browser-profiles/$browser_name/" 2>/dev/null || print_warning "  → Could not export History (may be in use)"
            fi

            # Export cookies (WARNING: Contains session data)
            if [ -f "$chrome_path/Default/Cookies" ]; then
                cp "$chrome_path/Default/Cookies" "$EXPORT_DIR/browser-profiles/$browser_name/" 2>/dev/null || print_warning "  → Could not export Cookies (may be in use)"
            fi

            # Export local storage
            if [ -d "$chrome_path/Default/Local Storage" ]; then
                cp -R "$chrome_path/Default/Local Storage" "$EXPORT_DIR/browser-profiles/$browser_name/" 2>/dev/null || print_warning "  → Could not export Local Storage (may be in use)"
            fi
        fi

        # List all profiles
        if [ -d "$chrome_path" ]; then
            ls "$chrome_path" 2>/dev/null | grep -E "^(Default|Profile [0-9]+)$" > "$EXPORT_DIR/browser-profiles/$browser_name/profiles-list.txt" 2>/dev/null
        fi

        # Export other profiles if they exist
        for profile_dir in "$chrome_path"/Profile*; do
            if [ -d "$profile_dir" ]; then
                profile_name=$(basename "$profile_dir")
                mkdir -p "$EXPORT_DIR/browser-profiles/$browser_name/$profile_name"

                [ -f "$profile_dir/Bookmarks" ] && cp "$profile_dir/Bookmarks" "$EXPORT_DIR/browser-profiles/$browser_name/$profile_name/" 2>/dev/null
                [ -f "$profile_dir/Preferences" ] && cp "$profile_dir/Preferences" "$EXPORT_DIR/browser-profiles/$browser_name/$profile_name/" 2>/dev/null
                [ -d "$profile_dir/Extensions" ] && ls "$profile_dir/Extensions" > "$EXPORT_DIR/browser-profiles/$browser_name/$profile_name/extensions-list.txt" 2>/dev/null

                print_success "  → Additional profile exported: $profile_name"
            fi
        done
    fi
done

# Firefox
FIREFOX_PATH="$HOME/Library/Application Support/Firefox"
if [ -d "$FIREFOX_PATH" ]; then
    print_success "Found Firefox"
    mkdir -p "$EXPORT_DIR/browser-profiles/Firefox"

    # Export profiles.ini
    if [ -f "$FIREFOX_PATH/profiles.ini" ]; then
        cp "$FIREFOX_PATH/profiles.ini" "$EXPORT_DIR/browser-profiles/Firefox/"
        print_success "  → Profiles config exported"
    fi

    # Find and export each profile
    for profile_dir in "$FIREFOX_PATH"/Profiles/*.default* "$FIREFOX_PATH"/Profiles/*.default-release*; do
        if [ -d "$profile_dir" ]; then
            profile_name=$(basename "$profile_dir")
            mkdir -p "$EXPORT_DIR/browser-profiles/Firefox/$profile_name"

            # Export bookmarks (places.sqlite contains bookmarks and history)
            [ -f "$profile_dir/places.sqlite" ] && cp "$profile_dir/places.sqlite" "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/" 2>/dev/null

            # Export preferences
            [ -f "$profile_dir/prefs.js" ] && cp "$profile_dir/prefs.js" "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/"

            # Export extensions
            [ -f "$profile_dir/extensions.json" ] && cp "$profile_dir/extensions.json" "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/"
            [ -d "$profile_dir/extensions" ] && ls "$profile_dir/extensions" > "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/extensions-list.txt"

            # Export cookies
            [ -f "$profile_dir/cookies.sqlite" ] && cp "$profile_dir/cookies.sqlite" "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/" 2>/dev/null

            # Export search engines
            [ -f "$profile_dir/search.json.mozlz4" ] && cp "$profile_dir/search.json.mozlz4" "$EXPORT_DIR/browser-profiles/Firefox/$profile_name/"

            print_success "  → Profile exported: $profile_name"
        fi
    done
fi

# Safari
SAFARI_PATH="$HOME/Library/Safari"
if [ -d "$SAFARI_PATH" ]; then
    print_success "Found Safari"
    mkdir -p "$EXPORT_DIR/browser-profiles/Safari"

    # Export bookmarks
    [ -f "$SAFARI_PATH/Bookmarks.plist" ] && cp "$SAFARI_PATH/Bookmarks.plist" "$EXPORT_DIR/browser-profiles/Safari/"

    # Export reading list
    [ -f "$SAFARI_PATH/ReadingList.plist" ] && cp "$SAFARI_PATH/ReadingList.plist" "$EXPORT_DIR/browser-profiles/Safari/"

    # Export history
    [ -f "$SAFARI_PATH/History.db" ] && cp "$SAFARI_PATH/History.db" "$EXPORT_DIR/browser-profiles/Safari/" 2>/dev/null

    # Export extensions
    if [ -d "$HOME/Library/Safari/Extensions" ]; then
        ls "$HOME/Library/Safari/Extensions" > "$EXPORT_DIR/browser-profiles/Safari/extensions-list.txt"
    fi

    print_success "  → Safari data exported"
fi

# Arc Browser
ARC_PATH="$HOME/Library/Application Support/Arc"
if [ -d "$ARC_PATH" ]; then
    print_success "Found Arc Browser"
    mkdir -p "$EXPORT_DIR/browser-profiles/Arc"

    # Arc uses Chromium-based structure
    [ -f "$ARC_PATH/User Data/Default/Bookmarks" ] && cp "$ARC_PATH/User Data/Default/Bookmarks" "$EXPORT_DIR/browser-profiles/Arc/"
    [ -f "$ARC_PATH/User Data/Default/Preferences" ] && cp "$ARC_PATH/User Data/Default/Preferences" "$EXPORT_DIR/browser-profiles/Arc/"

    print_success "  → Arc data exported"
fi

# Create browser export summary
{
    echo "# Browser Configurations Export Summary"
    echo "Export Date: $(date)"
    echo ""
    echo "## Exported Browsers:"
    for browser_dir in "$EXPORT_DIR/browser-profiles"/*; do
        if [ -d "$browser_dir" ]; then
            echo "- $(basename "$browser_dir")"
        fi
    done
    echo ""
    echo "## Security Warning:"
    echo "Browser profiles may contain sensitive data:"
    echo "- Session cookies (auto-login tokens)"
    echo "- Stored passwords (if not using keychain)"
    echo "- Local storage data"
    echo "- Browsing history"
    echo ""
    echo "Review and clean sensitive data before sharing or committing to version control."
} > "$EXPORT_DIR/browser-profiles/BROWSER-README.md"

print_success "Browser export summary created"

# ============================================================================
# SYSTEM PREFERENCES
# ============================================================================
print_section "Exporting System Preferences"

# Export some common defaults
{
    echo "# Dock Preferences"
    defaults read com.apple.dock 2>/dev/null || echo "Cannot read dock preferences"
    echo -e "\n# Finder Preferences"
    defaults read com.apple.finder 2>/dev/null || echo "Cannot read finder preferences"
    echo -e "\n# Global Preferences"
    defaults read NSGlobalDomain 2>/dev/null || echo "Cannot read global preferences"
} > "$EXPORT_DIR/system-info/macos-defaults.txt"
print_success "macOS defaults saved"

# ============================================================================
# PARSEABLE CONFIGURATION FILES
# ============================================================================
print_section "Creating Parseable Configuration Files"

# Create JSON manifest of all packages
{
    echo "{"
    echo '  "export_date": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",'
    echo '  "hostname": "'$(hostname)'",'
    echo '  "os": "macOS",'
    echo '  "packages": {'

    # Homebrew formulae
    if command -v brew &> /dev/null; then
        echo '    "homebrew_formulae": ['
        brew list --formula | awk '{print "      \"" $0 "\""","}' | sed '$ s/,$//'
        echo '    ],'
        echo '    "homebrew_casks": ['
        brew list --cask | awk '{print "      \"" $0 "\""","}' | sed '$ s/,$//'
        echo '    ],'
    fi

    # NPM global
    if command -v npm &> /dev/null; then
        echo '    "npm_global": ['
        npm list -g --depth=0 --json 2>/dev/null | grep '"' | grep -v "dependencies\|npm" | sed 's/.*"\(.*\)".*/      "\1",/' | sed '$ s/,$//'
        echo '    ],'
    fi

    # Python packages
    if command -v pip3 &> /dev/null; then
        echo '    "pip3": ['
        pip3 list --format=json 2>/dev/null | grep '"name"' | sed 's/.*"name": "\(.*\)".*/      "\1",/' | sed '$ s/,$//'
        echo '    ],'
    fi

    # Ruby gems
    if command -v gem &> /dev/null; then
        echo '    "ruby_gems": ['
        gem list --no-versions | awk '{print "      \"" $0 "\""","}' | sed '$ s/,$//'
        echo '    ]'
    fi

    echo '  },'
    echo '  "shell": "'$SHELL'",'
    echo '  "user": "'$(whoami)'"'
    echo "}"
} > "$EXPORT_DIR/parseable-configs/packages.json"
print_success "packages.json created"

# Create shell-sourceable environment file
{
    echo "# Exported environment configuration"
    echo "# Source this file: source environment.sh"
    echo ""
    echo "# Path configuration"
    echo 'export PATH="'$PATH'"'
    echo ""
    echo "# Shell"
    echo 'export SHELL="'$SHELL'"'
    echo ""
    echo "# Exported aliases (sample - review and uncomment as needed)"
    alias 2>/dev/null | sed 's/^/# /'
} > "$EXPORT_DIR/parseable-configs/environment.sh"
print_success "environment.sh created"

# Create YAML package list
{
    echo "# Package List - YAML Format"
    echo "---"
    echo "export_info:"
    echo "  date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "  source_os: macOS"
    echo "  target_os: parrot-linux"
    echo ""
    echo "homebrew_formulae:"
    if command -v brew &> /dev/null; then
        brew list --formula | awk '{print "  - " $0}'
    fi
    echo ""
    echo "homebrew_casks:"
    if command -v brew &> /dev/null; then
        brew list --cask | awk '{print "  - " $0}'
    fi
    echo ""
    echo "npm_global_packages:"
    if command -v npm &> /dev/null; then
        npm list -g --depth=0 2>/dev/null | grep -v "^[├└─]" | grep -v "npm@" | tail -n +2 | sed 's/.*── //' | awk '{print "  - " $1}'
    fi
    echo ""
    echo "python_packages:"
    if command -v pip3 &> /dev/null; then
        pip3 list --format=freeze | awk -F'==' '{print "  - name: " $1 "\n    version: " $2}'
    fi
} > "$EXPORT_DIR/parseable-configs/packages.yml"
print_success "packages.yml created"

# Create Linux package mapping
{
    echo "# macOS to Linux Package Mapping"
    echo "# Format: macos_package:linux_package:install_method"
    echo "#"
    echo "# Install methods:"
    echo "#   apt    - APT package manager (Debian/Ubuntu/Parrot)"
    echo "#   snap   - Snap package"
    echo "#   manual - Manual installation required"
    echo "#   npm    - NPM global install"
    echo "#   pip    - Python pip install"
    echo ""

    if command -v brew &> /dev/null; then
        brew list --formula | while read pkg; do
            case "$pkg" in
                # CLI tools with direct APT equivalents
                git|vim|tmux|wget|curl|jq|tree|htop|nano|grep|sed|awk|make|gcc|python3|ruby|perl|rsync|ssh|netcat)
                    echo "$pkg:$pkg:apt" ;;
                node)
                    echo "node:nodejs:apt" ;;
                python@*)
                    echo "$pkg:python3:apt" ;;
                # Development tools
                cmake|autoconf|automake|libtool|pkg-config)
                    echo "$pkg:$pkg:apt" ;;
                # Compression tools
                gzip|bzip2|xz|unzip|zip|p7zip)
                    echo "$pkg:$pkg:apt" ;;
                # Network tools
                nmap|wireshark|tcpdump|netcat|socat)
                    echo "$pkg:$pkg:apt" ;;
                # Docker
                docker|docker-compose)
                    echo "$pkg:docker.io:apt" ;;
                # Others require manual review
                *)
                    echo "$pkg:REVIEW_NEEDED:manual" ;;
            esac
        done
    fi
} > "$EXPORT_DIR/parseable-configs/macos-to-linux-mapping.txt"
print_success "macos-to-linux-mapping.txt created"

# Create shell install script for common tools
{
    echo "#!/bin/bash"
    echo "# Auto-generated package installation script for Parrot OS / Debian-based Linux"
    echo "# Review before executing!"
    echo ""
    echo "set -e"
    echo ""
    echo "echo 'Installing common development tools...'"
    echo ""
    echo "# Update package list"
    echo "sudo apt update"
    echo ""
    echo "# Common CLI tools"
    echo "PACKAGES=("

    # Map common Homebrew packages to APT
    if command -v brew &> /dev/null; then
        brew list --formula | while read pkg; do
            case "$pkg" in
                git|vim|tmux|wget|curl|jq|tree|htop|zsh|bash|fish) echo "    $pkg" ;;
                node) echo "    nodejs" ;;
                python@*) echo "    python3 python3-pip" ;;
                ruby) echo "    ruby-full" ;;
            esac
        done | sort -u
    fi

    echo ")"
    echo ""
    echo "# Install packages"
    echo 'for pkg in "${PACKAGES[@]}"; do'
    echo '    echo "Installing $pkg..."'
    echo '    sudo apt install -y $pkg'
    echo 'done'
    echo ""
    echo "echo 'Package installation complete!'"
    echo ""
    echo "# NPM global packages"
    if command -v npm &> /dev/null; then
        echo "if command -v npm &> /dev/null; then"
        echo "    echo 'Installing NPM global packages...'"
        npm list -g --depth=0 2>/dev/null | grep -v "^[├└─]" | tail -n +2 | sed 's/.*── //' | awk '{print "    npm install -g " $1}'
        echo "fi"
    fi
    echo ""
    echo "# Python packages"
    if command -v pip3 &> /dev/null; then
        echo "if command -v pip3 &> /dev/null; then"
        echo "    echo 'Installing Python packages...'"
        echo "    pip3 install -r ../packages/pip3-packages.txt"
        echo "fi"
    fi
} > "$EXPORT_DIR/parseable-configs/install-packages-linux.sh"
chmod +x "$EXPORT_DIR/parseable-configs/install-packages-linux.sh"
print_success "install-packages-linux.sh created (executable)"

# Create CLI tools inventory
{
    echo "# CLI Tools Inventory"
    echo "# Detected command-line tools with versions"
    echo ""
    echo "Tool,Version,Location"

    for cmd in git vim nvim tmux zsh bash fish python python3 ruby node npm yarn pip pip3 docker kubectl aws gcloud terraform ansible; do
        if command -v $cmd &> /dev/null; then
            version=$($cmd --version 2>&1 | head -n1 | tr '\n' ' ')
            location=$(which $cmd)
            echo "$cmd,\"$version\",$location"
        fi
    done
} > "$EXPORT_DIR/parseable-configs/cli-tools-inventory.csv"
print_success "cli-tools-inventory.csv created"

# Create dotfiles installation script
{
    echo "#!/bin/bash"
    echo "# Dotfiles installation script"
    echo "# Usage: ./install-dotfiles.sh"
    echo ""
    echo "set -e"
    echo ""
    echo 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
    echo 'DOTFILES_DIR="$SCRIPT_DIR/../dotfiles"'
    echo ""
    echo "echo 'Installing dotfiles...'"
    echo ""
    echo "# Backup existing dotfiles"
    echo 'BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"'
    echo 'mkdir -p "$BACKUP_DIR"'
    echo ""

    # List all dotfiles that were exported
    find ~/Github/Github_desktop/dog-files/dotfiles -maxdepth 1 -name ".*" -type f 2>/dev/null | while read file; do
        filename=$(basename "$file")
        echo "# Install $filename"
        echo "if [ -f \"\$HOME/$filename\" ]; then"
        echo "    cp \"\$HOME/$filename\" \"\$BACKUP_DIR/\""
        echo "    echo 'Backed up existing $filename'"
        echo "fi"
        echo "cp \"\$DOTFILES_DIR/$filename\" \"\$HOME/$filename\""
        echo "echo 'Installed $filename'"
        echo ""
    done 2>/dev/null || true

    echo "echo 'Dotfiles installation complete!'"
    echo "echo 'Backups saved to: \$BACKUP_DIR'"
} > "$EXPORT_DIR/parseable-configs/install-dotfiles.sh"
chmod +x "$EXPORT_DIR/parseable-configs/install-dotfiles.sh"
print_success "install-dotfiles.sh created (executable)"

print_success "All parseable configs created"

# ============================================================================
# CREATE README
# ============================================================================
print_section "Creating README"

cat > "$EXPORT_DIR/README.md" << 'EOF'
# System Configuration Export

This export contains your system configuration, packages, and dotfiles.

## Contents

### 📦 Packages (`packages/`)
- `Brewfile` - Homebrew bundle file (restore with `brew bundle`)
- `brew-formulae.txt` - List of Homebrew formulae
- `brew-casks.txt` - List of Homebrew casks
- `npm-global.txt` - Global NPM packages
- `pip3-packages.txt` - Python packages
- `ruby-gems.txt` - Ruby gems

### 🔧 Dotfiles (`dotfiles/`)
- Shell configuration files (.zshrc, .bashrc, etc.)
- Git configuration (.gitconfig)
- Editor configurations (.vimrc, etc.)
- SSH configuration (config only, no keys)

### 📁 Config Directories (`config-dirs/`)
- Application-specific configurations from ~/.config/

### 💻 Applications (`applications/`)
- List of installed macOS applications
- VS Code extensions

### 🌐 Browser Profiles (`browser-profiles/`)
- Bookmarks and favorites
- Browser preferences and settings
- Extensions lists
- Cookies and session data
- History (optional)
- Multiple profile support

### 📋 Parseable Configs (`parseable-configs/`) **NEW**
- `packages.json` - All packages in JSON format
- `packages.yml` - All packages in YAML format
- `environment.sh` - Shell-sourceable environment variables
- `cli-tools-inventory.csv` - CLI tools with versions
- `macos-to-linux-mapping.txt` - Package name mappings
- `install-packages-linux.sh` - Executable installer for Linux
- `install-dotfiles.sh` - Executable dotfiles installer

### ℹ️ System Information (`system-info/`)
- System details and versions
- Environment variables
- PATH configuration
- macOS defaults

## Restoring on a New System

### Homebrew Packages
```bash
# Install Homebrew first
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Restore packages
cd packages
brew bundle
```

### Dotfiles
```bash
# Copy dotfiles to home directory
cp dotfiles/.* ~/

# Source shell configuration
source ~/.zshrc  # or ~/.bashrc
```

### NPM Packages
```bash
# Install global packages (edit the file to create a proper install script)
cat packages/npm-global.txt
```

### Python Packages
```bash
pip3 install -r packages/pip3-packages.txt
```

### VS Code Extensions
```bash
cat applications/vscode-extensions.txt | xargs -L 1 code --install-extension
```

### Browser Data
```bash
# Chrome/Chromium-based browsers (Chrome, Brave, Edge)
# Bookmarks location on Linux: ~/.config/google-chrome/Default/Bookmarks
# Copy exported bookmarks to appropriate browser profile directory

# Firefox
# Linux location: ~/.mozilla/firefox/
# Copy profile directories or import bookmarks manually

# Review BROWSER-README.md for security considerations
```

### Quick Install for Parrot OS (Using Parseable Configs)
```bash
# Install packages automatically
cd parseable-configs
chmod +x install-packages-linux.sh
./install-packages-linux.sh

# Install dotfiles
chmod +x install-dotfiles.sh
./install-dotfiles.sh

# Review package mappings
cat macos-to-linux-mapping.txt

# View all packages in JSON/YAML
cat packages.json
cat packages.yml

# Source environment variables
source environment.sh
```

## Notes for Parrot OS

This export was created on macOS. When migrating to Parrot OS (Debian-based):

1. **Package Manager**: Use `apt` instead of `brew`
2. **Shell**: Bash is default, but zsh configurations are included
3. **Paths**: Adjust paths in dotfiles (e.g., /usr/local/bin vs /opt/homebrew/bin)
4. **Applications**: Many macOS apps have Linux alternatives
5. **System Preferences**: macOS-specific, adapt as needed

### Suggested Linux Alternatives
- Homebrew → APT (native) or Linuxbrew
- macOS apps → Check for Linux versions or alternatives
- Review shell paths and update for Linux filesystem structure

EOF

print_success "README.md created"

# ============================================================================
# CREATE TARBALL
# ============================================================================
print_section "Creating Compressed Archive"

TARBALL="${EXPORT_DIR}.tar.gz"
tar -czf "$TARBALL" -C "$(dirname "$EXPORT_DIR")" "$(basename "$EXPORT_DIR")"
print_success "Archive created: $TARBALL"

# ============================================================================
# SUMMARY
# ============================================================================
echo -e "\n${GREEN}=== Export Complete ===${NC}"
echo -e "${BLUE}Export Location:${NC} $EXPORT_DIR"
echo -e "${BLUE}Archive:${NC} $TARBALL"
echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Review the exported files in: $EXPORT_DIR"
echo "2. Transfer $TARBALL to your Parrot OS system"
echo "3. Extract: tar -xzf $(basename "$TARBALL")"
echo "4. Follow instructions in README.md"
echo -e "\n${YELLOW}Security Note:${NC} Review exported files for sensitive data before sharing"
