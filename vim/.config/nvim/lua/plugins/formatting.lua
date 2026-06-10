return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo" },
  opts = {
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "isort", "black" },
      go = { "gofmt", "goimports" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      bash = { "shfmt" },
      sh = { "shfmt" },
      terraform = { "terraform_fmt" },
    },
    -- conform renamed `lsp_fallback = true` → `lsp_format = "fallback"`. Fall
    -- back to the LSP formatter when no configured formatter is installed, so a
    -- missing tool (e.g. black) still formats via pyright/gopls instead of
    -- erroring on save.
    format_on_save = {
      timeout_ms = 500,
      lsp_format = "fallback",
    },
  },
}
