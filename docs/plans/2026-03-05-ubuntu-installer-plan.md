# Ubuntu/Kali/Parrot Installer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the dot-files bootstrap to fully support Ubuntu 22.04+, Kali, and Parrot with a unified entry point, FZF configuration wizard, and cross-platform shell portability layer.

**Architecture:** Three layers — (1) a platform shim (`shell/platform.zsh`) that abstracts OS-specific commands into `$CLAW_*` variables, (2) an FZF wizard (`scripts/install/wizard.sh`) that lets users pick components saved to a JSON manifest, and (3) a Linux system configurator (`scripts/install/ubuntu.sh`) mirroring the existing `macos.sh`. The existing `bootstrap.sh` gains a Linux flow that installs apt base packages, sets up Linuxbrew for modern CLI tools, and delegates to the wizard for optional components.

**Tech Stack:** Bash, Zsh, apt, Linuxbrew, FZF, GNU Stow, jq

---

### Task 1: Create `shell/platform.zsh` — OS Portability Shim

**Files:**
- Create: `shell/platform.zsh`

**Step 1: Write the platform shim file**

```zsh
# shell/platform.zsh
# Cross-platform shim layer — sourced FIRST by .zshrc
# Provides CLAW_* variables that abstract OS-specific commands

# Detect platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    export CLAW_PLATFORM="macos"
else
    export CLAW_PLATFORM="linux"
fi

# Homebrew path setup
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -f /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
        eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
    fi
fi

# Clipboard commands
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    export CLAW_CLIPBOARD_COPY="pbcopy"
    export CLAW_CLIPBOARD_PASTE="pbpaste"
else
    export CLAW_CLIPBOARD_COPY="xclip -selection clipboard"
    export CLAW_CLIPBOARD_PASTE="xclip -selection clipboard -o"
fi

# Open command
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    export CLAW_OPEN_CMD="open"
else
    export CLAW_OPEN_CMD="xdg-open"
fi

# Local IP command
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    export CLAW_LOCAL_IP_CMD="ipconfig getifaddr en0"
else
    export CLAW_LOCAL_IP_CMD="hostname -I | awk '{print \$1}'"
fi

# Speed test command
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    export CLAW_SPEED_CMD="networkQuality"
else
    export CLAW_SPEED_CMD="speedtest-cli --simple"
fi

# OS info commands (used in TUI fallback header)
if [[ "$CLAW_PLATFORM" == "macos" ]]; then
    export CLAW_OS_NAME_CMD="sw_vers -productName"
    export CLAW_OS_VERSION_CMD="sw_vers -productVersion"
else
    export CLAW_OS_NAME_CMD="lsb_release -si 2>/dev/null || cat /etc/os-release | grep ^NAME | cut -d= -f2 | tr -d '\"'"
    export CLAW_OS_VERSION_CMD="lsb_release -sr 2>/dev/null || cat /etc/os-release | grep ^VERSION_ID | cut -d= -f2 | tr -d '\"'"
fi
```

**Step 2: Verify the file was written correctly**

Run: `head -5 shell/platform.zsh && wc -l shell/platform.zsh`
Expected: File starts with `# shell/platform.zsh` and is ~70 lines

**Step 3: Commit**

```bash
git add shell/platform.zsh
git commit -m "feat: add cross-platform shim layer (platform.zsh)"
```

---

### Task 2: Update `.zshrc` — Source Platform Shim and Use `$HOMEBREW_PREFIX`

**Files:**
- Modify: `.zshrc` (lines 1-57)

**Step 1: Add platform.zsh source as the very first import**

In `.zshrc`, add `source $HOME/.dotfiles/shell/platform.zsh` as step 0, BEFORE `exports.zsh`:

```zsh
# 0. Platform shim (sets CLAW_PLATFORM, Homebrew paths, CLAW_* variables)
source $HOME/.dotfiles/shell/platform.zsh
```

This goes above line 4 (current `# 1. Source exports first`).

**Step 2: Replace hardcoded `/opt/homebrew` paths with `$HOMEBREW_PREFIX`**

In `.zshrc` lines 37-42, replace the zsh plugin sourcing:

OLD (lines 37-42):
```zsh
# 7. Syntax Highlighting & Autosuggestions (if installed via brew)
if [ -d /opt/homebrew/share/zsh-syntax-highlighting ]; then
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
if [ -d /opt/homebrew/share/zsh-autosuggestions ]; then
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
```

NEW:
```zsh
# 7. Syntax Highlighting & Autosuggestions (via Homebrew — works on macOS and Linux)
local _zsh_hl="${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
[[ -f "$_zsh_hl" ]] && source "$_zsh_hl"
local _zsh_as="${HOMEBREW_PREFIX}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "$_zsh_as" ]] && source "$_zsh_as"
```

**Note:** The `local` keyword works here because these lines execute at the top-level scope of zsh (not inside a function). If this causes issues, inline the variable: `[[ -f "${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && source "${HOMEBREW_PREFIX}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"`.

