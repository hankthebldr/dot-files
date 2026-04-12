return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  keys = {
    { "<leader>e", "<cmd>NvimTreeToggle<cr>", desc = "Toggle file explorer" },
  },
  opts = {
    disable_netrw = true,
    hijack_netrw = true,
    open_on_setup = false,
    filters = {
      dotfiles = false,
      git_ignored = true,
    },
    git = {
      enable = true,
      ignore = true,
    },
    renderer = {
      group_empty = true,
      icons = {
        show = {
          git = true,
          folder = true,
          file = true,
          folder_arrow = true,
        },
      },
    },
    actions = {
      open_file = {
        quit_on_open = true,
      },
    },
    view = {
      width = 35,
      side = "left",
    },
  },
}
