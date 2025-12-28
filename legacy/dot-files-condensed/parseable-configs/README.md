# Parseable Configuration Files

This directory contains machine-readable and easily parseable configuration files for migrating your macOS setup to Parrot OS (or any Linux distribution).

## Files Overview

### 📊 Package Manifests

#### `packages.json`
- **Format**: JSON
- **Use case**: Programmatic parsing, automation scripts
- **Contains**: All packages organized by package manager
  - Homebrew formulae (265 packages)
  - Homebrew casks (6 apps)
  - NPM global packages
  - Python pip3 packages
  - Ruby gems

**Example usage:**
```bash
# Parse with jq
cat packages.json | jq '.packages.homebrew_formulae[]'

# Get NPM packages
cat packages.json | jq -r '.packages.npm_global[]'
```

#### `packages.yml`
- **Format**: YAML
- **Use case**: Human-readable, Ansible playbooks, configuration management
- **Contains**: Same data as JSON but in YAML format

**Example usage:**
```bash
# View with yq (YAML processor)
yq '.homebrew_formulae[]' packages.yml

# Use in Ansible playbook
ansible-playbook -e "@packages.yml" your-playbook.yml
```

### 🐧 Linux Migration Tools

#### `macos-to-linux-mapping.txt`
- **Format**: Colon-delimited text (macos_package:linux_package:install_method)
- **Use case**: Manual review, understanding what's available on Linux
- **Contains**: Mapping of macOS packages to Linux equivalents

**Format:**
```
package_name:linux_equivalent:install_method
```

**Install methods:**
- `apt` - Available via APT package manager
- `manual` - Requires manual installation
- `REVIEW_NEEDED` - Needs investigation for Linux alternative

**Example usage:**
```bash
# Find all APT-available packages
grep ':apt$' macos-to-linux-mapping.txt

# Find packages needing review
grep 'REVIEW_NEEDED' macos-to-linux-mapping.txt

# Count by install method
cut -d: -f3 macos-to-linux-mapping.txt | sort | uniq -c
```

#### `install-packages-linux.sh` ⚡
- **Format**: Executable bash script
- **Use case**: Quick installation on Parrot OS
- **Contains**: Auto-generated APT install commands for common tools

**Usage:**
```bash
# Review first!
cat install-packages-linux.sh

# Make executable (if needed)
chmod +x install-packages-linux.sh

# Run on Parrot OS
./install-packages-linux.sh
```

**What it does:**
1. Updates APT package list
2. Installs common CLI tools (git, vim, tmux, curl, wget, etc.)
3. Installs Node.js, Python3, Ruby
4. Installs NPM global packages
5. Installs Python packages from requirements

### 🏠 Dotfiles Tools

#### `install-dotfiles.sh` ⚡
- **Format**: Executable bash script
- **Use case**: Safe dotfiles installation with backup
- **Contains**: Commands to backup and install all exported dotfiles

**Usage:**
```bash
# Review what will be installed
cat install-dotfiles.sh

# Run the installer
./install-dotfiles.sh
```

**Safety features:**
- Creates timestamped backup of existing dotfiles
- Copies dotfiles from export to home directory
- Shows what was backed up and installed

**Dotfiles included:**
- `.zshrc`, `.zprofile`
- `.vimrc`, `.vim/`
- `.gitconfig`
- `.yarnrc`
- `.ssh/config`

### 🛠️ System Information

#### `cli-tools-inventory.csv`
- **Format**: CSV
- **Use case**: Spreadsheet import, version tracking, dependency auditing
- **Contains**: All detected CLI tools with versions and locations

**Columns:**
1. Tool name
2. Version string
3. Installation path

**Example usage:**
```bash
# View in terminal
column -t -s, cli-tools-inventory.csv

# Import to Excel/Google Sheets
# Just open the file

# Find specific tool
grep 'docker' cli-tools-inventory.csv

# Count total tools
wc -l cli-tools-inventory.csv
```

**Detected tools include:**
- git (2.51.0)
- vim (9.1)
- tmux
- zsh (5.9)
- bash (5.3.3)
- python3 (3.14.0)
- node (v24.10.0)
- npm (11.6.0)
- docker
- kubectl
- aws-cli
- gcloud
- terraform (1.5.7)

#### `environment.sh`
- **Format**: Shell-sourceable script
- **Use case**: Restore PATH and environment variables
- **Contains**: Exported PATH, SHELL, and aliases (commented)

**Usage:**
```bash
# Review first
cat environment.sh

# Source in current shell
source environment.sh

# Or add to .bashrc/.zshrc
echo 'source ~/path/to/environment.sh' >> ~/.zshrc
```

## Quick Start Workflows

### 🚀 Complete Migration to Parrot OS

