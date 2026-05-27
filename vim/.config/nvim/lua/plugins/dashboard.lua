-- OPEN CLAW dashboard — visual landing for nvim
-- Mirrors the fastfetch logo aesthetic. GitHub Dark palette inherited from colorscheme.lua.
return {
  "nvimdev/dashboard-nvim",
  event = "VimEnter",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local logo = [[

    ╔═══════════════════════╗
    ║   ▄▄▄   ▄▄▄    ▄   ▄  ║
    ║  █   █ █   █   █ █ █  ║
    ║  █   █ █▄▄▄█   █▄█▄█  ║
    ║  █   █ █       █   █  ║
    ║   ▀▀▀  ▀       ▀   ▀  ║
    ║                       ║
    ║   ▄▄▄ █   ▄▄▄ █   █   ║
    ║  █    █   █   █ █ █   ║
    ║  █    █   █▄▄▄█ ██    ║
    ║  █    █   █   █ █ █   ║
    ║   ▀▀▀ ▀▀▀ ▀   ▀ █  █  ║
    ╚═══════════ v2.0 ══════╝
]]

    require("dashboard").setup({
      theme = "doom",
      config = {
        header = vim.split(logo, "\n"),
        center = {
          { icon = "  ", desc = "Find file        ",
            key = "f", action = "Telescope find_files" },
          { icon = "  ", desc = "Recent files     ",
            key = "r", action = "Telescope oldfiles" },
          { icon = "  ", desc = "Find word        ",
            key = "g", action = "Telescope live_grep" },
          { icon = "  ", desc = "Open vault       ",
            key = "o", action = "edit " .. (vim.env.OBSIDIAN_VAULT or "~") },
          { icon = "  ", desc = "Edit dotfiles    ",
            key = "d", action = "edit ~/.dotfiles" },
          { icon = "  ", desc = "Lazy plugin mgr  ",
            key = "l", action = "Lazy" },
          { icon = "  ", desc = "Quit             ",
            key = "q", action = "qa" },
        },
        footer = function()
          local stats = require("lazy").stats()
          return {
            "",
            string.format("⚡ %d plugins loaded in %.0f ms",
              stats.loaded, stats.startuptime),
          }
        end,
      },
    })
  end,
}
