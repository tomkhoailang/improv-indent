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
    if vim.b[bufnr].improv_indent_attached then
      return
    end
    vim.b[bufnr].improv_indent_attached = true

    vim.api.nvim_buf_attach(bufnr, false, {
      on_bytes = function(
        _, buf, _, start_row, _, _, old_row, _, _, new_row, _, _
      )
        if new_row > 0 or (new_row == 0 and old_row == 0) then
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(buf) then
              return
            end
            local ft = vim.bo[buf].filetype
            if rules.rules[ft] and rules.rules[ft].enabled then
              local target_row = start_row + new_row
              local prev_line = vim.api.nvim_buf_get_lines(buf, start_row, start_row + 1, true)[1]
              local lines = vim.api.nvim_buf_get_lines(buf, target_row, target_row + 1, true)
              local line = lines[1]
              
              local moved_trailing_dot = false
              local new_indent = nil
              
              if new_row > 0 and prev_line and prev_line:match("%.$") and line and line:match("^%s*$") then
                local stripped_prev = prev_line:sub(1, -2)
                local engine = require("indent_engine")
                local dot_idx = engine.find_first_dot_index(stripped_prev, ft)
                if not dot_idx and start_row > 0 then
                  local line_above = vim.api.nvim_buf_get_lines(buf, start_row - 1, start_row, true)[1]
                  if line_above and line_above:match("^%s*%&?%.") then
                    dot_idx = engine.find_first_dot_index(line_above, ft)
                  end
                end
                
                if dot_idx then
                  moved_trailing_dot = true
                  new_indent = dot_idx - 1
                  vim.api.nvim_buf_set_lines(buf, start_row, start_row + 1, true, { stripped_prev })
                  line = "."
                end
              end

              if line then
                local should_align = false
                local is_empty = line:match("^%s*$") ~= nil
                if new_row > 0 then
                  if line:match("^%s*%&?%.") or moved_trailing_dot then
                    should_align = true
                  elseif is_empty then
                    -- Lookahead: check if the line below starts with a dot
                    local nlnum = vim.fn.nextnonblank(target_row + 1)
                    if nlnum > 0 then
                      local nline = vim.fn.getline(nlnum)
                      if nline:match("^%s*%&?%.") then
                        should_align = true
                      end
                    end
                    -- Lookabove: check if the line above starts with a dot
                    if not should_align and start_row > 0 then
                      local pline = vim.api.nvim_buf_get_lines(buf, start_row, start_row + 1, true)[1]
                      if pline and pline:match("^%s*%&?%.") then
                        should_align = true
                      end
                    end
                  end
                elseif new_row == 0 and line:match("^%s*%.$") then
                  should_align = true
                end

                if should_align then
                  local lnum = target_row + 1
                  local cursor_lnum = vim.api.nvim_win_get_cursor(0)[1]
                  local is_valid = false
                  if cursor_lnum == lnum then
                    is_valid = true
                  elseif cursor_lnum == lnum - 1 then
                    local pline = vim.api.nvim_buf_get_lines(buf, lnum - 2, lnum - 1, true)[1]
                    if pline and not pline:match("^%s*$") then
                      is_valid = true
                    end
                  end

                  if is_valid then
                    if is_empty then
                      -- Manual lookup for dot-chain indent on empty lines (only for VS Code)
                      if vim.g.vscode then
                        local nlnum = vim.fn.nextnonblank(target_row + 1)
                        if nlnum > 0 then
                          local nline = vim.fn.getline(nlnum)
                          if nline:match("^%s*%&?%.") then
                            new_indent = vim.fn.indent(nlnum)
                          end
                        end
                        if not new_indent and start_row > 0 then
                          local pline = vim.api.nvim_buf_get_lines(buf, start_row, start_row + 1, true)[1]
                          if pline and pline:match("^%s*%&?%.") then
                            new_indent = vim.fn.indent(start_row + 1)
                          end
                        end
                      end
                    end

                    new_indent = new_indent or require("indent_engine").get_indent(ft, lnum)
                    local current_indent = vim.fn.indent(lnum)
                    local target_col = new_indent + 1

                    if vim.g.vscode then
                      if new_indent ~= current_indent or moved_trailing_dot then
                        local spaces = string.rep(" ", new_indent)
                        local replacement = moved_trailing_dot and (spaces .. line) or spaces
                        vim.api.nvim_buf_set_text(buf, target_row, 0, target_row, current_indent, { replacement })
                      end
                      
                      if new_row > 0 then
                        for _, delay in ipairs({ 10, 30, 60, 100 }) do
                          vim.defer_fn(function()
                            if vim.api.nvim_buf_is_valid(buf) then
                              if line:match("^%s*$") then
                                vim.fn.VSCodeNotify('cursorMove', { to = 'wrappedLineEnd' })
                              else
                                vim.fn.VSCodeNotify('cursorMove', { to = 'wrappedLineFirstNonWhitespaceCharacter' })
                                vim.fn.VSCodeNotify('cursorMove', { to = 'right', by = 'character', value = 1 })
                              end
                            end
                          end, delay)
                        end
                      end
                    end
                  end
                end
              end
            end
          end)
        end
      end,
    })
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

  -- Register TextChangedI to handle closing brackets, dot-chain alignments, and splits automatically
  vim.api.nvim_create_autocmd("TextChangedI", {
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local ft = vim.bo[bufnr].filetype
      if rules.rules[ft] and rules.rules[ft].enabled then
        local lnum = vim.api.nvim_win_get_cursor(0)[1]
        local line = vim.api.nvim_get_current_line()

        -- 1. Check for trailing dot split in terminal Neovim
        if not vim.g.vscode and lnum > 1 and line:match("^%s*$") then
          local pline = vim.fn.getline(lnum - 1)
          if pline:match("%.$") then
            local stripped_prev = pline:sub(1, -2)
            local engine = require("indent_engine")
            local dot_idx = engine.find_first_dot_index(stripped_prev, ft)
            if not dot_idx and lnum > 2 then
              local line_above = vim.fn.getline(lnum - 2)
              if line_above and line_above:match("^%s*%&?%.") then
                dot_idx = engine.find_first_dot_index(line_above, ft)
              end
            end

            if dot_idx then
              local new_indent = dot_idx - 1
              local spaces = string.rep(" ", new_indent)
              vim.api.nvim_buf_set_lines(bufnr, lnum - 2, lnum - 1, true, { stripped_prev })
              vim.api.nvim_set_current_line(spaces .. ".")
              pcall(vim.api.nvim_win_set_cursor, 0, { lnum, new_indent + 1 })
              return
            end
          end
        end

        -- 2. Check for before-dot split cursor adjustment in terminal Neovim
        if not vim.g.vscode and line:match("^%s*%&?%.") then
          local cursor = vim.api.nvim_win_get_cursor(0)
          local current_indent = vim.fn.indent(lnum)
          if cursor[2] == current_indent then
            pcall(vim.api.nvim_win_set_cursor, 0, { lnum, current_indent + 1 })
          end
        end

        -- 3. Original TextChangedI alignment logic (for typing dot or brackets)
        local should_align = false
        if line:match("^%s*%&?%.") then
          should_align = true
        elseif not vim.g.vscode and line:match("^%s*[)}%]]") then
          should_align = true
        end

        if should_align then
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

  -- If we are in VS Code, stop here to avoid conflicts with editor events
  if vim.g.vscode then
    return
  end

  -- Set up auto-closing pairs (autopair) - only in standard Neovim
  if opts.autopair ~= false then
    require("improv-indent.autopair").setup(opts.autopair_opts)
  end

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
