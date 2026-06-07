#!/usr/bin/env bash
# scripts/utils/tunnel-manager.sh
# Interactive SSH Tunnel Manager with ASCII Topology Visualization
# Supports: Local (-L), Remote (-R), SOCKS (-D) tunnels
# Multi-hop via ProxyJump, per-hop keys, ControlMaster lifecycle

set -euo pipefail

# ============================================
# THEME COLORS (GitHub macOS Dark)
# ============================================
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'      # Blue #58a6ff
c_green=$'\e[38;2;63;185;80m'      # Green #3fb950
c_purple=$'\e[38;2;188;140;255m'   # Purple #bc8cff
c_orange=$'\e[38;2;227;179;65m'    # Orange #e3b341
c_red=$'\e[38;2;255;123;114m'      # Red #ff7b72
c_dim=$'\e[38;2;139;148;158m'      # Muted #8b949e
c_white=$'\e[38;2;201;209;217m'    # Foreground #c9d1d9
c_bold=$'\e[1m'

# ============================================
# CONFIGURATION
# ============================================
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
TUNNEL_CONFIG="$DOTFILES_DIR/config/ssh/tunnels.yml"
CONTROL_DIR="/tmp/ssh-tunnels"
mkdir -p "$CONTROL_DIR"

# ============================================
# DEPENDENCY CHECKS
# ============================================
check_deps() {
    local missing=()
    command -v yq &>/dev/null || missing+=("yq")
    command -v fzf &>/dev/null || missing+=("fzf")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "${c_red}Missing dependencies: ${missing[*]}${c_reset}"
        echo "${c_dim}Install with: brew install ${missing[*]}${c_reset}"
        exit 1
    fi
}

# ============================================
# TUNNEL STATUS CHECK
# ============================================
tunnel_status() {
    local name="$1"
    local socket="$CONTROL_DIR/$name"
    if [[ -S "$socket" ]]; then
        if ssh -O check -o ControlPath="$socket" dummy 2>/dev/null; then
            echo "active"
            return 0
        fi
    fi
    echo "inactive"
    return 1
}

status_icon() {
    local name="$1"
    if [[ "$(tunnel_status "$name")" == "active" ]]; then
        echo "${c_green}●${c_reset}"
    else
        echo "${c_dim}○${c_reset}"
    fi
}

