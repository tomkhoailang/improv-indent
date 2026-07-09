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
end

return M
