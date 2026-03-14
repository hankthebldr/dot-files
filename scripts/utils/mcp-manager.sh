#!/usr/bin/env bash
# scripts/utils/mcp-manager.sh
# Interactive Model Context Protocol (MCP) Manager

# Theme Colors (GitHub macOS Dark)
c_reset=$'\e[0m'
c_cyan=$'\e[38;2;88;166;255m'
c_green=$'\e[38;2;63;185;80m'
c_purple=$'\e[38;2;188;140;255m'
c_dim=$'\e[38;2;139;148;158m'
c_red=$'\e[38;2;255;123;114m'

# Paths
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
MCP_PROJECTS_DIR="$HOME/Github/mcp-servers"

clear

echo "${c_purple}╭────────────────────────────────────────────────────────╮${c_reset}"
echo "${c_purple}│${c_reset}  ${c_cyan}🔌 MODEL CONTEXT PROTOCOL (MCP) MANAGER${c_reset}               ${c_purple}│${c_reset}"
echo "${c_purple}├────────────────────────────────────────────────────────┤${c_reset}"
echo "${c_purple}│${c_reset}  ${c_dim}Manage Claude Desktop endpoints & Scaffold servers...${c_reset} ${c_purple}│${c_reset}"
echo "${c_purple}╰────────────────────────────────────────────────────────╯${c_reset}"
echo ""

prompt_menu() {
    echo "  ${c_cyan}1.${c_reset} List Active MCP Servers"
    echo "  ${c_cyan}2.${c_reset} Register New MCP Server"
    echo "  ${c_cyan}3.${c_reset} Scaffold New MCP Project (TypeScript/Python)"
    echo "  ${c_cyan}4.${c_reset} Edit Claude Config Raw JSON"
    echo "  ${c_dim}0. Exit Manager${c_reset}"
    echo ""
    read -p "  ${c_purple}▶${c_reset} Enter choice [0-4]: " mode
    echo ""
}

prompt_menu

# Ensure config file exists for features that require it
ensure_config() {
    if [[ ! -f "$CLAUDE_CONFIG" ]]; then
        echo "${c_red}Claude Desktop config not found at:${c_reset}"
        echo "$CLAUDE_CONFIG"
        echo "${c_dim}Initializing empty config template...${c_reset}"
        mkdir -p "$(dirname "$CLAUDE_CONFIG")"
        echo '{"mcpServers": {}}' > "$CLAUDE_CONFIG"
    fi
}

case $mode in
    1)
        # List Active Servers
        ensure_config
        echo "${c_green}── Registered MCP Endpoints ──${c_reset}"
        
        # Use jq to iterate over the keys in mcpServers object
        if ! command -v jq &> /dev/null; then
            echo "${c_red}Please install 'jq' to parse JSON mapping: brew install jq${c_reset}"
            exit 1
        fi
        
        server_count=$(jq '.mcpServers | length' "$CLAUDE_CONFIG")
        if [[ "$server_count" == "0" ]]; then
            echo "  ${c_dim}No MCP servers currently registered in Claude Desktop.${c_reset}"
        else
            jq -r '.mcpServers | to_entries[] | "\(.key) \(.value.command) \(.value.args | join(" ") // "")"' "$CLAUDE_CONFIG" | while read -r name cmd args; do
                echo "  ${c_cyan}■ ${name}${c_reset}"
                echo "    Command: ${c_dim}${cmd} ${args}${c_reset}"
            done
        fi
        ;;
    2)
        # Register New
        ensure_config
        echo "${c_green}── Register Server to Claude Desktop ──${c_reset}"
        read -p "  Server Name (e.g. postgres-db): " s_name
        read -p "  Execution Command (e.g. npx, uvx, node): " s_cmd
        read -p "  Arguments (space separated, e.g. -y @modelcontextprotocol/server-postgres): " s_args
        
        # Convert args to JSON array format
        # E.g. "-y @package" -> ["-y", "@package"]
        json_args=$(echo "$s_args" | awk '{for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i==NF?"":", ")}')
        
        if [[ -n "$s_name" && -n "$s_cmd" ]]; then
            # Inject into JSON using jq tree manipulation
            temp_json=$(mktemp)
            jq ".mcpServers[\"$s_name\"] = {\"command\": \"$s_cmd\", \"args\": [$json_args]}" "$CLAUDE_CONFIG" > "$temp_json" && mv "$temp_json" "$CLAUDE_CONFIG"
            echo "${c_green}✅ Successfully registered ${s_name}! Restart Claude Desktop to apply.${c_reset}"
        else
            echo "${c_red}Error: Server Name and Command are required.${c_reset}"
        fi
        ;;
    3)
        # Scaffold Project
        echo "${c_green}── Scaffold MCP Server Project ──${c_reset}"
        mkdir -p "$MCP_PROJECTS_DIR"
        read -p "  Project Name: " p_name
        if [[ -z "$p_name" ]]; then
             echo "${c_red}Aborted: Name required.${c_reset}"; exit 1; 
        fi
        
        p_dir="$MCP_PROJECTS_DIR/$p_name"
        if [[ -d "$p_dir" ]]; then
             echo "${c_red}Project directory already exists: $p_dir${c_reset}"; exit 1;
        fi
        
        echo "  1. TypeScript (Node/NPM)"
        echo "  2. Python (uv)"
        read -p "  Language [1/2]: " lang
        
        mkdir -p "$p_dir"
        cd "$p_dir" || exit 1
        
        if [[ "$lang" == "1" ]]; then
            echo "${c_dim}Initializing Node project...${c_reset}"
            npm init -y > /dev/null
            npm install @modelcontextprotocol/sdk > /dev/null
            cat << 'EOF' > index.js
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new Server({
  name: "custom-mcp-server",
  version: "1.0.0"
}, {
  capabilities: { tools: {} }
});

const transport = new StdioServerTransport();
await server.connect(transport);
console.error("MCP Server running on stdio");
EOF
            echo "node index.js" > start.sh
            
        elif [[ "$lang" == "2" ]]; then
            echo "${c_dim}Initializing Python project...${c_reset}"
            if command -v uv &> /dev/null; then
                uv venv > /dev/null
                uv pip install mcp > /dev/null
            else
                python3 -m venv venv
                source venv/bin/activate
                pip install mcp > /dev/null
            fi
            
            cat << 'EOF' > server.py
from mcp.server import Server
from mcp.server.stdio import stdio_server
import asyncio

app = Server("custom-mcp-server")

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await app.run(read_stream, write_stream, app.create_initialization_options())

if __name__ == "__main__":
    asyncio.run(main())
EOF
            echo "python3 server.py" > start.sh
        else
            echo "${c_red}Invalid choice.${c_reset}"
            rm -rf "$p_dir"
            exit 1
        fi
        
        chmod +x start.sh
        echo "# $p_name MCP Server" > README.md
        
        echo "${c_green}✅ Scaffolding complete at: $p_dir${c_reset}"
        ;;
    4)
        # Edit Config
        ensure_config
        echo "${c_dim}Opening $CLAUDE_CONFIG in \$EDITOR...${c_reset}"
        ${EDITOR:-vim} "$CLAUDE_CONFIG"
        ;;
    0)
        exit 0
        ;;
    *)
        echo "${c_red}Invalid choice.${c_reset}"
        ;;
esac
echo ""
