local M = {}

local left = "<Left>"
local right = "<Right>"
local del_bs = "<Del><BS>"
local esc = "<Esc>"
local cr_expand = "<CR><Esc>O"

local default_pair_definitions = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
  ['"'] = '"',
  ["'"] = "'",
  ["`"] = "`",
  ["<"] = ">",
}

local visual_pairs = {
  ["("] = { "(", ")" },
  ["["] = { "[", "]" },
  ["{"] = { "{", "}" },
  ['"'] = { '"', '"' },
  ["'"] = { "'", "'" },
  ["`"] = { "`", "`" },
}

local allowed_brackets = "'\"`;:.,=}])> \t"
local allowed_quotes = ";:.,=}])> \t"

-- Quotes that do NOT open a literal -> never insert a closer.
-- Keyed by filetype, then quote char; values are the preceding characters.
local QUOTE_NOT_LITERAL = {
  rust = { ["'"] = { "&", "<", "+" } },
}

-- The prose guard below (`don't`) cannot tell a word from a literal prefix
-- (`b'`), so a language opts out for the quotes it uses prefixes with.
local QUOTE_PREFIX_AFTER_WORD = {
  rust = { ["'"] = true, ['"'] = true },
}

-- `<` opens a type-argument list after a name (`Vec<`), but is a comparison
-- after whitespace or an operator (`a < b`). Keyed by filetype; the value is
-- the pattern the character before `<` must match. Add other filetypes with
-- their own pattern when needed, e.g.
--   typescriptreact = "[^%w_]",  -- a JSX tag starts after space/(/=
local ANGLE_PAIR = {
  rust = "[%w_:>]",
}

local ns = vim.api.nvim_create_namespace("improv_indent_autopair")

local function track_inserted_char(bufnr)
  vim.schedule(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      local r, c = unpack(vim.api.nvim_win_get_cursor(0))
      vim.api.nvim_buf_set_extmark(bufnr, ns, r - 1, c, {
        right_gravity = true,
      })
    end
  end)
end

M.user_pairs = nil

function M.get_cursor_context()
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  local char_before = col > 0 and line:sub(col, col) or ""
  local char_after = line:sub(col + 1, col + 1)
  return char_before, char_after
end

function M.get_pairs_for_buf(bufnr)
  local ft = vim.bo[bufnr].filetype
  local base_ft = ft:gsub("react$", "")

  local ok, rules = pcall(require, "indent_rules")
  if ok and rules.rules then
    local lang_rules = rules.rules[ft] or rules.rules[base_ft]
    if lang_rules and lang_rules.pairs then
      return lang_rules.pairs
    end
  end

  return M.user_pairs or default_pair_definitions
end

function M.handle_open(open_char)
  local bufnr = vim.api.nvim_get_current_buf()
  local pairs = M.get_pairs_for_buf(bufnr)
  local char_before, char_after = M.get_cursor_context()
  local close_char = pairs[open_char] or default_pair_definitions[open_char] or ""

  if close_char == "" then
    return open_char
  end

  -- `<` only pairs where it opens a type/JSX argument list.
  if open_char == "<" then
    local allowed_after = ANGLE_PAIR[vim.bo[bufnr].filetype]
    if not allowed_after or not char_before:match(allowed_after) then
      return open_char
    end
  elseif open_char == '"' or open_char == "'" or open_char == "`" then
    local ft = vim.bo[bufnr].filetype
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local last = vim.api.nvim_get_current_line():sub(1, col):match("(%S)%s*$") or ""

    -- A quote that provably does NOT open a literal never gets a closer.
    for _, ch in ipairs((QUOTE_NOT_LITERAL[ft] or {})[open_char] or {}) do
      if last == ch then
        return open_char
      end
    end

    -- Prose guard (`don't`). It cannot tell `b'` from `don'`, so a language
    -- opts out for the quotes it uses as prefixes.
    local prefixed = (QUOTE_PREFIX_AFTER_WORD[ft] or {})[open_char]
    if not prefixed and char_before:match("[%w_]") then
      return open_char
    end

    if char_after ~= "" and not allowed_quotes:find(char_after, 1, true) then
      return open_char
    end
  else
    -- Bracket checks
    if char_after ~= "" and not allowed_brackets:find(char_after, 1, true) then
      return open_char
    end
  end

  track_inserted_char(bufnr)
  return open_char .. close_char .. left
end

function M.handle_close(close_char)
  local bufnr = vim.api.nvim_get_current_buf()
  local _, char_after = M.get_cursor_context()
  if char_after == close_char then
    local r, c = unpack(vim.api.nvim_win_get_cursor(0))
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { r - 1, c }, { r - 1, c }, {})
    if #marks > 0 then
      vim.api.nvim_buf_del_extmark(bufnr, ns, marks[1][1])
    end
    return right
  end
  return close_char
