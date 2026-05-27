-- Wezterm Configuration — Open Claw (GitHub Dark)
-- Sized for the welcome TUI + profile fastfetch flow.
-- Install: ln -s ~/.dotfiles/terminal/.config/wezterm/wezterm.lua ~/.wezterm.lua

local wezterm = require 'wezterm'
local config = wezterm.config_builder()

-- ── Font ──────────────────────────────────────────────
config.font = wezterm.font('JetBrainsMono Nerd Font Mono')
config.font_size = 13.0
config.line_height = 1.0

-- ── Window ────────────────────────────────────────────
-- 160 × 50 = comfortable headroom for the welcome TUI + fastfetch sequence.
config.initial_cols = 160
config.initial_rows = 50
config.window_padding = {
    left = 10, right = 10, top = 10, bottom = 10,
}
config.window_decorations = 'RESIZE'
config.window_background_opacity = 0.95
config.macos_window_background_blur = 20
config.hide_tab_bar_if_only_one_tab = true

-- ── GitHub Dark palette (matches dotfiles identity) ──
config.colors = {
    foreground = '#c9d1d9',
    background = '#0d1117',
    cursor_bg  = '#58a6ff',
    cursor_fg  = '#0d1117',
    cursor_border = '#58a6ff',
    selection_fg = '#0d1117',
    selection_bg = '#58a6ff',
    ansi = {
        '#484f58',  -- black
        '#ff7b72',  -- red
        '#3fb950',  -- green
        '#d29922',  -- yellow
        '#58a6ff',  -- blue
        '#bc8cff',  -- magenta
        '#39c5cf',  -- cyan
        '#b1bac4',  -- white
    },
    brights = {
        '#6e7681',
        '#ffa198',
        '#56d364',
        '#e3b341',
        '#79c0ff',
        '#d2a8ff',
        '#56d4dd',
        '#f0f6fc',
    },
    tab_bar = {
        background = '#0d1117',
        active_tab = {
            bg_color = '#58a6ff',
            fg_color = '#0d1117',
            intensity = 'Bold',
        },
        inactive_tab = {
            bg_color = '#161b22',
            fg_color = '#8b949e',
        },
    },
}

-- ── macOS ─────────────────────────────────────────────
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- ── Keybindings (Cmd-c/v/q/n/t as expected on Mac) ───
config.keys = {
    { key = 'c', mods = 'CMD', action = wezterm.action.CopyTo 'Clipboard' },
    { key = 'v', mods = 'CMD', action = wezterm.action.PasteFrom 'Clipboard' },
    { key = 'n', mods = 'CMD', action = wezterm.action.SpawnWindow },
    { key = 't', mods = 'CMD', action = wezterm.action.SpawnTab 'CurrentPaneDomain' },
    { key = 'w', mods = 'CMD', action = wezterm.action.CloseCurrentTab { confirm = true } },
}

return config
