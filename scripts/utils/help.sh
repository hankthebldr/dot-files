#!/usr/bin/env bash
# scripts/utils/help.sh
# Integrated Help System for Dotfiles

source "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

DOTFILES_HOME="${HOME}/.dotfiles"
ALIAS_FILES=(
    "$DOTFILES_HOME/shell/aliases.zsh"
    "$DOTFILES_HOME/shell/security.zsh"
)

show_help() {
    log_info "Dotfiles Integrated Help"
    echo "========================================================"
    printf "%-15s %-30s %s\n" "Command" "Definition" "Description"
    echo "--------------------------------------------------------"

    for file in "${ALIAS_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            # Parse aliases
            # Regex explanation:
            # ^alias : matches start of alias
            # ([^=]+) : captures alias name (group 1)
            # = : literal equals
            # ['"]?([^#]+)['"]? : captures definition (group 2), ignores quotes
            # .*#\s*(.+)$ : captures comment (group 3)
            
            while IFS= read -r line; do
                # Regex breakdown:
                # ^alias[[:space:]]+ : starts with alias and space
                # ([^=]+)= : group 1 is alias name
                # ['"]?([^#]+)['"]? : group 2 is definition (lazy match before #?)
                # [[:space:]]*#[[:space:]]*(.*)$ : group 3 is description
                
                if [[ "$line" =~ ^alias[[:space:]]+([^=]+)=[\'\"]?([^#]+)[\'\"]?[[:space:]]*#[[:space:]]*(.*)$ ]]; then
                    name="${BASH_REMATCH[1]}"
                    # Trim trailing quote/spaces from definition if regex captured them
                    def=$(echo "${BASH_REMATCH[2]}" | sed "s/['\"]*//g" | xargs)
                    desc="${BASH_REMATCH[3]}"
                    
                    if [[ -n "$desc" ]]; then
                       printf "\033[0;32m%-15s\033[0m %-30s \033[0;34m%s\033[0m\n" "$name" "${def:0:28}..." "$desc"
                    fi
                fi
            done < "$file"
        fi
    done
    echo "========================================================"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_help
fi
