# System Configuration Export Script - Usage Guide

## Overview
The `export-system-config.sh` script creates a complete portable backup of your macOS system configuration, including packages, dotfiles, browser profiles, and application settings. This is ideal for migrating to a new system (like Parrot OS) or creating backups.

## Location
- Script: `/Users/henry/export-system-config.sh`
- Default output: `~/Github/Github_desktop/dog-files/`
- Archive: `~/Github/Github_desktop/dog-files.tar.gz`

## What Gets Exported

### 📦 Packages
- **Homebrew**: Brewfile, formulae, casks, and detailed package info
- **Node.js**: Global NPM and Yarn packages
- **Python**: pip3 packages
- **Ruby**: Gems

### 🔧 Dotfiles
- Shell configs (.zshrc, .zprofile, .bashrc, etc.)
- Git configuration (.gitconfig)
- Editor configs (.vimrc, .vim/)
- SSH config (no private keys)
- Various rc files (.yarnrc, etc.)

### 🌐 Browser Profiles
- **Chrome**: Bookmarks, preferences, extensions, history, cookies, local storage
- **Firefox**: Bookmarks, preferences, extensions, profiles
- **Safari**: Bookmarks, reading list, history
- **Arc**: Bookmarks and preferences
- **Brave/Edge**: If installed

### 📁 Configuration Directories
- `.config/` subdirectories (nvim, git, zsh, etc.)
- `.aws/` configuration
- `.docker/` configuration

### 💻 Applications
- List of installed macOS applications
- VS Code extensions (if code CLI is available)

### ℹ️ System Information
- OS version and system details
- PATH configuration
- Environment variables
- Shell aliases
- macOS system defaults

## Usage

### Basic Usage (Uses Default Directory)
```bash
./export-system-config.sh
```

### Custom Output Directory
```bash
./export-system-config.sh /path/to/output/directory
```

### Re-run to Update
The script can be run multiple times. It will overwrite previous exports:
```bash
cd ~/Github/Github_desktop
rm -rf dog-files dog-files.tar.gz
~/export-system-config.sh
```

## Output Structure

```
dog-files/
├── README.md                    # Restoration instructions
├── packages/                    # Package lists
│   ├── Brewfile                 # brew bundle restore
│   ├── brew-formulae.txt
│   ├── brew-casks.txt
│   ├── npm-global.txt
│   ├── pip3-packages.txt
│   └── ...
├── dotfiles/                    # Shell and app dotfiles
│   ├── .zshrc
│   ├── .gitconfig
│   ├── .vimrc
│   └── ...
├── browser-profiles/            # Browser data
│   ├── BROWSER-README.md        # Security warnings
│   ├── Chrome/
│   ├── Firefox/
│   ├── Safari/
│   └── Arc/
├── config-dirs/                 # ~/.config directories
├── applications/                # App lists
├── system-info/                 # System metadata
└── dog-files.tar.gz            # Compressed archive
```

## Migrating to Parrot OS

### 1. Transfer the Archive
```bash
# From macOS
scp ~/Github/Github_desktop/dog-files.tar.gz user@parrot-machine:~/

# Or use a USB drive, cloud storage, etc.
```

### 2. Extract on Parrot OS
```bash
tar -xzf dog-files.tar.gz
cd dog-files
```

### 3. Review the README
```bash
cat README.md
```

### 4. Adapt Configurations

#### Package Installation
Homebrew packages need to be mapped to APT packages:
```bash
# Example mapping:
# macOS (brew)     → Parrot OS (apt)
# git              → git
# vim              → vim
# node             → nodejs
# python3          → python3
```

#### Shell Configuration
```bash
# Copy dotfiles
cp dotfiles/.zshrc ~/.zshrc
cp dotfiles/.vimrc ~/.vimrc
cp dotfiles/.gitconfig ~/.gitconfig

# Review and edit paths for Linux
vim ~/.zshrc  # Update macOS-specific paths
```

#### Browser Profiles
```bash
# Chrome on Linux
cp browser-profiles/Chrome/Bookmarks ~/.config/google-chrome/Default/

# Firefox on Linux
cp -r browser-profiles/Firefox/Profiles/* ~/.mozilla/firefox/
```

## Security Considerations

### Sensitive Data Exported
- ⚠️ Browser cookies (session tokens)
- ⚠️ SSH config (no keys, but config may reveal info)
- ⚠️ AWS configuration (may contain credentials)
- ⚠️ Docker configuration
- ⚠️ Environment variables (filtered, but review)

### Before Sharing or Committing
```bash
# Review for sensitive data
grep -r "password\|secret\|token" dog-files/
grep -r "api_key\|private" dog-files/

# Remove sensitive files if needed
rm dog-files/config-dirs/.aws/credentials
rm dog-files/browser-profiles/Chrome/Cookies
```

### Best Practices
1. Store the archive in a secure location
2. Encrypt the archive if transferring over network
3. Don't commit to public repositories
4. Review BROWSER-README.md for browser data warnings
5. Clean cookies/sessions before long-term storage

## Encryption (Optional)

### Encrypt the Archive
```bash
# Using GPG
gpg -c dog-files.tar.gz
# Creates dog-files.tar.gz.gpg

# Using OpenSSL
openssl enc -aes-256-cbc -salt -in dog-files.tar.gz -out dog-files.tar.gz.enc
```

### Decrypt
```bash
# GPG
gpg dog-files.tar.gz.gpg

# OpenSSL
openssl enc -d -aes-256-cbc -in dog-files.tar.gz.enc -out dog-files.tar.gz
```

## Automation

### Schedule Regular Backups
Add to crontab:
```bash
# Backup weekly on Sunday at 2 AM
0 2 * * 0 /Users/henry/export-system-config.sh ~/Backups/system-backup-$(date +\%Y\%m\%d)
```

### Pre-commit Hook
Run before major system changes:
```bash
#!/bin/bash
echo "Creating system backup..."
~/export-system-config.sh ~/Backups/pre-update-backup
```

## Troubleshooting

### Script Fails
- Ensure you have read permissions for all directories
- Close browsers before export (for locked files)
- Check disk space (requires ~200MB)

### Missing Browsers
- Script only exports installed browsers
- Check `browser-profiles/` for what was found

### VS Code Extensions Not Exported
- Install VS Code command line tools
- Restart terminal and try again

## Support

For issues or improvements:
1. Check the script output for warnings
2. Review error messages
3. Ensure all paths exist and are accessible

## Example Workflow

```bash
# 1. Run export
./export-system-config.sh

# 2. Verify contents
ls -lh ~/Github/Github_desktop/dog-files/
cat ~/Github/Github_desktop/dog-files/README.md

# 3. Transfer to Parrot OS
scp dog-files.tar.gz user@parrot:~/

# 4. On Parrot OS
tar -xzf dog-files.tar.gz
cd dog-files

# 5. Install packages
cat packages/brew-formulae.txt  # Review what was installed
sudo apt install git vim curl wget  # Install equivalents

# 6. Restore dotfiles
cp dotfiles/.zshrc ~/.zshrc
source ~/.zshrc

# 7. Import browser bookmarks manually through browser UI
```

## Notes

- The export includes 265 Homebrew formulae and 6 casks
- Browser data includes multiple profiles where applicable
- Archive size: ~45MB compressed, ~168MB uncompressed
- Safe to run multiple times (overwrites previous export)
