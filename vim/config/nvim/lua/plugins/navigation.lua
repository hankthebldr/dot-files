return {
  -- Telescope: fuzzy finder over lists
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
      },
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
      { "<leader>fo", "<cmd>Telescope oldfiles<cr>", desc = "Old files" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },
    },
    config = function()
      local telescope = require("telescope")
      telescope.setup({
        defaults = {
          layout_strategy = "horizontal",
          layout_config = {
            horizontal = { preview_width = 0.55 },
            width = 0.87,
            height = 0.80,
          },
          sorting_strategy = "ascending",
          prompt_prefix = "   ",
          selection_caret = "  ",
        },
        pickers = {
          buffers = { theme = "dropdown", previewer = false },
          oldfiles = { theme = "dropdown", previewer = false },
        },
        extensions = {
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },
        },
      })
      telescope.load_extension("fzf")
    end,
  },

  -- Harpoon: quick file marks
  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "<leader>a",
        function() require("harpoon"):list():add() end,
        desc = "Harpoon add file",
      },
      {
        "<C-e>",
        function()
          local harpoon = require("harpoon")
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        desc = "Harpoon menu",
      },
      {
        "<leader>1",
        function() require("harpoon"):list():select(1) end,
        desc = "Harpoon file 1",
      },
      {
        "<leader>2",
        function() require("harpoon"):list():select(2) end,
        desc = "Harpoon file 2",
      },
      {
        "<leader>3",
        function() require("harpoon"):list():select(3) end,
        desc = "Harpoon file 3",
      },
      {
        "<leader>4",
        function() require("harpoon"):list():select(4) end,
        desc = "Harpoon file 4",
      },
    },
    config = function()
      require("harpoon"):setup()
    end,
  },
}