# ============================================
# ASCII TOPOLOGY RENDERER
# ============================================
draw_topology() {
    local name="$1"
    local ttype
    ttype=$(yq -r ".tunnels.${name}.type" "$TUNNEL_CONFIG")
    local desc
    desc=$(yq -r ".tunnels.${name}.description // \"\"" "$TUNNEL_CONFIG")
    local lport
    lport=$(yq -r ".tunnels.${name}.local_port" "$TUNNEL_CONFIG")
    local rhost
    rhost=$(yq -r ".tunnels.${name}.remote_host // \"\"" "$TUNNEL_CONFIG")
    local rport
    rport=$(yq -r ".tunnels.${name}.remote_port // \"\"" "$TUNNEL_CONFIG")
    local hop_count
    hop_count=$(yq -r ".tunnels.${name}.hops | length" "$TUNNEL_CONFIG")
    local status
    status=$(tunnel_status "$name" 2>/dev/null || true)

    # Status line
    echo ""
    if [[ "$status" == "active" ]]; then
        echo "  ${c_green}${c_bold}▶ $name${c_reset}  ${c_green}CONNECTED${c_reset}  ${c_dim}$desc${c_reset}"
    else
        echo "  ${c_cyan}${c_bold}▶ $name${c_reset}  ${c_dim}DISCONNECTED${c_reset}  ${c_dim}$desc${c_reset}"
    fi
    echo ""

    # Build the chain of boxes
    local boxes=()
    local arrows=()

    # LOCAL box (always first)
    local local_label="LOCAL"
    local local_detail=":${lport}"
    case "$ttype" in
        socks)  local_label="SOCKS5"; local_detail=":${lport}" ;;
        remote) local_label="LOCAL"; local_detail=":${lport}" ;;
    esac
    boxes+=("$local_label|$local_detail")

    # HOP boxes
    for ((i=0; i<hop_count; i++)); do
        local hhost huser hport hkey hkey_short
        hhost=$(yq -r ".tunnels.${name}.hops[$i].host" "$TUNNEL_CONFIG")
        huser=$(yq -r ".tunnels.${name}.hops[$i].user" "$TUNNEL_CONFIG")
        hport=$(yq -r ".tunnels.${name}.hops[$i].port // 22" "$TUNNEL_CONFIG")
        hkey=$(yq -r ".tunnels.${name}.hops[$i].key" "$TUNNEL_CONFIG")
        hkey_short=$(basename "$hkey")

        local hop_label="HOP $((i+1))"
        if ((i == hop_count - 1)) && [[ "$ttype" == "socks" ]]; then
            hop_label="PROXY"
        fi
        boxes+=("$hop_label|${huser}@${hhost}:${hport}|${hkey_short}")
        arrows+=("SSH")
    done

    # TARGET box (for local/remote forwards, not socks)
    if [[ "$ttype" == "local" ]]; then
        boxes+=("TARGET|${rhost}:${rport}")
        arrows+=("FWD")
    elif [[ "$ttype" == "remote" ]]; then
        boxes+=("REMOTE|${rhost}:${rport}")
        arrows+=("EXPOSE")
    fi

    # Render the topology
    local num_boxes=${#boxes[@]}

    # === TOP BORDER LINE ===
    local top_line="  "
    for ((b=0; b<num_boxes; b++)); do
        top_line+="${c_cyan}┌────────────────────┐${c_reset}"
        if ((b < num_boxes - 1)); then
            top_line+="      "
        fi
    done
    echo "$top_line"

    # === LABEL LINE ===
    local label_line="  "
    for ((b=0; b<num_boxes; b++)); do
        local label="${boxes[$b]%%|*}"
        local padded
        padded=$(printf "%-18s" "$label")
        label_line+="${c_cyan}│${c_reset} ${c_purple}${c_bold}${padded}${c_reset} ${c_cyan}│${c_reset}"
        if ((b < num_boxes - 1)); then
            local arrow_label="${arrows[$b]}"
            label_line+="${c_green}─${arrow_label}─▶${c_reset}"
            # Pad to align
            local arrow_pad=$((4 - ${#arrow_label}))
            for ((p=0; p<arrow_pad; p++)); do label_line+=" "; done
        fi
    done
    echo "$label_line"

    # === DETAIL LINE ===
    local detail_line="  "
    for ((b=0; b<num_boxes; b++)); do
        local parts="${boxes[$b]}"
        # Extract second field (detail)
        local detail
        detail=$(echo "$parts" | cut -d'|' -f2)
        local padded
        padded=$(printf "%-18s" "$detail")
        detail_line+="${c_cyan}│${c_reset} ${c_white}${padded}${c_reset} ${c_cyan}│${c_reset}"
        if ((b < num_boxes - 1)); then
            detail_line+="      "
        fi
    done
    echo "$detail_line"

    # === KEY LINE (for hops that have keys) ===
    local key_line="  "
    local has_keys=false
    for ((b=0; b<num_boxes; b++)); do
        local parts="${boxes[$b]}"
        local key_field
        key_field=$(echo "$parts" | cut -d'|' -f3)
        if [[ -n "$key_field" ]]; then
            has_keys=true
            local padded
            padded=$(printf "%-18s" "🔑 $key_field")
            key_line+="${c_cyan}│${c_reset} ${c_orange}${padded}${c_reset} ${c_cyan}│${c_reset}"
        else
            key_line+="${c_cyan}│${c_reset}                    ${c_cyan}│${c_reset}"
        fi
        if ((b < num_boxes - 1)); then
            key_line+="      "
        fi
    done
    if [[ "$has_keys" == "true" ]]; then
        echo "$key_line"
    fi

    # === BOTTOM BORDER LINE ===
    local bottom_line="  "
    for ((b=0; b<num_boxes; b++)); do
        bottom_line+="${c_cyan}└────────────────────┘${c_reset}"
        if ((b < num_boxes - 1)); then
            bottom_line+="      "
        fi
    done
    echo "$bottom_line"

    # === TYPE SUMMARY LINE ===
    echo ""
    local direction_arrow
    case "$ttype" in
        local)  direction_arrow="${c_green}LOCAL :${lport}  ─────▶  ${rhost}:${rport}${c_reset}" ;;
        remote) direction_arrow="${c_orange}REMOTE :${rport}  ◀─────  LOCAL :${lport}${c_reset}" ;;
        socks)  direction_arrow="${c_purple}SOCKS5 PROXY  :${lport}${c_reset}" ;;
    esac
    echo "  ${c_dim}Type:${c_reset} ${direction_arrow}  ${c_dim}│  Hops: ${hop_count}${c_reset}"
    echo ""
}

