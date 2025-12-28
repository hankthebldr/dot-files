#!/usr/bin/env bash

# ============================================
# Activate CLI Optimizations
# This will update your .zshrc with new tools
# ============================================

set -e

ZSHRC="$HOME/.zshrc"
BACKUP="$HOME/.zshrc.backup-$(date +%Y%m%d-%H%M%S)"

echo "🔧 Activating CLI optimizations..."
echo ""

# Backup current .zshrc
echo "📦 Backing up current .zshrc to $BACKUP"
cp "$ZSHRC" "$BACKUP"

# Check if aliases already sourced
if grep -q "source.*aliases.zsh" "$ZSHRC"; then
    echo "⚠️  aliases.zsh already sourced in .zshrc"
else
    echo "➕ Adding aliases.zsh to .zshrc"
    cat >> "$ZSHRC" << 'EOF'

# ============================================
# OPTIMIZED ALIASES AND FUNCTIONS
# ============================================
source ~/Github/Github_desktop/dot-files/aliases.zsh
EOF
fi

# Add tool integrations
echo "➕ Adding tool integrations..."

# Zoxide (smarter cd)
if ! grep -q "zoxide init" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Zoxide (smarter cd - use 'z' command)
eval "$(zoxide init zsh)"
EOF
    echo "  ✓ Added zoxide integration"
else
    echo "  ⚠️  zoxide already configured"
fi

# Starship prompt
if ! grep -q "starship init" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Starship prompt (cross-platform, fast)
# Comment out to keep powerlevel10k
# eval "$(starship init zsh)"
EOF
    echo "  ✓ Added starship (commented out - uncomment to use)"
else
    echo "  ⚠️  starship already configured"
fi

# Direnv (per-directory environments)
if ! grep -q "direnv hook" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Direnv (per-directory environment variables)
eval "$(direnv hook zsh)"
EOF
    echo "  ✓ Added direnv integration"
else
    echo "  ⚠️  direnv already configured"
fi

# Atuin (shell history)
if ! grep -q "atuin init" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Atuin (better shell history)
eval "$(atuin init zsh)"
EOF
    echo "  ✓ Added atuin integration"
else
    echo "  ⚠️  atuin already configured"
fi

# Update eza aliases (better ls)
if ! grep -q "alias ls='eza" "$ZSHRC"; then
    cat >> "$ZSHRC" << 'EOF'

# Eza (modern ls replacement)
alias ls='eza --icons --group-directories-first'
alias ll='eza -l --icons --group-directories-first'
alias la='eza -la --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons'
alias tree='eza --tree --icons'
EOF
    echo "  ✓ Added eza aliases (overriding previous ls aliases)"
else
    echo "  ⚠️  eza aliases already configured"
fi

echo ""
echo "✅ Activation complete!"
echo ""
echo "Your old .zshrc was backed up to:"
echo "  $BACKUP"
echo ""
echo "Next steps:"
echo "  1. Reload your shell:"
echo "     source ~/.zshrc"
echo ""
echo "  2. Try these new commands:"
echo "     z ~/Documents          # Jump to directory (zoxide)"
echo "     ls                     # Better ls with icons (eza)"
echo "     ll                     # Detailed list with icons"
echo "     lazygit                # Beautiful Git TUI"
echo "     lazydocker             # Beautiful Docker TUI"
echo "     navi                   # Interactive cheatsheets"
echo "     glow README.md         # Render markdown"
echo ""
echo "  3. Optional: Switch to Starship prompt"
echo "     Edit ~/.zshrc and uncomment the starship line"
echo ""
