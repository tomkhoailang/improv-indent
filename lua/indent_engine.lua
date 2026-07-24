local M = {}
local rules = require("indent_rules").rules

local function count_unmatched_brackets(s, lang)
  local lang_rules = rules[lang]
  local comment_pat = lang_rules and lang_rules.comment or "#.*"
  -- Remove comments
  s = s:gsub(comment_pat, "")
  if lang == "rust" then
    -- Also strip block comments for Rust
    s = s:gsub("/%*.-%*/", "")
  end
  -- Remove single-line strings (handling escaped quotes and backslashes)
  s = s:gsub('\\\\', ""):gsub('\\"', ""):gsub('\\\'', "")
  s = s:gsub('"[^"]*"', ""):gsub("'[^']*'", "")

  local count = 0
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == "(" or c == "[" or c == "{" then
      count = count + 1
    elseif c == ")" or c == "]" or c == "}" then
      count = count - 1
    end
  end
  return count
end

local function get_matching_open_bracket_indent(lnum, cline)
  -- Find the first closing bracket on the line
  local col = cline:find("[)}%]]")
  if not col then return nil end

  local char = cline:sub(col, col)
  local open_char, close_char
  if char == "}" then
    open_char, close_char = "{", "}"
  elseif char == ")" then
    open_char, close_char = "(", ")"
  elseif char == "]" then
    open_char, close_char = "[", "]"
  end

  local open_pat = open_char == "[" and "\\[" or open_char
  local close_pat = close_char == "]" and "\\]" or close_char

  local skip_expr = "synIDattr(synID(line('.'), col('.'), 0), 'name') =~? 'comment\\|string'"
  local ok_win, win = pcall(vim.api.nvim_get_current_win)
  if ok_win and win and vim.api.nvim_win_is_valid(win) then
    local save_cursor = vim.api.nvim_win_get_cursor(win)
    pcall(vim.api.nvim_win_set_cursor, win, { lnum, col - 1 })
    local match_pos = vim.fn.searchpairpos(open_pat, "", close_pat, "bWn", skip_expr)
    pcall(vim.api.nvim_win_set_cursor, win, save_cursor)
    if match_pos[1] > 0 then
      return vim.fn.indent(match_pos[1])
    end
  end
  return nil
end


function M.get_indent(lang, lnum)
  lnum = lnum or vim.v.lnum
  local lang_rules = rules[lang]
  if not lang_rules then
    return vim.fn.indent(lnum)
  end

  local plnum = vim.fn.prevnonblank(lnum - 1)
  if plnum == 0 then
    return 0
  end

  local pline = vim.fn.getline(plnum)
  local cline = vim.fn.getline(lnum)

  -- Compile patterns if not already compiled and not empty
  if lang_rules.increase ~= "" and not lang_rules.compiled_increase then
    lang_rules.compiled_increase = vim.regex(lang_rules.increase)
  end
  if lang_rules.decrease ~= "" and not lang_rules.compiled_decrease then
    lang_rules.compiled_decrease = vim.regex(lang_rules.decrease)
  end

  local base_indent = vim.fn.indent(plnum)
  local sw = vim.fn.shiftwidth()


  -- 2. Determine if we should increase indentation
  local should_indent = false
  local inc_match = lang_rules.compiled_increase and lang_rules.compiled_increase:match_str(pline)
  if inc_match or count_unmatched_brackets(pline, lang) > 0 then
    should_indent = true
  end

  -- 3. Determine if we should decrease indentation
  local should_outdent = false
  local dec_match = lang_rules.compiled_decrease and lang_rules.compiled_decrease:match_str(cline)
  if dec_match or cline:match("^%s*[)}%]]") then
    should_outdent = true
  end

  if should_indent then
    base_indent = base_indent + sw
  end

  if should_outdent then
    local matched_indent = get_matching_open_bracket_indent(lnum, cline)
    if matched_indent then
      base_indent = matched_indent
    else
      base_indent = base_indent - sw
    end
  end

  return base_indent
end

return M