**Step 3: Verify `.zshrc` sources platform.zsh first**

Run: `head -8 .zshrc`
Expected: First source line is `platform.zsh`

**Step 4: Commit**

```bash
git add .zshrc
git commit -m "feat: source platform.zsh first, use HOMEBREW_PREFIX for plugins"
```

---

### Task 3: Update `shell/aliases.zsh` — Replace macOS-only Commands with Shims

**Files:**
- Modify: `shell/aliases.zsh` (lines 42-43, 660, 698-699)

**Step 1: Replace `localip` alias (line 660)**

OLD (line 660):
```zsh
alias localip='ipconfig getifaddr en0'
```

NEW:
```zsh
alias localip='eval $CLAW_LOCAL_IP_CMD'
```

**Step 2: Replace `sshcopy` function (lines 697-700)**

OLD (lines 697-700):
```zsh
sshcopy() {
    cat ~/.ssh/id_rsa.pub | pbcopy
    echo "SSH public key copied to clipboard"
}
```

NEW:
```zsh
sshcopy() {
    if [[ -f ~/.ssh/id_ed25519.pub ]]; then
        cat ~/.ssh/id_ed25519.pub | eval $CLAW_CLIPBOARD_COPY
    elif [[ -f ~/.ssh/id_rsa.pub ]]; then
        cat ~/.ssh/id_rsa.pub | eval $CLAW_CLIPBOARD_COPY
    else
        echo "No SSH public key found."
        return 1
    fi
    echo "SSH public key copied to clipboard"
}
```

**Step 3: Verify no remaining `pbcopy`/`ipconfig` references in aliases.zsh**

Run: `grep -n 'pbcopy\|pbpaste\|ipconfig\|networkQuality\|sw_vers' shell/aliases.zsh`
Expected: No matches (all replaced with shims)

**Step 4: Commit**

```bash
git add shell/aliases.zsh
git commit -m "feat: replace macOS-only commands with CLAW_* shims in aliases"
```

---

### Task 4: Update `shell/obsidian.zsh` — Use `$CLAW_OPEN_CMD`

**Files:**
- Modify: `shell/obsidian.zsh` (lines 12, 34, 42, 50)

**Step 1: Replace `open -a "Obsidian"` with `$CLAW_OPEN_CMD`**

Line 12 — OLD:
```zsh
alias obs='open -a "Obsidian"'
```
NEW:
```zsh
alias obs='eval $CLAW_OPEN_CMD "obsidian://"'
```

**Step 2: Replace `open "obsidian://..."` calls in functions**

Line 34 — OLD:
```zsh
    open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file=$(urlencode "$note_name")"
```
NEW:
```zsh
    eval $CLAW_OPEN_CMD "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file=$(urlencode "$note_name")"
```

Line 42 — OLD:
```zsh
        cd "$OBSIDIAN_VAULT" && fzf --preview 'bat --style=numbers --color=always {}' | xargs -I {} open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file={}"
```
NEW:
```zsh
        cd "$OBSIDIAN_VAULT" && fzf --preview 'bat --style=numbers --color=always {}' | xargs -I {} eval $CLAW_OPEN_CMD "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file={}"
```

Line 50 — OLD:
```zsh
              --bind 'enter:become(open "obsidian://open?vault=$(basename "$OBSIDIAN_VAULT")&file={1}")'
```
NEW:
```zsh
              --bind "enter:become(eval $CLAW_OPEN_CMD \"obsidian://open?vault=\$(basename $OBSIDIAN_VAULT)&file={1}\")"
```

**Step 3: Verify no remaining hardcoded `open` calls**

Run: `grep -n "^alias.*='open " shell/obsidian.zsh && grep -n '[^$]open "obsidian' shell/obsidian.zsh`
Expected: No matches

**Step 4: Commit**

```bash
git add shell/obsidian.zsh
git commit -m "feat: use CLAW_OPEN_CMD in obsidian.zsh for cross-platform"
```

---

### Task 5: Update `tmux/.tmux.conf` — OS-conditional Clipboard

**Files:**
- Modify: `tmux/.tmux.conf` (lines 28-33)

**Step 1: Replace macOS-only clipboard bindings**

OLD (lines 28-33):
```
# 3. macOS Clipboard Integration
set -g set-clipboard on
# Use pbcopy for copy
bind-key -T copy-mode-vi v send-keys -X begin-selection
bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel "pbcopy"
bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"
```

NEW:
```
# 3. Clipboard Integration (cross-platform)
set -g set-clipboard on
bind-key -T copy-mode-vi v send-keys -X begin-selection
if-shell "uname | grep -q Darwin" \
    "bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'pbcopy'" \
    "bind-key -T copy-mode-vi y send-keys -X copy-pipe-and-cancel 'xclip -selection clipboard'"
if-shell "uname | grep -q Darwin" \
    "bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'pbcopy'" \
    "bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel 'xclip -selection clipboard'"
```