# ============================================
# SSH COMMAND BUILDER
# ============================================
build_ssh_cmd() {
    local name="$1"
    local ttype
    ttype=$(yq -r ".tunnels.${name}.type" "$TUNNEL_CONFIG")
    local lport
    lport=$(yq -r ".tunnels.${name}.local_port" "$TUNNEL_CONFIG")
    local rhost
    rhost=$(yq -r ".tunnels.${name}.remote_host // \"localhost\"" "$TUNNEL_CONFIG")
    local rport
    rport=$(yq -r ".tunnels.${name}.remote_port // \"\"" "$TUNNEL_CONFIG")
    local hop_count
    hop_count=$(yq -r ".tunnels.${name}.hops | length" "$TUNNEL_CONFIG")

    local cmd=("ssh" "-f" "-N")
    local socket="$CONTROL_DIR/$name"
    cmd+=("-o" "ControlMaster=auto" "-o" "ControlPath=$socket" "-o" "ControlPersist=yes")
    cmd+=("-o" "ServerAliveInterval=30" "-o" "ServerAliveCountMax=3")

    # Forward type
    case "$ttype" in
        local)  cmd+=("-L" "${lport}:${rhost}:${rport}") ;;
        remote) cmd+=("-R" "${rport}:${rhost}:${lport}") ;;
        socks)  cmd+=("-D" "${lport}") ;;
    esac

    # Build ProxyJump chain for multi-hop (all hops except the last one)
    if ((hop_count > 1)); then
        local jump_chain=""
        for ((i=0; i<hop_count-1; i++)); do
            local jhost juser jport jkey
            jhost=$(yq -r ".tunnels.${name}.hops[$i].host" "$TUNNEL_CONFIG")
            juser=$(yq -r ".tunnels.${name}.hops[$i].user" "$TUNNEL_CONFIG")
            jport=$(yq -r ".tunnels.${name}.hops[$i].port // 22" "$TUNNEL_CONFIG")
            jkey=$(yq -r ".tunnels.${name}.hops[$i].key" "$TUNNEL_CONFIG")
            if [[ -n "$jump_chain" ]]; then
                jump_chain+=","
            fi
            jump_chain+="${juser}@${jhost}:${jport}"
        done
        cmd+=("-J" "$jump_chain")
    fi

    # Final hop (the target SSH host)
    local last_idx=$((hop_count - 1))
    local fhost fuser fport fkey
    fhost=$(yq -r ".tunnels.${name}.hops[$last_idx].host" "$TUNNEL_CONFIG")
    fuser=$(yq -r ".tunnels.${name}.hops[$last_idx].user" "$TUNNEL_CONFIG")
    fport=$(yq -r ".tunnels.${name}.hops[$last_idx].port // 22" "$TUNNEL_CONFIG")
    fkey=$(yq -r ".tunnels.${name}.hops[$last_idx].key" "$TUNNEL_CONFIG")

    # Add identity file for final hop
    local expanded_key="${fkey/#\~/$HOME}"
    if [[ -f "$expanded_key" ]]; then
        cmd+=("-i" "$expanded_key")
    fi
    cmd+=("-p" "$fport")
    cmd+=("${fuser}@${fhost}")

    echo "${cmd[@]}"
}

