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