**Step 2: Verify the file is valid tmux config**

Run: `grep -c 'if-shell' tmux/.tmux.conf`
Expected: 2 (two if-shell blocks)

**Step 3: Commit**

```bash
git add tmux/.tmux.conf
git commit -m "feat: cross-platform clipboard in tmux (pbcopy/xclip)"
```

---

### Task 6: Update `shell/welcome-tui.zsh` — Use Shims in Fallback Header

**Files:**
- Modify: `shell/welcome-tui.zsh` (lines 42-43)

**Step 1: Replace macOS-specific commands in fallback header**

OLD (lines 42-43):
```zsh
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(sw_vers -productName 2>/dev/null || echo 'System') $(sw_vers -productVersion 2>/dev/null) · $(uname -m)${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(date '+%a %b %d %H:%M') · $(ipconfig getifaddr en0 2>/dev/null || echo 'offline')${c_reset}"
```

NEW:
```zsh
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(eval $CLAW_OS_NAME_CMD 2>/dev/null || echo 'System') $(eval $CLAW_OS_VERSION_CMD 2>/dev/null) · $(uname -m)${c_reset}"
        echo "  ${c_purple}│${c_reset}   ${c_dim}$(date '+%a %b %d %H:%M') · $(eval $CLAW_LOCAL_IP_CMD 2>/dev/null || echo 'offline')${c_reset}"
```

**Step 2: Verify no remaining macOS-only commands in welcome-tui.zsh**

Run: `grep -n 'sw_vers\|ipconfig\|pbcopy\|networkQuality' shell/welcome-tui.zsh`
Expected: No matches

**Step 3: Commit**

```bash
git add shell/welcome-tui.zsh
git commit -m "feat: use CLAW_* shims in welcome TUI fallback header"
```

---

### Task 7: Update `scripts/utils/toolkit.sh` — Cross-platform Utilities

**Files:**
- Modify: `scripts/utils/toolkit.sh` (lines 193-198, 200)

**Step 1: Replace `pbcopy` in SSH key copy (lines 193-198)**

OLD:
```bash
            if [[ -f ~/.ssh/id_rsa.pub ]]; then
                cat ~/.ssh/id_rsa.pub | pbcopy && echo "✅ Copied id_rsa.pub to clipboard"
            elif [[ -f ~/.ssh/id_ed25519.pub ]]; then
                cat ~/.ssh/id_ed25519.pub | pbcopy && echo "✅ Copied id_ed25519.pub to clipboard"
```

NEW:
```bash
            local _clip="${CLAW_CLIPBOARD_COPY:-pbcopy}"
            if [[ -f ~/.ssh/id_ed25519.pub ]]; then
                cat ~/.ssh/id_ed25519.pub | eval $_clip && echo "✅ Copied id_ed25519.pub to clipboard"
            elif [[ -f ~/.ssh/id_rsa.pub ]]; then
                cat ~/.ssh/id_rsa.pub | eval $_clip && echo "✅ Copied id_rsa.pub to clipboard"
```

**Step 2: Replace `networkQuality` with shim (line 200)**

OLD:
```bash
            3) networkQuality ;;
```

NEW:
```bash
            3) eval "${CLAW_SPEED_CMD:-networkQuality}" ;;
```

**Step 3: Replace `open -a` in Obsidian section (line 246)**

OLD (line 246):
```bash
                obsidian open vault="$vault_name" || open -a "Obsidian"
```

NEW:
```bash
                obsidian open vault="$vault_name" || eval "${CLAW_OPEN_CMD:-open}" "obsidian://"
```

**Step 4: Replace `pan-docs` in cortex profile (line 47 of cortex.zsh)**

In `shell/profiles/cortex.zsh` line 47-49, replace `open` with `eval $CLAW_OPEN_CMD`:

OLD:
```zsh
alias pan-docs="open https://pan.dev"
alias cortex-docs="open https://docs.paloaltonetworks.com/cortex"
alias xsoar-docs="open https://xsoar.pan.dev"
```

NEW:
```zsh
alias pan-docs='eval $CLAW_OPEN_CMD "https://pan.dev"'
alias cortex-docs='eval $CLAW_OPEN_CMD "https://docs.paloaltonetworks.com/cortex"'
alias xsoar-docs='eval $CLAW_OPEN_CMD "https://xsoar.pan.dev"'
```

**Step 5: Commit**

```bash
git add scripts/utils/toolkit.sh shell/profiles/cortex.zsh
git commit -m "feat: cross-platform clipboard/open in toolkit and cortex profile"
```

---

### Task 8: Create `scripts/install/wizard.sh` — FZF Configuration Wizard

**Files:**
- Create: `scripts/install/wizard.sh`

**Step 1: Write the wizard script**