# ============================================
# TUNNEL OPERATIONS
# ============================================
connect_tunnel() {
    local name="$1"
    if [[ "$(tunnel_status "$name")" == "active" ]]; then
        echo "  ${c_orange}Tunnel '$name' is already active.${c_reset}"
        return 0
    fi

    draw_topology "$name"
    echo "  ${c_cyan}Connecting...${c_reset}"

    local cmd
    cmd=$(build_ssh_cmd "$name")

    if eval "$cmd" 2>/dev/null; then
        sleep 1
        if [[ "$(tunnel_status "$name")" == "active" ]]; then
            echo "  ${c_green}✓ Tunnel '$name' is now active.${c_reset}"
        else
            echo "  ${c_orange}⚠ Tunnel started but status uncertain. Check manually.${c_reset}"
        fi
    else
        echo "  ${c_red}✗ Failed to establish tunnel '$name'.${c_reset}"
        return 1
    fi
}

disconnect_tunnel() {
    local name="$1"
    local socket="$CONTROL_DIR/$name"
    if [[ -S "$socket" ]]; then
        # Get the target host for the control command
        local hop_count
        hop_count=$(yq -r ".tunnels.${name}.hops | length" "$TUNNEL_CONFIG")
        local last_idx=$((hop_count - 1))
        local fhost fuser
        fhost=$(yq -r ".tunnels.${name}.hops[$last_idx].host" "$TUNNEL_CONFIG")
        fuser=$(yq -r ".tunnels.${name}.hops[$last_idx].user" "$TUNNEL_CONFIG")

        if ssh -O exit -o ControlPath="$socket" "${fuser}@${fhost}" 2>/dev/null; then
            echo "  ${c_green}✓ Tunnel '$name' disconnected.${c_reset}"
        else
            # Force remove socket if ssh -O exit fails
            rm -f "$socket"
            echo "  ${c_orange}Socket removed for '$name'.${c_reset}"
        fi
    else
        echo "  ${c_dim}Tunnel '$name' is not active.${c_reset}"
    fi
}

disconnect_all() {
    local names
    names=$(yq -r '.tunnels | keys | .[]' "$TUNNEL_CONFIG" 2>/dev/null)
    local count=0
    for name in $names; do
        if [[ "$(tunnel_status "$name")" == "active" ]]; then
            disconnect_tunnel "$name"
            ((count++))
        fi
    done
    if ((count == 0)); then
        echo "  ${c_dim}No active tunnels to disconnect.${c_reset}"
    else
        echo "  ${c_green}✓ Disconnected $count tunnel(s).${c_reset}"
    fi
}