end

function M.handle_backspace()
  local bufnr = vim.api.nvim_get_current_buf()
  local pairs = M.get_pairs_for_buf(bufnr)
  local char_before, char_after = M.get_cursor_context()
  if pairs[char_before] == char_after then
    local r, c = unpack(vim.api.nvim_win_get_cursor(0))
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { r - 1, c }, { r - 1, c }, {})
    if #marks > 0 then
      vim.api.nvim_buf_del_extmark(bufnr, ns, marks[1][1])
      return del_bs
    end
  end
  return "<BS>"
end

function M.handle_cr()
  local bufnr = vim.api.nvim_get_current_buf()
  local pairs = M.get_pairs_for_buf(bufnr)
  local char_before, char_after = M.get_cursor_context()
  if pairs[char_before] == char_after then
    return cr_expand
  end
  return "<CR>"
end

function M.wrap_selection(char)
  local pair = visual_pairs[char]
  if not pair then return char end

  local s_start = vim.fn.getpos("v")
  local s_end = vim.fn.getpos(".")

  if s_start[2] > s_end[2] or (s_start[2] == s_end[2] and s_start[3] > s_end[3]) then
    s_start, s_end = s_end, s_start
  end

  local start_line, start_col = s_start[2], s_start[3]
  local end_line, end_col = s_end[2], s_end[3]

  -- Single-line selection wrapping
  if start_line == end_line then
    local line = vim.api.nvim_buf_get_lines(0, start_line - 1, start_line, false)[1]
    if line then
      local before = line:sub(1, start_col - 1)
      local selected = line:sub(start_col, end_col)
      local after = line:sub(end_col + 1)
      local new_line = before .. pair[1] .. selected .. pair[2] .. after
      vim.api.nvim_buf_set_lines(0, start_line - 1, start_line, false, { new_line })

      vim.schedule(function()
        vim.fn.setpos(".", { s_end[1], end_line, end_col + 2, 0 })
        vim.fn.setpos("v", { s_start[1], start_line, start_col + 1, 0 })
        vim.cmd("normal! gv")
      end)
      return esc
    end
  end

  return char
end

function M.setup(opts)
  opts = opts or {}

  -- Store user-configured pairs if provided
  if opts.pairs then
    M.user_pairs = opts.pairs
  end

  -- Register Insert mode expression mappings
  local function map_insert(char, fn)
    vim.keymap.set("i", char, fn, { expr = true, replace_keycodes = true, silent = true })
  end

  -- Register Visual mode expression mappings for selection wrapping
  local function map_visual(char, fn)
    vim.keymap.set("x", char, fn, { expr = true, replace_keycodes = true, silent = true })
  end

  -- Map opening/closing pairs in Insert mode
  local pairs_to_map = M.user_pairs or default_pair_definitions
  for open_char, close_char in pairs(pairs_to_map) do
    if open_char ~= close_char then
      map_insert(open_char, function()
        return M.handle_open(open_char)
      end)
      map_insert(close_char, function()
        return M.handle_close(close_char)
      end)
    else
      -- Quotes (same character for open/close)
      map_insert(open_char, function()
        local bufnr = vim.api.nvim_get_current_buf()
        local _, char_after = M.get_cursor_context()
        if char_after == open_char then
          local r, c = unpack(vim.api.nvim_win_get_cursor(0))
          local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { r - 1, c }, { r - 1, c }, {})
          if #marks > 0 then
            vim.api.nvim_buf_del_extmark(bufnr, ns, marks[1][1])
          end
          return right
        end
        return M.handle_open(open_char)
      end)
    end

    -- Map selection wrapping in Visual mode
    map_visual(open_char, function()
      return M.wrap_selection(open_char)
    end)
  end

  -- Map backspace and enter in Insert mode
  map_insert("<BS>", M.handle_backspace)
  map_insert("<CR>", M.handle_cr)

  -- Clear namespace on InsertLeave
  vim.api.nvim_create_autocmd("InsertLeave", {
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
    end,
  })
end

return M