```bash
#!/usr/bin/env bash
# scripts/install/wizard.sh
# Interactive FZF-based component selection wizard for dot-files installer.
# Saves selections to ~/.config/claw/install-manifest.json
# Rerun with --wizard flag to re-select.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/detect-os.sh"
detect_os

MANIFEST_DIR="$HOME/.config/claw"
MANIFEST_FILE="$MANIFEST_DIR/install-manifest.json"

# Check for FZF
if ! command -v fzf &> /dev/null; then
    log_warning "fzf not found — installing defaults without wizard"
    mkdir -p "$MANIFEST_DIR"
    cat > "$MANIFEST_FILE" <<'EOF'
{
  "components": ["core_shell", "modern_cli"],
  "generated": "auto-default",
  "os": "unknown"
}
EOF
    return 0 2>/dev/null || exit 0
fi

# Component definitions: key|label|default_state
# default_state: "on" = pre-selected, "off" = not pre-selected
COMPONENTS=(
    "core_shell|Core Shell (zsh, starship, fzf, zoxide, atuin)|on"
    "modern_cli|Modern CLI (eza, bat, ripgrep, fd, btop, lazygit)|on"
    "development|Development (node, python, go, rust, databases)|off"
    "devops|DevOps (docker, kubectl, helm, k9s, terraform)|off"
    "cloud|Cloud (awscli, gcloud, azure-cli)|off"
    "security|Security (nmap, trivy, grype, metasploit)|off"
    "ai_ml|AI/ML (ollama, pipx AI tools, huggingface-cli)|off"
    "research|Research (csvkit, pandoc, yt-dlp)|off"
    "cortex|Cortex (demisto-sdk, panos-cli)|off"
)

# Auto-enable security on Kali/Parrot
if [[ "$OS_TYPE" == "kali" || "$OS_TYPE" == "parrot" ]]; then
    for i in "${!COMPONENTS[@]}"; do
        if [[ "${COMPONENTS[$i]}" == security* ]]; then
            COMPONENTS[$i]="security|Security (nmap, trivy, grype, metasploit)|on"
        fi
    done
fi

# Build FZF input: pre-select items marked "on"
fzf_input=""
preselected=()
for comp in "${COMPONENTS[@]}"; do
    IFS='|' read -r key label state <<< "$comp"
    fzf_input+="$key  $label"$'\n'
    if [[ "$state" == "on" ]]; then
        preselected+=("$key")
    fi
done

# Build --bind for pre-selection (select lines starting with keys marked "on")
log_info "Select components to install (TAB to toggle, ENTER to confirm):"
echo ""

selected=$(echo -e "$fzf_input" | fzf \
    --multi \
    --height=14 \
    --reverse \
    --prompt="Components ▶ " \
    --header="  TAB toggle · ENTER confirm · core_shell always included" \
    --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950" \
    --bind="start:select-all" \
    || echo "core_shell")

# Always include core_shell
if ! echo "$selected" | grep -q "core_shell"; then
    selected="core_shell  Core Shell (zsh, starship, fzf, zoxide, atuin)
$selected"
fi

# Extract just the keys (first field)
selected_keys=()
while IFS= read -r line; do
    key=$(echo "$line" | awk '{print $1}')
    [[ -n "$key" ]] && selected_keys+=("$key")
done <<< "$selected"

# Save manifest
mkdir -p "$MANIFEST_DIR"
{
    echo "{"
    echo "  \"components\": ["
    for i in "${!selected_keys[@]}"; do
        if [[ $i -lt $((${#selected_keys[@]} - 1)) ]]; then
            echo "    \"${selected_keys[$i]}\","
        else
            echo "    \"${selected_keys[$i]}\""
        fi
    done
    echo "  ],"
    echo "  \"os\": \"$OS_TYPE\","
    echo "  \"generated\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\""
    echo "}"
} > "$MANIFEST_FILE"

log_success "Manifest saved to $MANIFEST_FILE"
log_info "Selected: ${selected_keys[*]}"
echo ""
```

**Step 2: Make executable and verify**

Run: `chmod +x scripts/install/wizard.sh && head -5 scripts/install/wizard.sh`
Expected: Shebang line visible, file is executable

**Step 3: Commit**

```bash
git add scripts/install/wizard.sh
git commit -m "feat: add FZF configuration wizard for component selection"
```

---

### Task 9: Create `scripts/install/linuxbrew.sh` — Linuxbrew Installer

**Files:**
- Create: `scripts/install/linuxbrew.sh`

**Step 1: Write the Linuxbrew installer**

