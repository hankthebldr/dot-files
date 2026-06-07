#!/usr/bin/env bash
# scripts/utils/toolkit.sh
# Interactive Open Claw TUI for modular toolsets and workflows

# Auto-detect dotfiles root (this file lives at <dotfiles>/scripts/utils/toolkit.sh)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Theme Colors (GitHub macOS Dark)
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_yellow=$'\e[38;2;227;179;65m'
c_dim=$'\e[38;2;139;148;158m'
c_red=$'\e[38;2;255;123;114m'

# Clear screen for crisp UI
clear

# Header
echo "${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
echo "${c_purple}│${c_reset}  ${c_cyan}🧠 OPEN CLAW TOOLKIT TUI${c_reset}                              ${c_purple}│${c_reset}"
echo "${c_purple}┝────────────────────────────────────────────────────────┥${c_reset}"
echo "${c_purple}│${c_reset}  ${c_yellow}Select a modular workflow category:${c_reset}                   ${c_purple}│${c_reset}"
echo "${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
echo ""
echo "  ${c_cyan}1.${c_reset} Git & Development Operations"
echo "  ${c_cyan}2.${c_reset} Containers & Docker Management"
echo "  ${c_cyan}3.${c_reset} Kubernetes (K8s) Cluster Contexts"
echo "  ${c_cyan}4.${c_reset} Cloud & Infrastructure (AWS/TF)"
echo "  ${c_cyan}5.${c_reset} Security & Vulnerability Scanning"
echo "  ${c_cyan}6.${c_reset} System Utilities & Networking"
echo "  ${c_cyan}7.${c_reset} Knowledge & Notes (Obsidian)"
echo "  ${c_cyan}8.${c_reset} Agentic & AI Solutions"
echo "  ${c_dim}0. Exit Toolkit${c_reset}"
echo ""

if [[ -n "$TK_AUTO_START" ]]; then
    main_choice="$TK_AUTO_START"
    unset TK_AUTO_START
else
    read -p "  ${c_purple}▶${c_reset} Enter choice [0-8]: " main_choice
fi

