return {
  -- Mason: portable LSP/DAP/linter/formatter installer.
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    opts = { ui = { border = "rounded" } },
  },

  -- Auto-install the formatters + linters referenced by formatting.lua /
  -- linting.lua into Mason's dir (added to Neovim's PATH), so conform + nvim-lint
  -- actually find them instead of erroring with ENOENT.
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = {
        "stylua", "shfmt", "black", "isort", "prettier", "goimports",
        "yamllint", "hadolint", "golangci-lint", "flake8", "mypy", "eslint_d",
      },
      run_on_start = true,
    },
  },

  -- LSP. Native nvim 0.11+ API: register per-server config via vim.lsp.config()
  -- FIRST, then let mason-lspconfig install + auto-enable (vim.lsp.enable) the
  -- servers — so settings/capabilities always apply and nothing is configured
  -- twice (the old manual setup() loop + automatic_enable produced duplicate
  -- clients).
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
    },
    config = function()
      -- Completion capabilities applied to every server.
      vim.lsp.config("*", { capabilities = require("cmp_nvim_lsp").default_capabilities() })

      -- lua_ls: make it Neovim-aware (knows the `vim` global + runtime stdlib).
      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            diagnostics = { globals = { "vim" } },
            workspace = {
              library = vim.api.nvim_get_runtime_file("", true),
              checkThirdParty = false,
            },
            telemetry = { enable = false },
          },
        },
      })

      -- Per-buffer keymaps, attached when any server connects.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("claw-lsp-attach", { clear = true }),
        callback = function(ev)
          local map = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = ev.buf, desc = "LSP: " .. desc })
          end
          map("gd", vim.lsp.buf.definition, "Go to definition")
          map("gr", vim.lsp.buf.references, "References")
          map("K", vim.lsp.buf.hover, "Hover documentation")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename symbol")
          map("<leader>D", vim.lsp.buf.type_definition, "Type definition")
          map("gi", vim.lsp.buf.implementation, "Go to implementation")
          -- nvim 0.11+ diagnostic navigation (goto_prev/goto_next are removed).
          map("[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, "Previous diagnostic")
          map("]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, "Next diagnostic")
          map("<leader>d", vim.diagnostic.open_float, "Float diagnostic")
        end,
      })

      -- Diagnostic appearance.
      vim.diagnostic.config({
        virtual_text = { spacing = 4, prefix = "●" },
        signs = true,
        underline = true,
        update_in_insert = false,
        float = { border = "rounded" },
      })

      -- Install missing servers, then auto-enable them. Runs AFTER the
      -- vim.lsp.config() calls above so per-server settings take effect.
      require("mason-lspconfig").setup({
        ensure_installed = {
          "lua_ls", "pyright", "ts_ls", "gopls", "bashls",
          "yamlls", "jsonls", "dockerls", "terraformls",
        },
        automatic_enable = true,
      })
    end,
  },
}