list_active() {
    local names
    names=$(yq -r '.tunnels | keys | .[]' "$TUNNEL_CONFIG" 2>/dev/null)
    local active_count=0
    local active_names=()

    for name in $names; do
        if [[ "$(tunnel_status "$name")" == "active" ]]; then
            active_names+=("$name")
            ((active_count++))
        fi
    done

    echo ""
    echo "  ${c_purple}${c_bold}Active Tunnels${c_reset}  ${c_dim}(${active_count} connected)${c_reset}"
    echo "  ${c_dim}─────────────────────────────────────────────────────${c_reset}"

    if ((active_count == 0)); then
        echo ""
        echo "  ${c_dim}    ┌─────────┐"
        echo "  ${c_dim}    │         │  No active tunnels"
        echo "  ${c_dim}    │  ○ OFF  │  Use the menu to connect"
        echo "  ${c_dim}    │         │"
        echo "  ${c_dim}    └─────────┘${c_reset}"
    else
        for name in "${active_names[@]}"; do
            local ttype lport desc rhost rport hop_count
            ttype=$(yq -r ".tunnels.${name}.type" "$TUNNEL_CONFIG")
            lport=$(yq -r ".tunnels.${name}.local_port" "$TUNNEL_CONFIG")
            desc=$(yq -r ".tunnels.${name}.description // \"\"" "$TUNNEL_CONFIG")
            rhost=$(yq -r ".tunnels.${name}.remote_host // \"\"" "$TUNNEL_CONFIG")
            rport=$(yq -r ".tunnels.${name}.remote_port // \"\"" "$TUNNEL_CONFIG")
            hop_count=$(yq -r ".tunnels.${name}.hops | length" "$TUNNEL_CONFIG")
            local type_upper
            type_upper=$(echo "$ttype" | tr '[:lower:]' '[:upper:]')

            echo ""
            printf "  ${c_green}●${c_reset}  ${c_white}${c_bold}%-16s${c_reset} ${c_cyan}%-7s${c_reset}  ${c_dim}%s${c_reset}\n" "$name" "$type_upper" "$desc"

            # Mini inline topology
            local hop_chain="  ${c_dim}   "
            hop_chain+="${c_green}:${lport}${c_dim}"
            for ((i=0; i<hop_count; i++)); do
                local hhost
                hhost=$(yq -r ".tunnels.${name}.hops[$i].host" "$TUNNEL_CONFIG")
                # Truncate long hostnames
                if ((${#hhost} > 18)); then
                    hhost="${hhost:0:15}..."
                fi
                hop_chain+=" ──▶ ${c_purple}${hhost}${c_dim}"
            done
            if [[ "$ttype" == "local" ]]; then
                hop_chain+=" ──▶ ${c_orange}${rhost}:${rport}${c_dim}"
            elif [[ "$ttype" == "remote" ]]; then
                hop_chain+=" ◀── ${c_orange}:${rport}${c_dim}"
            fi
            hop_chain+="${c_reset}"
            echo "$hop_chain"
        done
    fi
    echo ""
    echo "  ${c_dim}─────────────────────────────────────────────────────${c_reset}"
    echo ""
}

# ============================================
# FZF MENU BUILDER
# ============================================
build_menu_entries() {
    local names
    names=$(yq -r '.tunnels | keys | .[]' "$TUNNEL_CONFIG" 2>/dev/null)
    for name in $names; do
        local ttype lport desc rhost rport hop_count status_char
        ttype=$(yq -r ".tunnels.${name}.type" "$TUNNEL_CONFIG")
        lport=$(yq -r ".tunnels.${name}.local_port" "$TUNNEL_CONFIG")
        desc=$(yq -r ".tunnels.${name}.description // \"\"" "$TUNNEL_CONFIG")
        rhost=$(yq -r ".tunnels.${name}.remote_host // \"\"" "$TUNNEL_CONFIG")
        rport=$(yq -r ".tunnels.${name}.remote_port // \"\"" "$TUNNEL_CONFIG")
        hop_count=$(yq -r ".tunnels.${name}.hops | length" "$TUNNEL_CONFIG")

        if [[ "$(tunnel_status "$name")" == "active" ]]; then
            status_char="${c_green}●${c_reset}"
        else
            status_char="${c_dim}○${c_reset}"
        fi

        local type_upper forward_str
        type_upper=$(echo "$ttype" | tr '[:lower:]' '[:upper:]')
        case "$ttype" in
            local)  forward_str=":${lport} → ${rhost}:${rport}" ;;
            remote) forward_str=":${lport} ← ${rhost}:${rport}" ;;
            socks)  forward_str=":${lport} proxy" ;;
        esac

        printf "%s  %-16s %s%-7s%s %-24s %s(%d hop%s)%s  %s%s%s\n" \
            "$status_char" "$name" \
            "$c_cyan" "$type_upper" "$c_reset" \
            "$forward_str" \
            "$c_dim" "$hop_count" "$([ "$hop_count" -ne 1 ] && echo 's')" "$c_reset" \
            "$c_dim" "$desc" "$c_reset"
    done
}

# ============================================
# FZF PREVIEW FUNCTION (called by fzf --preview)
# ============================================
preview_tunnel() {
    local name="$1"
    # Re-source colors for subshell
    local c_reset=$'\e[0m'
    local c_cyan=$'\e[38;2;88;166;255m'
    local c_green=$'\e[38;2;63;185;80m'
    local c_purple=$'\e[38;2;188;140;255m'
    local c_orange=$'\e[38;2;227;179;65m'
    local c_red=$'\e[38;2;255;123;114m'
    local c_dim=$'\e[38;2;139;148;158m'
    local c_white=$'\e[38;2;201;209;217m'
    local c_bold=$'\e[1m'

    draw_topology "$name"
}