```bash
#!/usr/bin/env bash
# scripts/install/linuxbrew.sh
# Install Linuxbrew (Homebrew for Linux)
# Provides consistent tool names matching macOS (eza not exa, bat not batcat, fd not fdfind)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logger.sh"

install_linuxbrew() {
    if command -v brew &> /dev/null; then
        log_success "Linuxbrew already installed"
        brew update
        return
    fi

    log_info "Installing Linuxbrew..."

    # Prerequisites
    sudo apt install -y build-essential procps curl file git

    # Install Homebrew (official installer supports Linux)
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add to PATH for this session
    if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    elif [[ -f "$HOME/.linuxbrew/bin/brew" ]]; then
        eval "$("$HOME/.linuxbrew/bin/brew" shellenv)"
    fi

    # Verify
    if command -v brew &> /dev/null; then
        log_success "Linuxbrew installed successfully"
        brew --version
    else
        log_error "Linuxbrew installation failed"
        exit 1
    fi
}

install_linuxbrew
```

**Step 2: Make executable**

Run: `chmod +x scripts/install/linuxbrew.sh`

**Step 3: Commit**

```bash
git add scripts/install/linuxbrew.sh
git commit -m "feat: add Linuxbrew installer script"
```

---

### Task 10: Create `scripts/install/packages/linux-repos.sh` — Official Apt Repos

**Files:**
- Create: `scripts/install/packages/linux-repos.sh`

**Step 1: Write the apt repository setup script**

```bash
#!/usr/bin/env bash
# scripts/install/packages/linux-repos.sh
# Add official apt repositories for tools not available in Ubuntu defaults.
# Only runs on apt-based distros (Ubuntu, Kali, Parrot, Debian).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../utils/logger.sh"
source "$SCRIPT_DIR/../../utils/detect-os.sh"
detect_os

if [[ "$PKG_MANAGER" != "apt" ]]; then
    log_info "Not an apt-based distro — skipping repo setup"
    return 0 2>/dev/null || exit 0
fi

log_info "Adding official apt repositories..."

# Docker (Ubuntu only — Kali/Parrot have their own)
if [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" ]]; then
    if ! command -v docker &> /dev/null; then
        log_info "Adding Docker official repo..."
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
fi

# GitHub CLI
if ! command -v gh &> /dev/null; then
    log_info "Adding GitHub CLI repo..."
    (type -p wget >/dev/null || sudo apt install -y wget) \
        && sudo mkdir -p -m 755 /etc/apt/keyrings \
        && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
        && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
        && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
fi

# kubectl (Kubernetes)
if ! command -v kubectl &> /dev/null; then
    log_info "Adding Kubernetes repo..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
fi

# Trivy (vulnerability scanner)
if ! command -v trivy &> /dev/null; then
    log_info "Adding Trivy repo..."
    sudo apt install -y apt-transport-https gnupg
    wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
fi

# Update apt after adding repos
sudo apt update

log_success "Apt repositories configured"
```

**Step 2: Make executable**

Run: `chmod +x scripts/install/packages/linux-repos.sh`

**Step 3: Commit**

```bash
git add scripts/install/packages/linux-repos.sh
git commit -m "feat: add official apt repo setup for Docker, GH CLI, kubectl, Trivy"
```

---

### Task 11: Create `scripts/install/ubuntu.sh` — Linux System Configuration

**Files:**
- Create: `scripts/install/ubuntu.sh`

**Step 1: Write the Linux system configurator**

```bash
#!/usr/bin/env bash
# scripts/install/ubuntu.sh
# System-level configuration for Ubuntu/Kali/Parrot
# Mirrors macos.sh — sets shell, firewall, SSH hardening, GNOME tweaks, sysctl

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../utils/logger.sh"
source "$SCRIPT_DIR/../utils/detect-os.sh"
detect_os

log_info "Configuring Linux system ($OS_TYPE)..."

# 1. Set default shell to Zsh
if [[ "$SHELL" != *"zsh"* ]]; then
    log_info "Setting default shell to Zsh..."
    if command -v zsh &> /dev/null; then
        chsh -s "$(which zsh)"
        log_success "Default shell set to Zsh (takes effect on next login)"
    else
        log_error "Zsh not installed — cannot set as default shell"
    fi
else
    log_info "Zsh is already the default shell"
fi

# 2. UFW Firewall (Ubuntu only — Kali/Parrot have their own security posture)
if [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" ]]; then
    if command -v ufw &> /dev/null; then
        log_info "Configuring UFW firewall..."
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw --force enable
        log_success "UFW firewall enabled (deny incoming, allow outgoing, allow SSH)"
    fi
fi

# 3. SSH Hardening (Ubuntu only)
if [[ "$OS_TYPE" == "ubuntu" || "$OS_TYPE" == "debian" ]]; then
    local sshd_config="/etc/ssh/sshd_config"
    if [[ -f "$sshd_config" ]]; then
        log_info "Hardening SSH configuration..."
        sudo cp "$sshd_config" "${sshd_config}.bak.$(date +%s)"

        # Disable password auth (key-only)
        sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"
        # Disable root login
        sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$sshd_config"

        sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart 2>/dev/null
        log_success "SSH hardened: PasswordAuthentication=no, PermitRootLogin=no"
    fi
fi

# 4. GNOME Tweaks (if desktop environment detected)
if command -v gsettings &> /dev/null && [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
    log_info "Applying GNOME desktop tweaks..."

    # Show hidden files in file manager
    gsettings set org.gtk.Settings.FileChooser show-hidden true 2>/dev/null || true

    # Dark theme
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true

    # Keyboard repeat speed (faster)
    gsettings set org.gnome.desktop.peripherals.keyboard delay 250 2>/dev/null || true
    gsettings set org.gnome.desktop.peripherals.keyboard repeat-interval 30 2>/dev/null || true

    log_success "GNOME tweaks applied"
else
    log_info "No desktop environment detected — skipping GNOME tweaks"
fi

# 5. Sysctl Tuning
log_info "Applying sysctl performance tuning..."
sudo tee /etc/sysctl.d/99-claw-tuning.conf > /dev/null <<EOF
# CLAW dot-files sysctl tuning
net.core.somaxconn = 1024
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 256
EOF
sudo sysctl --system > /dev/null 2>&1
log_success "Sysctl tuning applied"

# 6. Timezone/locale confirmation
log_info "Current timezone: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'unknown')"
log_info "Current locale: $LANG"
echo ""

log_success "Linux system configuration complete ($OS_TYPE)"
```

