return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      python = { "flake8", "mypy" },
      javascript = { "eslint_d" },
      typescript = { "eslint_d" },
      bash = { "shellcheck" },
      sh = { "shellcheck" },
      go = { "golangcilint" },
      yaml = { "yamllint" },
      dockerfile = { "hadolint" },
    }

    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufEnter" }, {
      group = lint_augroup,
      callback = function()
        lint.try_lint()
      end,
    })
  end,
}