case $main_choice in
    1)
        echo ""
        echo "${c_green}── Git & Dev Ops ──${c_reset}"
        echo "  1. Lazygit (Interactive Git TUI)"
        echo "  2. Quick Commit & Push (add all, msg, push)"
        echo "  3. Interactive Rebase (last 5 commits)"
        echo "  4. Clean/Nuke Node Modules & Reinstall"
        echo "  5. Start Local Python HTTP Server (Port 8000)"
        echo "  6. Interactive JSON Explorer (fx)"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-6]: " sub
        case $sub in
            1) command -v lazygit &> /dev/null && lazygit || echo "${c_red}Lazygit not installed.${c_reset}" ;;
            2)
                read -p "  Commit message: " msg
                git add . && git commit -m "$msg" && git push
                ;;
            3) git rebase -i HEAD~5 ;;
            4)
                echo "Cleaning..."
                rm -rf node_modules package-lock.json yarn.lock && npm install
                ;;
            5) python3 -m http.server 8000 ;;
            6)
                if command -v fx &> /dev/null; then
                    json=$(find . -maxdepth 3 -iname "*.json" 2>/dev/null | fzf --height 40% --reverse --prompt="Select JSON: ")
                    [[ -n "$json" ]] && fx "$json"
                else
                    echo "${c_red}fx not installed.${c_reset}"
                fi
                ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    2)
        echo ""
        echo "${c_green}── Docker Management ──${c_reset}"
        echo "  1. Lazydocker (Interactive UI)"
        echo "  2. System Prune (Force clean unused containers/networks/images)"
        echo "  3. Stop ALL Running Containers"
        echo "  4. Remove ALL Containers"
        echo "  5. View Docker Compose Logs (Tail)"
        # shellcheck disable=SC2046
        case $sub in
            1) command -v lazydocker &> /dev/null && lazydocker || echo "${c_red}Lazydocker not installed.${c_reset}" ;;
            2) docker system prune -af --volumes ;;
            3) docker stop $(docker ps -q) 2>/dev/null || echo "No running containers." ;;
            4) docker rm $(docker ps -aq) 2>/dev/null || echo "No containers found." ;;
            5) docker-compose logs -f ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    3)
        echo ""
        echo "${c_green}── Kubernetes (K8s) ──${c_reset}"
        if ! command -v fzf &> /dev/null; then
            echo "${c_red}Workflow requires 'fzf' (fuzzy finder). Please install it.${c_reset}"
            exit 1
        fi
        echo "  1. K9s (Interactive UI)"
        echo "  2. Switch Context (Interactive)"
        echo "  3. Switch Namespace (Interactive)"
        echo "  4. View Top Pods (CPU/Memory)"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-4]: " sub
        case $sub in
            1) command -v k9s &> /dev/null && k9s || echo "${c_red}K9s not installed.${c_reset}" ;;
            2)
                ctx=$(kubectl config get-contexts -o name | fzf --height 40% --reverse)
                [[ -n "$ctx" ]] && kubectl config use-context "$ctx"
                ;;
            3)
                ns=$(kubectl get ns -o name | cut -d/ -f2 | fzf --height 40% --reverse)
                [[ -n "$ns" ]] && kubectl config set-context --current --namespace="$ns" && echo "Switched to namespace: $ns"
                ;;
            4) kubectl top pods -A ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    4)
        echo ""
        echo "${c_green}── Cloud & IaC ──${c_reset}"
        echo "  1. Switch AWS Profile (Interactive)"
        echo "  2. WhoAmI Check (AWS & GCP)"
        echo "  3. Terraform Format & Validate"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-3]: " sub
        case $sub in
            1)
                prof=$(aws configure list-profiles | fzf --height 40% --reverse)
                [[ -n "$prof" ]] && export AWS_PROFILE="$prof" && echo "Switched AWS_PROFILE to: $prof"
                # Keep prompt aware of the export, instruct user for persistence
                echo "${c_dim}Note: AWS_PROFILE is set for this session. Use 'export AWS_PROFILE=$prof' to persist outside TUI.${c_reset}"
                ;;
            2)
                echo "${c_yellow}AWS Identity:${c_reset}"
                aws sts get-caller-identity || echo "AWS CLI not configured."
                echo "${c_yellow}GCP Identity:${c_reset}"
                gcloud config get-value account || echo "GCloud CLI not configured."
                ;;
            3) terraform fmt -recursive && terraform validate ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    5)
        echo ""
        echo "${c_green}── Security Scanners ──${c_reset}"
        echo "  1. Trivy Vulnerability Scan (Local Directory)"
        echo "  2. Grype Image Scan (Select running image)"
        echo "  3. Nmap Quick Scan (Fast Ping & Top 100 ports)"
        echo "  4. OSINT Identity Triangulation (osint-d2)"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-4]: " sub
        case $sub in
            1) trivy fs . ;;
            2)
                img=$(docker images --format "{{.Repository}}:{{.Tag}}" | fzf --height 40% --reverse)
                [[ -n "$img" ]] && grype "$img"
                ;;
            3)
                read -p "  Target IP/CIDR: " target
                [[ -n "$target" ]] && nmap -T4 -F "$target"
                ;;
            4)
                if command -v osint-d2 &> /dev/null; then
                    osint-d2
                else
                    echo "${c_red}osint-d2 not installed. It will install in the background automatically.${c_reset}"
                fi
                ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    6)
        echo ""
        echo "${c_green}── System Utilities ──${c_reset}"
        echo "  1. Show Active Listening Network Ports (lsof)"
        echo "  2. Copy Public SSH Key to Clipboard"
        echo "  3. Fast Internet Speed Test"
        echo "  4. Network Process Monitor (bandwhich) *sudo required"
        echo "  5. Real-time Network Diagnostics (netwatch)"
        echo "  6. Terminal File Manager (rovr)"
        echo "  7. Terminal RSS Reader (eilmeldung)"
        echo "  8. ASCII 3D Model Viewer (voxcii)"
        echo "  9. Weather Forecast (clawea)"
        echo "  10. 📡 Connect to HomeLab (Interactive SSH Manager)"
        echo "  11. 🔄 Cumulative System Update (macOS, Node, Python, Rust, etc.)"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-11]: " sub
        case $sub in
            1) sudo lsof -iTCP -sTCP:LISTEN -n -P ;;
            2)
                if [[ -f ~/.ssh/id_rsa.pub ]]; then
                    cat ~/.ssh/id_rsa.pub | clip_copy && echo "✅ Copied id_rsa.pub to clipboard"
                elif [[ -f ~/.ssh/id_ed25519.pub ]]; then
                    cat ~/.ssh/id_ed25519.pub | clip_copy && echo "✅ Copied id_ed25519.pub to clipboard"
                else
                    echo "${c_red}No standard SSH public key found.${c_reset}"
                fi
                ;;
            3) if command -v networkQuality &>/dev/null; then networkQuality; elif command -v speedtest &>/dev/null; then speedtest; else echo "${c_red}Install speedtest-cli: pip install speedtest-cli${c_reset}"; fi ;;
            4) 
                if command -v bandwhich &> /dev/null; then
                    sudo bandwhich
                else
                    echo "${c_red}bandwhich not installed.${c_reset}"
                fi
                ;;
            5) command -v netwatch-tui &> /dev/null && netwatch-tui || echo "${c_red}netwatch-tui not installed.${c_reset}" ;;
            6) command -v rovr &> /dev/null && rovr || echo "${c_red}rovr not installed.${c_reset}" ;;
            7) command -v eilmeldung &> /dev/null && eilmeldung || echo "${c_red}eilmeldung not installed.${c_reset}" ;;
            8) command -v voxcii &> /dev/null && voxcii || echo "${c_red}voxcii not installed.${c_reset}" ;;
            9) command -v clawea &> /dev/null && clawea || echo "${c_red}clawea not installed.${c_reset}" ;;
            10) 
                if [[ -f "$DOTFILES_DIR/scripts/utils/homelab.sh" ]]; then
                    "$DOTFILES_DIR/scripts/utils/homelab.sh"
                else
                    echo "${c_red}Homelab connector script missing.${c_reset}"
                fi
                ;;
            11)
                if [[ -f "$DOTFILES_DIR/scripts/utils/system-update.sh" ]]; then
                    "$DOTFILES_DIR/scripts/utils/system-update.sh"
                else
                    echo "${c_red}System update script missing.${c_reset}"
                fi
                ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    7)
        echo ""
        echo "${c_green}── Knowledge & Notes (Obsidian) ──${c_reset}"
        
        export OBSIDIAN_VAULT="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
        vault_name=$(basename "$OBSIDIAN_VAULT")
        # Ensure the new Obsidian CLI is available (macOS path)
        export PATH="$PATH:/Applications/Obsidian.app/Contents/MacOS"
        
        echo "  1. Launch Obsidian Vault"
        echo "  2. Open Daily Note"
        echo "  3. Interactive Vault Search (CLI + FZF)"
        echo "  4. Create New Note"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-4]: " sub
        case $sub in
            1)
                obsidian open vault="$vault_name" 2>/dev/null || xdg-open "obsidian://" 2>/dev/null || open -a "Obsidian" 2>/dev/null || echo "${c_red}Cannot open Obsidian${c_reset}"
                ;;
            2)
                daily_note=$(date '+%Y-%m-%d')
                obsidian open "file=$daily_note.md" "vault=$vault_name" || echo "${c_red}Failed to open daily note via CLI.${c_reset}"
                ;;
            3)
                if command -v obsidian &> /dev/null; then
                    read -p "  Search vault: " sq
                    if [[ -n "$sq" ]]; then
                        obsidian search "query=$sq" "vault=$vault_name"
                    fi
                else
                    echo "${c_red}Obsidian CLI not found. Re-run installer from obsidian.md${c_reset}"
                fi
                ;;
            4)
                read -p "  Enter New Note Title: " note_title
                if [[ -n "$note_title" ]]; then
                    if command -v obsidian &> /dev/null; then
                        # The new CLI lets us create it natively
                        obsidian create "file=$note_title.md" "vault=$vault_name" "content=# $note_title\n\nCreated: $(date '+%Y-%m-%d %H:%M')" || echo "Failed."
                    else
                        echo "${c_red}Obsidian CLI not found in PATH.${c_reset}"
                    fi
                fi
                ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    8)
        echo ""
        echo "${c_green}── Agentic & AI Solutions ──${c_reset}"
        echo "  1. Bootstrap Local AI Workspace (~/ai_models)"
        echo "  2. Launch Claude Code in Current App"
        echo "  3. Save Prompt Template to Knowledge Base"
        echo "  4. Start Local Model Inference (Ollama / llama.cpp)"
        echo "  5. 🔌 Manage MCP Servers (Register, Scaffold, Inspect)"
        echo "  6. 💻 Launch Aider (AI Pair Programmer)"
        echo "  7. 👉 Test OS Automation (mac-ui-automate)"
        read -p "  ${c_purple}▶${c_reset} Run workflow [1-7]: " sub
        case $sub in
            1) 
                mkdir -p ~/ai_models/prompts ~/ai_models/data
                echo "${c_green}Workspace created at ~/ai_models${c_reset}"
                ;;
            2)
                if command -v claude &> /dev/null; then claude; else echo "${c_red}Claude Code not found.${c_reset}"; fi
                ;;
            3)
                read -p "  Template Title: " ttitle
                if [[ -n "$ttitle" ]]; then
                    obs_vault="${OBSIDIAN_VAULT:-$HOME/hr-vault-main-pa}"
                    mkdir -p "$obs_vault/Prompts" 2>/dev/null
                    echo "## $ttitle\n\n**System Prompt:**\n\n**User Prompt:**" > "$obs_vault/Prompts/${ttitle}.md"
                    echo "Template created at $obs_vault/Prompts/${ttitle}.md"
                fi
                ;;
            4)
                echo "${c_dim}Tip: Run this within the 'ai' profile for full CLI aliases.${c_reset}"
                if command -v ollama &> /dev/null; then 
                    ollama run llama3.2
                elif command -v llama-cpp &> /dev/null; then
                    llama-cpp
                else
                    echo "${c_red}No local inference engines found in PATH. Run install via master-setup.${c_reset}"
                fi
                ;;
            5)
                if [[ -f "$DOTFILES_DIR/scripts/utils/mcp-manager.sh" ]]; then
                    "$DOTFILES_DIR/scripts/utils/mcp-manager.sh"
                else
                    echo "${c_red}MCP Manager script missing.${c_reset}"
                fi
                ;;
            6)
                if command -v aider &> /dev/null; then
                    aider
                else
                    echo "${c_red}Aider not installed. Run 'pipx install aider-chat'.${c_reset}"
                fi
                ;;
            7)
                if [[ -f "$DOTFILES_DIR/scripts/utils/mac-ui-automate.sh" ]]; then
                    "$DOTFILES_DIR/scripts/utils/mac-ui-automate.sh" notify "Toolkit Test" "OS Automation is active!"
                else
                    echo "${c_red}mac-ui-automate script missing.${c_reset}"
                fi
                ;;
            *) echo "${c_red}Invalid choice.${c_reset}" ;;
        esac
        ;;
    0)
        echo "Exiting toolkit."
        exit 0
        ;;
    *)
        echo "${c_red}Invalid category choice. Exiting.${c_reset}"
        exit 1
        ;;
esac

echo ""
echo "${c_green}Workflow complete!${c_reset}"
