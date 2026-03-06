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
    --color="hl:#ff7b72,hl+:#ff7b72,info:#8b949e,marker:#d29922,spinner:#bc8cff")

if [[ -n "$selected_host" ]]; then
    echo "${c_green}Initializing connection to: $selected_host...${c_reset}"
    # Use exec to replace the current process (TUI/Shell) with the SSH session
    exec ssh "$selected_host"
else
    echo "${c_dim}Connection cancelled.${c_reset}"
    exit 0
fi