**Step 2: Make executable**

Run: `chmod +x scripts/install/ubuntu.sh`

**Step 3: Fix the `local` keyword (used outside function)**

In the SSH hardening section, `local sshd_config=...` must be changed to just `sshd_config=...` since this runs at script top-level, not inside a function. Alternatively, wrap the entire script body in a `main()` function.

**Step 4: Commit**

```bash
git add scripts/install/ubuntu.sh
git commit -m "feat: add Linux system config (firewall, SSH, GNOME, sysctl)"
```

---

### Task 12: Update `bootstrap.sh` — Add Linux Flow

**Files:**
- Modify: `bootstrap.sh`

**Step 1: Add `--wizard` flag to argument parser (after line 24)**

Add to the `case` block:
```bash
        --wizard) WIZARD_MODE=true ;;
```

And initialize `WIZARD_MODE=false` near line 16.

**Step 2: Add Linux installation flow to `main()` function (after line 82)**

After the macOS block (lines 79-82), add:

```bash
    # Linux (Ubuntu/Kali/Parrot)
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        log_info "Linux detected ($OS_TYPE) — running apt-based setup"

        # Phase 1: apt base packages
        log_info "Phase 1: Installing apt base packages..."
        sudo apt update
        sudo apt install -y \
            build-essential curl wget git zsh tmux unzip tar tree stow \
            python3 python3-pip python3-venv pipx \
            software-properties-common apt-transport-https ca-certificates gnupg \
            fastfetch xclip

        # Phase 2: Official apt repos (Docker, GH CLI, kubectl, Trivy)
        [[ -f "scripts/install/packages/linux-repos.sh" ]] && source "scripts/install/packages/linux-repos.sh"

        # Phase 3: Install Linuxbrew for modern CLI tools
        source "scripts/install/linuxbrew.sh"

        # Phase 4: Install modern CLI via brew (consistent names)
        [[ -f "scripts/install/packages/modern-cli.sh" ]] && source "scripts/install/packages/modern-cli.sh"
    fi

    # Configuration Wizard (first run or --wizard flag)
    if [[ "$WIZARD_MODE" == "true" || ! -f "$HOME/.config/claw/install-manifest.json" ]]; then
        source "scripts/install/wizard.sh"
    fi

    # Read manifest and install selected toolchains
    if [[ -f "$HOME/.config/claw/install-manifest.json" ]] && command -v jq &> /dev/null; then
        local manifest="$HOME/.config/claw/install-manifest.json"
        if jq -e '.components | index("development")' "$manifest" > /dev/null 2>&1; then
            [[ -f "scripts/install/packages/dev-tools.sh" ]] && source "scripts/install/packages/dev-tools.sh"
        fi
        if jq -e '.components | index("devops")' "$manifest" > /dev/null 2>&1; then
            [[ -f "scripts/install/packages/devops-tools.sh" ]] && source "scripts/install/packages/devops-tools.sh"
        fi
    fi
```

**Step 3: Add Linux system config call (parallel to macOS block)**

After the new Linux block, add:
```bash
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        source "scripts/install/ubuntu.sh"
    fi
```

**Step 4: Update the "Next Steps" output (lines 96-101)**

Update the post-install message to be OS-aware:
```bash
    log_info "Next Steps:"
    echo "  1. Restart your terminal: exec zsh"
    if [[ "$CLAW_PLATFORM" == "linux" ]]; then
        echo "  2. Log out and back in for shell change to take effect."
    else
        echo "  2. Install fonts manually if icons are missing."
    fi
```

**Step 5: Verify the script has both macOS and Linux paths**

