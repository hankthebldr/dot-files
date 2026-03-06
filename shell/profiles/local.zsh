# Local CLI Profile
# Loadout for custom built and local CLI repositories
export CLAW_PROFILE_THEME="local"

# ==========================================
# UNIFIED CLI STARTUP SPEC PARSER
# ==========================================
# This script iterates through all subdirectories in ~/Github/local-clis/
# and parses any `.clistartup` specification files to dynamically load
# tools, aliases, and environment variables.

LOCAL_CLI_DIR="$HOME/Github/local-clis"

if [[ -d "$LOCAL_CLI_DIR" ]]; then
    # Iterate over all immediate subdirectories
    for d in "$LOCAL_CLI_DIR"/*/; do
        spec_file="${d}.clistartup"
        
        if [[ -f "$spec_file" ]]; then
            # We source the spec file directly to load its bash-compatible variables
            # We execute it in a subshell first to ensure valid syntax before pulling variables into current shell
            if zsh -n "$spec_file" &>/dev/null; then
                # Source safely
                source "$spec_file"
                
                # Apply: TOOL_EXPORT_PATH
                if [[ -n "$TOOL_EXPORT_PATH" ]]; then
                    full_path="${d}${TOOL_EXPORT_PATH}"
                    # Only add if it exists and isn't already in PATH
                    if [[ -d "$full_path" && ":$PATH:" != *":$full_path:"* ]]; then
                        export PATH="$full_path:$PATH"
                    fi
                fi
                
                # Apply: TOOL_ENV
                if [[ -n "${TOOL_ENV[@]}" ]]; then
                    for evar in "${TOOL_ENV[@]}"; do
                        export "$evar"
                    done
                fi

                # Apply: TOOL_ALIASES
                if [[ -n "${TOOL_ALIASES[@]}" ]]; then
                    for string_alias in "${TOOL_ALIASES[@]}"; do
                        # Evaluate to alias command
                        alias "$string_alias"
                    done
                fi
                
                # Unset the spec variables so they don't bleed into the next iteration
                unset TOOL_NAME TOOL_EXPORT_PATH TOOL_ENV TOOL_ALIASES
            else
                echo "⚠️ Syntax error in CLI Startup Spec: $spec_file"
            fi
        fi
    done
fi
