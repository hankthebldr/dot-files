#!/usr/bin/env bash
# scripts/utils/homelab.sh
# Interactive Home Lab SSH Topology Manager

# Theme Colors (GitHub macOS Dark)
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_dim=$'\e[38;2;139;148;158m'
c_red=$'\e[38;2;255;123;114m'

SSH_CONFIG="$HOME/.ssh/config"

# Non-interactive subcommands delegate to the situation poller.
# Bare `homelab.sh` (no args) keeps the interactive fzf topology launcher.
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
case "${1:-}" in
    poll)   exec bash "$DOTFILES_DIR/scripts/utils/situation.sh" homelab ;;
    status) # refresh the fleet cache, then pretty-print it (the HR-TRUST fleet,
            # NOT situation.json). Two separate commands — the poll must NOT be
            # `exec` (that would replace the process and the print never runs).
            bash "$DOTFILES_DIR/scripts/utils/situation.sh" homelab; _rc=$?
            jq . "${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json" 2>/dev/null \
              || cat "${XDG_CACHE_HOME:-$HOME/.cache}/claw/homelab.json" 2>/dev/null \
              || echo "no homelab cache"
            exit "$_rc" ;;
esac

echo "${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
echo "${c_purple}│${c_reset}  ${c_cyan}📡 HOMELAB TOPOLOGY MANAGER${c_reset}                           ${c_purple}│${c_reset}"
echo "${c_purple}├────────────────────────────────────────────────────────┤${c_reset}"
echo "${c_purple}│${c_reset}  ${c_dim}Parsing active nodes from ~/.ssh/config...${c_reset}            ${c_purple}│${c_reset}"
echo "${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
echo ""

if [[ ! -f "$SSH_CONFIG" ]]; then
    echo "${c_red}Error: No ~/.ssh/config file found. Please create one to manage your topology.${c_reset}"
    exit 1
fi

# Ensure fzf is available
if ! command -v fzf &> /dev/null; then
    echo "${c_red}Error: fzf is required for the interactive Homelab manager.${c_reset}"
    exit 1
fi

# Parse the SSH config file for Host configurations (ignore wildcards)
# We grep for lines starting with 'Host ' and exclude '*'
# Then format it nicely for fzf
hosts=$(awk '/^Host [^*]/ {print $2}' "$SSH_CONFIG")

if [[ -z "$hosts" ]]; then
    echo "${c_red}No explicit hosts found in ~/.ssh/config.${c_reset}"
    exit 1
fi

# Launch fzf with a preview window that shows the specific SSH block config for the selected host
selected_host=$(echo "$hosts" | fzf \
    --height=15 --reverse \
    --prompt="▶ Connect to Node: " \
    --header="Select an SSH node from your topology. UP/DOWN to navigate, ENTER to connect, ESC to cancel." \
    --preview="echo \"${c_cyan}Node Details:${c_reset}\"; awk -v host=\"{}\" 'BEGIN{IGNORECASE=1} /^Host / {if ($2 == host) flag=1; else flag=0} flag {print}' \"$SSH_CONFIG\"" \
    --preview-window="right:50%:wrap" \
    --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950" \
    --color="hl:#ff7b72,hl+:#ff7b72,info:#8b949e,marker:#e3b341,spinner:#bc8cff")

if [[ -z "$selected_host" ]]; then
    echo "${c_dim}Connection cancelled.${c_reset}"
    exit 0
fi

# Post-selection: choose action
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
DEPLOY_SCRIPT="$DOTFILES_DIR/scripts/utils/ssh-deploy.sh"

action="connect"
if [[ -f "$DEPLOY_SCRIPT" ]]; then
    action=$(printf "connect\tSSH into $selected_host\ndeploy\tDeploy Open Claw env to $selected_host\nboth\tDeploy env + connect" | \
        column -s $'\t' -t | fzf \
        --height=6 --reverse \
        --prompt="▶ Action: " \
        --header="  Choose action for $selected_host" \
        --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950" \
        --ansi | awk '{print $1}')
    [[ -z "$action" ]] && action="connect"
fi

case "$action" in
    deploy)
        bash "$DEPLOY_SCRIPT" "$selected_host"
        ;;
    both)
        bash "$DEPLOY_SCRIPT" "$selected_host"
        echo ""
        echo "${c_green}Connecting to $selected_host...${c_reset}"
        exec ssh "$selected_host"
        ;;
    *)
        echo "${c_green}Connecting to $selected_host...${c_reset}"
        exec ssh "$selected_host"
        ;;
esac
