local M = {}

function M.setup(opts)
  opts = opts or {}

  -- Merge custom user rules if provided
  local rules = require("indent_rules")
  if opts.rules then
    for lang, rule in pairs(opts.rules) do
      rules.rules[lang] = vim.tbl_deep_extend("force", rules.rules[lang] or {}, rule)
    end
  end

  -- Merge global dot-chain alignment setting
  if opts.align_dot_chains ~= nil then
    vim.g.align_dot_chains = opts.align_dot_chains
  end

  -- Set up auto-closing pairs (autopair)
  if opts.autopair ~= false then
    require("improv-indent.autopair").setup(opts.autopair_opts)
  end

  local function apply_custom_indent(bufnr)
    local ft = vim.bo[bufnr].filetype
    if rules.rules[ft] and rules.rules[ft].enabled then
      -- Disable native Vim indentation
      vim.b[bufnr].did_indent = true

      -- Connect to the custom indenter engine
      _G.GetCustomIndent = _G.GetCustomIndent or function(lnum)
        local lang = vim.bo.filetype
        return require("indent_engine").get_indent(lang, lnum)
      end
      vim.bo[bufnr].indentexpr = "v:lua.GetCustomIndent()"
    end
  end

  -- Register autocommands to hook filetypes automatically
  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      apply_custom_indent(args.buf)
    end,
  })

  -- Register autocommand to restore indentation settings after loading a session
  vim.api.nvim_create_autocmd("SessionLoadPost", {
    callback = function()
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          apply_custom_indent(bufnr)
        end
      end
    end,
  })

  -- Register TextChangedI to handle closing brackets alignment automatically (bypasses plugin conflicts)
  vim.api.nvim_create_autocmd("TextChangedI", {
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local ft = vim.bo[bufnr].filetype
      if rules.rules[ft] and rules.rules[ft].enabled then
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_get_current_line()
        if line:match("^%s*[)}%]]") then
          local lang = ft
          local new_indent = require("indent_engine").get_indent(lang, lnum)
          local current_indent = vim.fn.indent(lnum)
          if new_indent ~= current_indent then
            local line_without_indent = line:match("^%s*(.*)")
            local spaces = string.rep(" ", new_indent)
            local cursor = vim.api.nvim_win_get_cursor(0)
            local line_len = #line
            local col_from_end = line_len - cursor[2]

            local new_line = spaces .. line_without_indent
            vim.api.nvim_set_current_line(new_line)

            local new_line_len = #new_line
            local new_col = math.max(0, new_line_len - col_from_end)
            pcall(vim.api.nvim_win_set_cursor, 0, { cursor[1], new_col })
          end
        end
      end
    end,
  })
end

return M