# ============================================
# ASCII BANNER & NETWORK OVERVIEW
# ============================================
draw_banner() {
    echo ""
    echo "  ${c_cyan}    ┌─────────┐     ┌─────────┐     ┌─────────┐${c_reset}"
    echo "  ${c_cyan}    │${c_green}░░░░░░░░░${c_cyan}│────▶│${c_purple}░░░░░░░░░${c_cyan}│────▶│${c_orange}░░░░░░░░░${c_cyan}│${c_reset}"
    echo "  ${c_cyan}    │${c_green}  LOCAL  ${c_cyan}│ SSH │${c_purple}  JUMP   ${c_cyan}│ SSH │${c_orange} TARGET  ${c_cyan}│${c_reset}"
    echo "  ${c_cyan}    │${c_green}░░░░░░░░░${c_cyan}│◀───│${c_purple}░░░░░░░░░${c_cyan}│◀───│${c_orange}░░░░░░░░░${c_cyan}│${c_reset}"
    echo "  ${c_cyan}    └─────────┘     └─────────┘     └─────────┘${c_reset}"
    echo ""
    echo "  ${c_purple}${c_bold}  SSH TUNNEL MANAGER${c_reset}  ${c_dim}─ Open Claw v2.0${c_reset}"
    echo ""
}

draw_overview() {
    local total=0 active=0 local_count=0 remote_count=0 socks_count=0
    local names
    names=$(yq -r '.tunnels | keys | .[]' "$TUNNEL_CONFIG" 2>/dev/null)

    for name in $names; do
        ((total++))
        local ttype
        ttype=$(yq -r ".tunnels.${name}.type" "$TUNNEL_CONFIG")
        case "$ttype" in
            local)  ((local_count++)) ;;
            remote) ((remote_count++)) ;;
            socks)  ((socks_count++)) ;;
        esac
        if [[ "$(tunnel_status "$name" 2>/dev/null || true)" == "active" ]]; then
            ((active++))
        fi
    done

    echo "  ${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
    printf "  ${c_purple}│${c_reset}  ${c_white}Tunnels:${c_reset} ${c_cyan}%d total${c_reset}  ${c_green}%d active${c_reset}                          ${c_purple}│${c_reset}\n" "$total" "$active"
    printf "  ${c_purple}│${c_reset}  ${c_dim}LOCAL${c_reset} ${c_white}%d${c_reset}  ${c_dim}│  REMOTE${c_reset} ${c_white}%d${c_reset}  ${c_dim}│  SOCKS${c_reset} ${c_white}%d${c_reset}                     ${c_purple}│${c_reset}\n" "$local_count" "$remote_count" "$socks_count"
    echo "  ${c_purple}├────────────────────────────────────────────────────────┤${c_reset}"
    echo "  ${c_purple}│${c_reset}  ${c_dim}↑/↓ navigate · ENTER toggle · ESC exit${c_reset}                ${c_purple}│${c_reset}"
    echo "  ${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
    echo ""
}

