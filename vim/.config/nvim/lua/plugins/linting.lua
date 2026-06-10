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

    -- Only run linters whose binary is actually present — otherwise nvim-lint
    -- spams "Error running <linter>: ENOENT" on every buffer. Missing linters
    -- silently skip until installed (mason-tool-installer provisions most).
    local function available_linters()
      local names = lint.linters_by_ft[vim.bo.filetype] or {}
      local ok = {}
      for _, name in ipairs(names) do
        local l = lint.linters[name]
        local cmd = type(l) == "table" and l.cmd or name
        if vim.fn.executable(cmd) == 1 then
          table.insert(ok, name)
        end
      end
      return ok
    end

    local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
    vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
      group = lint_augroup,
      callback = function()
        local linters = available_linters()
        if #linters > 0 then
          lint.try_lint(linters)
        end
      end,
    })
  end,
}
