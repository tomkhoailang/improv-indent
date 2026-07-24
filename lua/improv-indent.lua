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

  local function setup_buf_listener(bufnr)
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

      if vim.g.vscode then
        setup_buf_listener(bufnr)
      end
    end
  end

  -- Register autocommands to hook filetypes automatically
  vim.api.nvim_create_autocmd("FileType", {
    callback = function(args)
      apply_custom_indent(args.buf)
    end,
  })

  -- Apply immediately to any currently loaded buffers (resolves race condition on startup)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype ~= "" then
      apply_custom_indent(bufnr)
    end
  end

  -- Register TextChangedI to handle closing brackets automatically
  if opts.reindent_on_type ~= false then
    vim.api.nvim_create_autocmd("TextChangedI", {
      callback = function()
        local bufnr = vim.api.nvim_get_current_buf()
        local ft = vim.bo[bufnr].filetype
        if rules.rules[ft] and rules.rules[ft].enabled then
          local lnum = vim.api.nvim_win_get_cursor(0)[1]
          local line = vim.api.nvim_get_current_line()

          local line_len = #line
          local last_line_len = vim.b[bufnr].last_line_len or line_len
          vim.b[bufnr].last_line_len = line_len

          local should_align = false
          if line_len >= last_line_len then
            if not vim.g.vscode and line:match("^%s*[)}%]]") then
              should_align = true
            end
          end

          if should_align then
            local lang = ft
            local new_indent = require("indent_engine").get_indent(lang, lnum)
            local current_indent = vim.fn.indent(lnum)
            if new_indent ~= current_indent then
              local line_without_indent = line:match("^%s*(.*)")
              local spaces = string.rep(" ", new_indent)
              local cursor = vim.api.nvim_win_get_cursor(0)
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

  -- If we are in VS Code, stop here to avoid conflicts with editor events
  if vim.g.vscode then
    return
  end

  -- Set up auto-closing pairs (autopair) - only in standard Neovim
  if opts.autopair ~= false then
    require("improv-indent.autopair").setup(opts.autopair_opts)
  end

  -- Asynchronously format parent control-flow statements and braces on Enter inside {}
  local format_group = vim.api.nvim_create_augroup("ImprovIndentSmartEnter", { clear = true })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = format_group,
    pattern = "*",
    callback = function(args)
      if vim.g.vscode then
        return
      end

      local bufnr = args.buf
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      local last_count = vim.b[bufnr].last_line_count or line_count
      vim.b[bufnr].last_line_count = line_count

      if line_count <= last_count then
        return
      end

      local ft = vim.bo[bufnr].filetype
      local base_ft = ft:gsub("react$", "")

      local rules = require("indent_rules").rules
      local lang_rules = rules[ft] or rules[base_ft]
      if not lang_rules or not lang_rules.enabled then
        return
      end

      local lnum = vim.api.nvim_win_get_cursor(0)[1]
      if lnum <= 1 then
        return
      end

      local pline = vim.fn.getline(lnum - 1)
      local line = vim.fn.getline(lnum)
      local nline = vim.fn.getline(lnum + 1)

      -- 1. Structural check: expand block pattern
      if pline:match("{%s*$") and line:match("^%s*$") and nline:match("^%s*}%s*$") then
        -- Skip comments
        if pline:match("^%s*//") or pline:match("^%s*%*") or pline:match("^%s*/%*") then
          return
        end

        local parent_lnum = lnum - 1
        local pline_len = #pline

        -- 2. Format parent line using LSP (matches VS Code's formatOnType)
        local clients = vim.lsp.get_clients({ bufnr = bufnr })
        local has_range_formatter = false
        for _, client in ipairs(clients) do
          if client:supports_method("textDocument/rangeFormatting") then
            has_range_formatter = true
            break
          end
        end

        if has_range_formatter then
          vim.lsp.buf.format({
            bufnr = bufnr,
            range = {
              ["start"] = { parent_lnum, 0 },
              ["end"] = { parent_lnum, pline_len },
            },
            async = true,
          })
        else
          -- Fallback to regex if LSP formatting is not ready/available
          local formatted = pline
          local keywords = lang_rules.smart_enter_keywords or {}
          for _, kw in ipairs(keywords) do
            formatted = formatted:gsub("(%f[%w]" .. kw .. ")%s*(%()", "%1 %2")
          end

          formatted = formatted:gsub("([^%s%$])%s*({%s*)$", "%1 %2")

          if formatted ~= pline then
            vim.fn.setline(parent_lnum, formatted)
          end
        end
      end
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

function M.map_bs()
  return require("improv-indent.autopair").handle_backspace()
end

return M