Run: `grep -n 'macos\|apt\|linux\|ubuntu' bootstrap.sh`
Expected: Multiple hits showing both OS paths

**Step 6: Commit**

```bash
git add bootstrap.sh
git commit -m "feat: add Linux flow to bootstrap.sh with wizard and apt/brew hybrid"
```

---

### Task 13: Update `scripts/install/brew.sh` — Support Linuxbrew Path

**Files:**
- Modify: `scripts/install/brew.sh` (lines 12-18)

**Step 1: Read current file to check exact content**

Run: `cat scripts/install/brew.sh`

**Step 2: Ensure Linuxbrew path is properly handled**

The `brew.sh` file should already partially handle Linux (from the audit). Verify the PATH setup handles both:
- macOS Apple Silicon: `/opt/homebrew/bin/brew`
- macOS Intel: `/usr/local/bin/brew`
- Linux: `/home/linuxbrew/.linuxbrew/bin/brew`

If not already complete, add the Linux path eval after installation.

**Step 3: Commit (only if changes needed)**

```bash
git add scripts/install/brew.sh
git commit -m "fix: ensure brew.sh handles Linuxbrew path"
```

---

### Task 14: Update Toolchain Scripts — Add apt Fallback Paths

**Files:**
- Modify: `scripts/install/ai-toolchain.sh`
- Modify: `scripts/install/cloud-toolchain.sh`
- Modify: `scripts/install/devops-toolchain.sh`
- Modify: `scripts/install/security-toolchain.sh`
- Modify: `scripts/install/research-toolchain.sh`
- Modify: `scripts/install/cortex-toolchain.sh`

**Step 1: Pattern for each toolchain script**

Each toolchain currently only uses `brew install`. The pattern to apply:

```bash
# At the top of each toolchain, after sourcing logger.sh:
source "$SCRIPT_DIR/../utils/detect-os.sh"
detect_os

# For each tool installation, add OS branching:
if [[ "$PKG_MANAGER" == "brew" ]] || command -v brew &> /dev/null; then
    brew install "$tool" || log_warning "brew: Failed to install $tool"
elif [[ "$PKG_MANAGER" == "apt" ]]; then
    sudo apt install -y "$tool" 2>/dev/null || log_warning "apt: $tool not available"
fi
```

For tools only available via brew (even on Linux), keep `brew install` since Linuxbrew will be available.

**Step 2: Apply to `security-toolchain.sh` (largest, 153 lines)**

Key change: On Kali/Parrot, many security tools are already in the default repos. Add a fast-path:

```bash
if [[ "$OS_TYPE" == "kali" || "$OS_TYPE" == "parrot" ]]; then
    log_info "Kali/Parrot detected — security tools available via apt"
    sudo apt install -y nmap sqlmap hydra john aircrack-ng metasploit-framework \
        gobuster hashcat whatweb wfuzz theharvester nikto 2>/dev/null
fi
```

For Ubuntu, use brew + apt + Trivy from the official repo (set up in `linux-repos.sh`).

**Step 3: Apply to each remaining toolchain**

For `ai-toolchain.sh`: `pipx` tools (openai, anthropic, langchain) work identically. `ollama` has a curl installer. Keep brew for `jq`, `yq`.

For `cloud-toolchain.sh`: `awscli` via pipx, `gcloud` via Google apt repo, `azure-cli` via MS apt repo on Linux. Keep brew on macOS.

For `devops-toolchain.sh`: Docker via apt on Ubuntu. `kubectl` via apt repo. `helm`, `k9s`, `terraform` via brew (even on Linux).

For `research-toolchain.sh`: `pandoc`, `csvkit` available via apt. Rest via brew.

For `cortex-toolchain.sh`: All `pipx` based — works identically on Linux.

**Step 4: Verify each script sources detect-os.sh**

Run: `grep -l 'detect-os' scripts/install/*-toolchain.sh`
Expected: All 6 toolchain files listed

**Step 5: Commit**

```bash
git add scripts/install/*-toolchain.sh
git commit -m "feat: add apt fallback paths to all toolchain scripts"
```

---

### Task 15: Update `scripts/install/master-setup.sh` — Cross-platform Support

**Files:**
- Modify: `scripts/install/master-setup.sh` (header, check_brew, install_extra_tools)

**Step 1: Update header comment**

Line 3 — OLD: `# MacBook Pro Master Setup Script`
NEW: `# Master Setup Script (macOS + Linux)`

**Step 2: Update `check_brew()` function to handle Linuxbrew**

Add Linux Homebrew path setup after the install command (after line 40):

```bash
        # Add to PATH for Linux
        if [[ "$(uname)" == "Linux" ]]; then
            if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
                eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            fi
        fi
```

**Step 3: Guard cask installs (macOS only)**

In `install_shell_tools()` (line 65-72), `install_dev_tools()` (line 99-103), and `install_extra_tools()` (line 133-140), wrap cask installs:

```bash
    if [[ "$(uname)" == "Darwin" ]]; then
        local cask_tools=("iterm2" "wezterm")
        # ... existing cask install loop
    fi
```

Casks are macOS-only (GUI apps). On Linux, skip them.

**Step 4: Commit**

```bash
git add scripts/install/master-setup.sh
git commit -m "feat: make master-setup.sh cross-platform (guard casks, add Linuxbrew)"
```

---

### Task 16: Update `shell/exports.zsh` — Remove macOS-only PATH

**Files:**
- Modify: `shell/exports.zsh`

**Step 1: Check for any macOS-specific PATH entries**

Current file is minimal (5 lines: EDITOR, VISUAL, LANG, LC_ALL). No changes needed unless there are hardcoded macOS paths. The file is already portable.

Run: `cat shell/exports.zsh`
Expected: No macOS-specific content

**Step 2: Commit (only if changes needed)**

If no changes needed, skip this commit.

---

### Task 17: Update `scripts/utils/tool-updater.sh` — Cross-platform Updates

**Files:**
- Modify: `scripts/utils/tool-updater.sh`

**Step 1: The tool-updater was already fixed in the performance audit**

Verify it uses `brew upgrade` (not `cargo install` for core tools) and `command -v` guards. Current version should be cross-platform since:
- `brew upgrade` works on both macOS and Linuxbrew
- `pipx upgrade` works on both
- `go install` works on both
- `cargo install` works on both

Run: `grep -c 'command -v' scripts/utils/tool-updater.sh`
Expected: 4 (one per category: brew, pipx, go, cargo)

**Step 2: Commit (only if changes needed)**

If no changes needed, skip this commit.

---

### Task 18: Final Integration Test Checklist

**Step 1: Verify all new files exist**

Run:
```bash
ls -la shell/platform.zsh \
       scripts/install/wizard.sh \
       scripts/install/ubuntu.sh \
       scripts/install/linuxbrew.sh \
       scripts/install/packages/linux-repos.sh
```
Expected: All 5 files exist and are executable (except platform.zsh which is sourced)

**Step 2: Verify no remaining hardcoded macOS commands in key files**

Run:
```bash
grep -rn 'pbcopy\|pbpaste\|ipconfig getifaddr\|sw_vers\|networkQuality\|open -a' \
    .zshrc shell/aliases.zsh shell/obsidian.zsh shell/welcome-tui.zsh tmux/.tmux.conf \
    scripts/utils/toolkit.sh
```
Expected: No matches (all replaced with shims or conditional blocks)

**Step 3: Shellcheck on new scripts**

Run:
```bash
shellcheck scripts/install/wizard.sh \
           scripts/install/ubuntu.sh \
           scripts/install/linuxbrew.sh \
           scripts/install/packages/linux-repos.sh
```
Expected: No errors (warnings about variable expansion are acceptable)

**Step 4: Verify .zshrc load order is correct**

Run: `grep -n 'source\|eval' .zshrc`
Expected: `platform.zsh` is first, then `exports.zsh`, then everything else

**Step 5: Final commit (if any loose changes)**

```bash
git add -A
git commit -m "chore: final integration cleanup for Ubuntu/Kali/Parrot support"
```

---

## Summary of Deliverables

| # | Task | Files | Est. Time |
|---|------|-------|-----------|
| 1 | Platform shim | Create `shell/platform.zsh` | 5 min |
| 2 | .zshrc update | Modify `.zshrc` | 3 min |
| 3 | Aliases shims | Modify `shell/aliases.zsh` | 5 min |
| 4 | Obsidian shims | Modify `shell/obsidian.zsh` | 5 min |
| 5 | Tmux clipboard | Modify `tmux/.tmux.conf` | 3 min |
| 6 | TUI fallback | Modify `shell/welcome-tui.zsh` | 2 min |
| 7 | Toolkit shims | Modify `scripts/utils/toolkit.sh`, `shell/profiles/cortex.zsh` | 5 min |
| 8 | Wizard | Create `scripts/install/wizard.sh` | 10 min |
| 9 | Linuxbrew | Create `scripts/install/linuxbrew.sh` | 3 min |
| 10 | Apt repos | Create `scripts/install/packages/linux-repos.sh` | 5 min |
| 11 | Ubuntu config | Create `scripts/install/ubuntu.sh` | 5 min |
| 12 | Bootstrap Linux flow | Modify `bootstrap.sh` | 10 min |
| 13 | Brew.sh path | Modify `scripts/install/brew.sh` | 2 min |
| 14 | Toolchain apt fallbacks | Modify 6 `*-toolchain.sh` files | 15 min |
| 15 | Master-setup | Modify `scripts/install/master-setup.sh` | 5 min |
| 16 | Exports check | Verify `shell/exports.zsh` | 1 min |
| 17 | Tool-updater check | Verify `scripts/utils/tool-updater.sh` | 1 min |
| 18 | Integration test | Verify all changes | 5 min |
