# Terminal Configurations — Open Claw

Tuned for the welcome TUI + profile fastfetch flow. All configs use a
shared visual identity: **GitHub Dark** palette · **JetBrainsMono Nerd
Font Mono 13pt** · **160 cols × 50 rows** initial window.

## Why 160 × 50?

The fastfetch profile dashboards render at ~16 rows tall + the welcome
TUI menu uses ~28 rows (with the new tiered layout). At 40 rows total,
the bottom of the menu scrolls off. **160 × 50** gives ~6 rows of margin
and avoids any clipping during the activation flow.

If you need a smaller window for screenshots, drop to 140 × 40 in your
terminal's own resize controls — the configs only set the *initial*
dimensions, not a clamp.

## Install paths per terminal

### Kitty

```bash
ln -s ~/.dotfiles/terminal/.config/kitty/kitty.conf  ~/.config/kitty/kitty.conf
```

### Alacritty

```bash
ln -s ~/.dotfiles/terminal/.config/alacritty/alacritty.toml  ~/.config/alacritty/alacritty.toml
```

### Ghostty

```bash
ln -s ~/.dotfiles/terminal/.config/ghostty/config  ~/.config/ghostty/config
```

### Wezterm

```bash
ln -s ~/.dotfiles/terminal/.config/wezterm/wezterm.lua  ~/.wezterm.lua
```

### iTerm2 (Dynamic Profile)

iTerm2 watches `~/Library/Application Support/iTerm2/DynamicProfiles/` for
JSON files and auto-loads them. Symlink the bundled profile:

```bash
mkdir -p ~/Library/Application\ Support/iTerm2/DynamicProfiles
ln -s ~/.dotfiles/terminal/iterm2/OpenClaw.json \
      ~/Library/Application\ Support/iTerm2/DynamicProfiles/OpenClaw.json
```

Then in iTerm2: `Settings → Profiles → Other Actions → Set as Default` on
the `Open Claw` profile.

### macOS Terminal.app

Double-click `terminal/mbp-m4.terminal` to import. Then:
`Settings → Profiles → [Open Claw] → Default`.

Note: the existing `.terminal` plist contains base64-encoded color blobs
because that's how macOS stores them — it works but isn't editable by
hand. For palette changes, switch to iTerm2 or Wezterm.

## Making Ghostty the default terminal

The Ghostty config (`terminal/.config/ghostty/config`) is the canonical
cross-platform experience — authored on the BD790i (GNOME/X11), stowed identically
to macOS. It tracks `claw theme set` (writes a git-ignored `theme.conf` include),
ships ssh-terminfo, and uses `⌘`/`Super` keybinds that work on both platforms.

### macOS

macOS has **no OS-level "default terminal"** setting (unlike Linux's
`x-terminal-emulator`). The practical equivalent — login item + Dock pin + a Finder
"Open in Ghostty" Quick Action — is applied idempotently by:

```bash
bash ~/.dotfiles/scripts/setup/macos-default-terminal.sh
```

The Quick Action bundle lives in the repo at `terminal/macos/Open in Ghostty.workflow`
and is copied to `~/Library/Services/`. If it doesn't appear in a folder's right-click
**Quick Actions** menu, enable it under *System Settings → Keyboard → Keyboard
Shortcuts → Services*, or relaunch Finder (`killall Finder`).

### Linux / BD790i (GNOME)

Linux *does* have a real default. On the BD790i:

```bash
# 1. Debian/Ubuntu alternatives system (terminal-launching apps honor this)
sudo update-alternatives --install /usr/bin/x-terminal-emulator \
     x-terminal-emulator "$(command -v ghostty)" 50
sudo update-alternatives --config x-terminal-emulator      # pick ghostty

# 2. Nautilus right-click "Open Terminal" (via nautilus-open-any-terminal)
gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal ghostty

# 3. GNOME Ctrl+Alt+T — rebind the custom shortcut to ghostty
#    Settings → Keyboard → Custom Shortcuts → command: ghostty

# 4. Tools that read $TERMINAL (rofi, i3/sway, xdg) — put in ~/.zshrc.local:
export TERMINAL=ghostty
```

## Stow integration (one-shot)

The dot-files bootstrap symlinks `terminal/` via GNU Stow:

```bash
cd ~/.dotfiles && stow terminal
```

This drops the per-terminal config files into `~/.config/...` paths
automatically. Run after pulling new terminal config updates.

## Font

All configs require **[JetBrainsMono Nerd Font Mono](https://www.nerdfonts.com/font-downloads)**
(the Mono variant — fixed-width glyph rendering).

```bash
# macOS
brew install --cask font-jetbrains-mono-nerd-font

# Linux
sudo apt install fonts-jetbrains-mono   # base font, then download Nerd Font icons from nerdfonts.com
```

## Theme alignment

The palette across all five configs maps 1:1 with the dotfiles identity
declared in `~/.dotfiles/CLAUDE.md`:

| Role     | Hex      | Used by |
|----------|----------|---------|
| Blue     | #58a6ff  | links, profile keys, accent |
| Green    | #3fb950  | success, profile titles |
| Orange   | #d29922  | warnings, secondary accent |
| Red      | #ff7b72  | errors |
| Purple   | #bc8cff  | AI / GenAI accents |
| Muted    | #8b949e  | inactive, subtitles |
| Foreground | #c9d1d9 | body text |
| Background | #0d1117 | base |

Changing any one of these means changing all 5 terminal configs **plus**
`shell/profiles/*/meta.zsh` PROFILE_THEME_DEFAULT references. The
canonical source is `CLAUDE.md`.

## Verifying

After install + restart, run any of:

```bash
echo "term: $TERM_PROGRAM   size: $(tput cols)×$(tput lines)"
fastfetch                       # should render without vertical crop
claw load cloud                 # full profile activation should fit
```

Expected on a fresh terminal: `160×50` and no clipping anywhere.