```bash
# 1. Transfer archive to Parrot OS
scp dog-files.tar.gz user@parrot:~/

# 2. On Parrot OS, extract
tar -xzf dog-files.tar.gz
cd dog-files/parseable-configs

# 3. Install packages
chmod +x install-packages-linux.sh
./install-packages-linux.sh

# 4. Install dotfiles
chmod +x install-dotfiles.sh
./install-dotfiles.sh

# 5. Source environment
source environment.sh

# 6. Review packages needing manual install
grep 'REVIEW_NEEDED\|manual' macos-to-linux-mapping.txt
```

### 🔍 Selective Package Installation

```bash
# View all packages in JSON
cat packages.json | jq '.packages'

# Install specific category
cat packages.json | jq -r '.packages.homebrew_formulae[]' | while read pkg; do
    # Look up in mapping
    grep "^$pkg:" macos-to-linux-mapping.txt
done

# Install only development tools
sudo apt install git vim tmux curl wget jq tree htop
```

### 📝 Ansible Automation

```yaml
# playbook.yml
---
- hosts: localhost
  vars_files:
    - packages.yml
  tasks:
    - name: Install APT packages
      apt:
        name: "{{ item }}"
        state: present
      loop: "{{ homebrew_formulae }}"
      when: item in ['git', 'vim', 'tmux', 'curl', 'wget']
      become: yes
```

### 🐍 Python Script to Parse

```python
import json

# Load packages
with open('packages.json') as f:
    data = json.load(f)

# Print all Homebrew formulae
for pkg in data['packages']['homebrew_formulae']:
    print(f"- {pkg}")

# Export to requirements
npm_packages = data['packages']['npm_global']
with open('requirements.txt', 'w') as f:
    for pkg in npm_packages:
        f.write(f"{pkg}\n")
```

## File Sizes

```
packages.json                    6.2 KB
packages.yml                     3.7 KB
macos-to-linux-mapping.txt       7.6 KB
cli-tools-inventory.csv          1.3 KB
environment.sh                   658 B
install-packages-linux.sh        806 B
install-dotfiles.sh              1.4 KB
```

## Important Notes

### Security
- Review all scripts before executing
- The install scripts use `sudo` - understand what they do
- Environment variables are filtered, but review `environment.sh`

### Package Availability
- Not all macOS packages have Linux equivalents
- Some may have different names on Linux
- Check `macos-to-linux-mapping.txt` for mappings
- Packages marked `REVIEW_NEEDED` require manual investigation

### Version Differences
- Linux packages may be different versions
- Check compatibility for your use case
- CLI tools inventory shows macOS versions for reference

### Parrot OS Specific
- Parrot OS is Debian-based, so APT commands work
- Some security tools may already be installed
- Review existing packages: `dpkg -l`

## Advanced Usage

### Generate Custom Install Script

```bash
# Create install script for only development tools
cat packages.json | jq -r '.packages.homebrew_formulae[]' | \
  grep -E 'git|vim|node|python' | \
  awk '{print "sudo apt install -y " $0}' > install-dev.sh
```

### Compare Installed vs Exported

```bash
# On Linux, compare what you have vs export
comm -3 \
  <(dpkg -l | awk '{print $2}' | sort) \
  <(cat packages.yml | grep '^  - ' | sed 's/  - //' | sort)
```

### Export to Other Formats

```bash
# Convert to plain list
cat packages.json | jq -r '.packages.homebrew_formulae[]' > brew-list.txt

# Convert to Markdown checklist
cat packages.yml | grep '^  - ' | sed 's/^  - /- [ ] /' > todo.md
```

## Troubleshooting

### Script Won't Execute
```bash
chmod +x install-packages-linux.sh install-dotfiles.sh
```

### JSON/YAML Parsing Errors
```bash
# Validate JSON
cat packages.json | jq empty

# Validate YAML
cat packages.yml | python3 -c 'import yaml, sys; yaml.safe_load(sys.stdin)'
```

### Missing Dependencies
Some scripts assume tools are installed:
- `jq` for JSON parsing: `sudo apt install jq`
- `yq` for YAML parsing: `sudo snap install yq`

## Related Files

- `../packages/` - Original package lists (human-readable)
- `../dotfiles/` - Actual dotfile contents
- `../README.md` - Main migration guide
- `../BROWSER-README.md` - Browser data info

## Next Steps

1. ✅ Review all parseable config files
2. ✅ Test install scripts in a VM first
3. ✅ Check package mappings for your specific needs
4. ✅ Customize scripts as needed
5. ✅ Run installations on Parrot OS
6. ✅ Verify everything works

---

**Generated by**: export-system-config.sh
**Export Date**: Check `packages.json` for exact timestamp
**Source OS**: macOS
**Target OS**: Parrot Linux / Debian-based distributions