# ============================================
# MAIN INTERACTIVE MENU
# ============================================
main_menu() {
    check_deps

    if [[ ! -f "$TUNNEL_CONFIG" ]]; then
        draw_banner
        echo "  ${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
        echo "  ${c_purple}│${c_reset}  ${c_orange}No tunnels.yml found.${c_reset}                                  ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}  ${c_dim}Copy the example to get started:${c_reset}                       ${c_purple}│${c_reset}"
        echo "  ${c_purple}│${c_reset}  ${c_white}cp tunnels.yml.example tunnels.yml${c_reset}                    ${c_purple}│${c_reset}"
        echo "  ${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
        echo ""
        local config_dir
        config_dir=$(dirname "$TUNNEL_CONFIG")
        if [[ -f "$config_dir/tunnels.yml.example" ]]; then
            echo "  ${c_dim}Example: $config_dir/tunnels.yml.example${c_reset}"
        fi
        return 1
    fi

    # Branded banner with network graphic
    draw_banner
    # Live overview dashboard
    draw_overview

    # Build entries
    local entries
    entries=$(build_menu_entries)

    # Add action entries
    local actions=""
    actions+="$(printf '%s  %-16s %s\n' "${c_dim}─${c_reset}" "──────────" "${c_dim}────────────────────────────────────────${c_reset}")"
    actions+=$'\n'
    actions+="$(printf '%s  %-16s %s\n' "${c_orange}◆${c_reset}" "show-active" "${c_dim}List all active tunnels${c_reset}")"
    actions+=$'\n'
    actions+="$(printf '%s  %-16s %s\n' "${c_red}◆${c_reset}" "kill-all" "${c_dim}Disconnect all active tunnels${c_reset}")"
    actions+=$'\n'
    actions+="$(printf '%s  %-16s %s\n' "${c_purple}◆${c_reset}" "edit-config" "${c_dim}Edit tunnels.yml${c_reset}")"

    local all_entries
    all_entries=$(printf '%s\n%s' "$entries" "$actions")

    # Export functions for fzf preview subshell
    export -f draw_topology tunnel_status build_ssh_cmd 2>/dev/null || true
    export TUNNEL_CONFIG CONTROL_DIR DOTFILES_DIR

    local selection
    selection=$(echo "$all_entries" | fzf \
        --height=20 --reverse \
        --prompt="▶ " \
        --ansi \
        --preview="name=\$(echo {} | awk '{print \$2}'); $0 --preview \"\$name\"" \
        --preview-window="right:55%:wrap" \
        --color="bg+:#161b22,fg+:#c9d1d9,prompt:#58a6ff,header:#8b949e,pointer:#3fb950,hl:#bc8cff,hl+:#bc8cff" \
        || echo "")

    if [[ -z "$selection" ]]; then
        echo "${c_dim}Cancelled.${c_reset}"
        return 0
    fi

    # Extract the tunnel name (second field)
    local selected_name
    selected_name=$(echo "$selection" | awk '{print $2}')

    case "$selected_name" in
        "──────────")
            main_menu
            ;;
        "show-active")
            list_active
            echo ""
            read -rp "  ${c_dim}Press ENTER to return...${c_reset}" _
            main_menu
            ;;
        "kill-all")
            disconnect_all
            echo ""
            read -rp "  ${c_dim}Press ENTER to return...${c_reset}" _
            main_menu
            ;;
        "edit-config")
            ${EDITOR:-vim} "$TUNNEL_CONFIG"
            main_menu
            ;;
        *)
            # Toggle tunnel connection
            if [[ "$(tunnel_status "$selected_name")" == "active" ]]; then
                draw_topology "$selected_name"
                echo "  ${c_orange}Tunnel is active. Disconnect?${c_reset}"
                read -rp "  ${c_dim}[y/N]:${c_reset} " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    disconnect_tunnel "$selected_name"
                fi
            else
                connect_tunnel "$selected_name"
            fi
            echo ""
            read -rp "  ${c_dim}Press ENTER to return...${c_reset}" _
            main_menu
            ;;
    esac
}

# ============================================
# CLI ENTRY POINTS
# ============================================
case "${1:-}" in
    --preview)
        # Called by fzf for preview pane
        if [[ -n "${2:-}" && "${2:-}" != "──────────" && "${2:-}" != "show-active" && "${2:-}" != "kill-all" && "${2:-}" != "edit-config" ]]; then
            draw_topology "$2"
        else
            echo ""
            echo "  ${c_dim}Select a tunnel to see its topology.${c_reset}"
        fi
        ;;
    --list)
        check_deps
        [[ -f "$TUNNEL_CONFIG" ]] && list_active || echo "${c_red}No tunnels.yml found.${c_reset}"
        ;;
    --connect)
        check_deps
        [[ -n "${2:-}" ]] && connect_tunnel "$2" || echo "${c_red}Usage: tunnel-manager.sh --connect <name>${c_reset}"
        ;;
    --disconnect)
        check_deps
        [[ -n "${2:-}" ]] && disconnect_tunnel "$2" || echo "${c_red}Usage: tunnel-manager.sh --disconnect <name>${c_reset}"
        ;;
    --kill-all)
        check_deps
        [[ -f "$TUNNEL_CONFIG" ]] && disconnect_all || echo "${c_red}No tunnels.yml found.${c_reset}"
        ;;
    --topology)
        check_deps
        [[ -n "${2:-}" ]] && draw_topology "$2" || echo "${c_red}Usage: tunnel-manager.sh --topology <name>${c_reset}"
        ;;
    ""|--menu)
        main_menu
        ;;
    *)
        echo "Usage: tunnel-manager.sh [--menu|--list|--connect <name>|--disconnect <name>|--kill-all|--topology <name>]"
        ;;
esac
