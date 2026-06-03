# Backlog — Frontend / Desktop / Visual Layer

> **Status:** deferred (future development). Not started.
> **Decision (scoping):** when built, the desktop aesthetic layer **integrates into
> the normal Ubuntu install flow** (promoted in the welcome TUI + onboarding).
> Hyprland stays **opt-in** (never auto-run) because it replaces the whole DE.
> **Platform:** Ubuntu 24.04 (GNOME baseline). macOS is out of scope for this layer.

This repo is CLI/cross-platform first. The items below add a GUI/desktop "ricing"
layer. Anything Ubuntu-only must be Linux-gated and must never run during the
default cross-platform bootstrap path.

## Already covered by the repo (do NOT re-implement)

| Blueprint item | Where it already lives |
|---|---|
| Zsh, Oh My Zsh, Starship, Fastfetch | `bootstrap.sh`, `terminal/starship.toml`, `config/.config/fastfetch/` |
| zsh-syntax-highlighting, zsh-autosuggestions | `.zshrc` tool-init block |
| eza, bat, btop, zoxide | modern-CLI step + `shell/aliases.zsh` |
| JetBrains Mono / FiraCode / Meslo Nerd Fonts | Nerd Fonts step in `bootstrap.sh` |
| Kitty, WezTerm configs | `terminal/kitty/`, `terminal/wezterm/` |
| Fractional scaling / GNOME tweaks (partial) | `scripts/utils/gnome-optimize.sh`, `scripts/install/desktop-linux.sh` |

## New work — grouped by subsystem

### 1. Customization frameworks
- [ ] GNOME Tweaks + Extension Manager (`gnome-shell-extension-manager`)
- [ ] Gradience (Libadwaita/GTK4 recoloring)
- [ ] Kvantum (Qt → GTK theme bridge)

### 2. GNOME extensions (automate install + enable via `gext`/dconf)
- [ ] Blur my Shell · Dash to Dock · Just Perfection · Rounded Window Corners Reborn
- [ ] Tiling Assistant · AppIndicator support · Vitals · Burn My Windows · Space Bar
- [ ] Aylur's Widgets (AGS) — TypeScript/CSS widget framework

### 3. Themes / icons / cursors (vendor into `config/themes/` or install scripts)
- [ ] GTK: Orchis · Graphite · WhiteSur (+ Catppuccin / Tokyo Night palettes)
- [ ] Icons: Tela · Papirus · WhiteSur
- [ ] Cursors: Bibata Modern Classic · Capitaine

### 4. Typography
- [ ] Inter + Cantarell UI fonts (Nerd mono fonts already handled)
- [ ] `~/.config/fontconfig/fonts.conf` — subpixel hinting / antialiasing

### 5. Terminal/shell extras (mostly done — gaps only)
- [ ] Yazi (TUI file manager w/ image preview)
- [ ] Cava (audio visualizer)
- [ ] Confirm Kitty background-blur config on Wayland

### 6. Desktop workflow utilities
- [ ] Ulauncher and/or Albert (Spotlight-style launcher)
- [ ] Flameshot (annotated screenshots) · CopyQ (clipboard manager) · Variety (wallpapers)

### 7. Hyprland (compositor — OPT-IN, high risk)
- [ ] Vendor a **hardened, pinned** wrapper around the JaKooLit `Ubuntu-Hyprland`
      `24.04` branch. Never run during bootstrap; surface only behind an explicit
      `claw install hyprland` (or onboarding "Tiling WM" choice).
- [ ] Enable `deb-src` + full upgrade as a documented prereq, not silently.
- [ ] Symlink `~/.config/hypr` into the dotfiles tree so config is version-controlled
      (the user already manages config via Stow — reuse that, not Obsidian).
- [ ] Document monitor/animation/keybind tweaks (`hyprctl monitors`, `$mainMod`).

## Integration notes when this is picked up
- Gate every script: `detect_os` → Ubuntu/GNOME only; no-op elsewhere.
- Theme assets: prefer `git clone --depth 1` of upstream theme repos into a cache,
  then `stow`/symlink — keep heavy assets out of the repo where possible.
- GNOME extension enablement is dconf-based; capture the dconf keys so it's
  reproducible (idempotent re-runs), matching the repo's existing conventions.
- Add a `claw integrity`-friendly manifest entry for any committed config.
