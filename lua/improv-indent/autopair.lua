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

-- Closing brackets we know how to reason about. Block-like statements land on
-- `empty_statement` instead, so they self-exclude.
local SEMI_BRACKETS = { [")"] = true, ["]"] = true, ["}"] = true }

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
  -- The closer is inserted now, so the statement's `;` is decided now too.
  if SEMI_BRACKETS[close_char] and M.opening_needs_semicolon(bufnr, open_char, close_char) then
    return open_char .. close_char .. ";" .. left .. left
  end
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
    -- Committing the auto-inserted closer: append the statement's `;` when the
    -- AST says this bracket terminates one.
    if SEMI_BRACKETS[close_char] and M.needs_semicolon(bufnr, close_char, c) then
      return right .. ";"
    end
    return right
  end
  -- A hand-typed closer with no auto-pair: `;` belongs immediately after it.
  if SEMI_BRACKETS[close_char] and M.needs_semicolon(bufnr, close_char, vim.api.nvim_win_get_cursor(0)[2]) then
    return close_char .. ";"
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

-- Statements whose missing `;` this feature will place. The bracket is only the
-- trigger; the decision comes from the node the `;` attaches to.
local SEMI_STATEMENTS = {
  rust = {
    let_declaration = true,
    expression_statement = true,
    use_declaration = true,
    type_item = true,
    const_item = true,
    static_item = true,
    mod_item = true,
  },
}

-- Parse a copy of the buffer with `new_line` at `row` and return the `;` node
-- at `semi_col` when it is a real terminator, else nil.
local function whatif_semicolon(bufnr, filetype, row, new_line, semi_col)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  lines[row] = new_line
  local text = table.concat(lines, "\n")

  local ok, parser = pcall(vim.treesitter.get_string_parser, text, filetype, { error = false })
  if not ok or not parser then
    return nil
  end
  local parsed_ok, trees = pcall(function()
    return parser:parse()
  end)
  if not parsed_ok or not trees or not trees[1] then
    return nil
  end

  local node = trees[1]:root():descendant_for_range(row - 1, semi_col, row - 1, semi_col + 1)
  if not node or node:type() ~= ";" or node:missing() then
    return nil
  end
  return node
end

-- `let x = if c { ... }` may still take an `else`, so a `;` decided while
-- closing its then-block (or a condition inside it) is premature.
local PREMATURE_TAIL = { if_expression = true }

local function terminates_statement(node, kinds)
  local parent = node:parent()
  if not (parent and kinds[parent:type()]) then
    return false
  end
  -- Error recovery can invent a `;` for a half-written statement (e.g.
  -- `let y = if foo(`), so only trust a cleanly parsed statement.
  if parent:has_error() then
    return false
  end
  local prev = node:prev_sibling()
  if prev and PREMATURE_TAIL[prev:type()] then
    return false
  end
  return true
end

-- True when a `;` at the closing bracket actually terminates an allowlisted
-- statement. close_col is the 0-based index of the closing bracket on the line,
-- present (auto-pair) or about to be typed; defaults to just behind the cursor.
function M.needs_semicolon(bufnr, close_char, close_col)
  local filetype = vim.bo[bufnr].filetype
  local kinds = SEMI_STATEMENTS[filetype]
  if not kinds then
    return false
  end

  close_char = close_char or "}"
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  close_col = close_col or (col - 1)

  local line = vim.api.nvim_get_current_line()
  local has = line:sub(close_col + 1, close_col + 1) == close_char
  -- The closer must be (or become) the last non-blank character on the line.
  if not line:sub(close_col + (has and 2 or 1)):match("^%s*$") then
    return false
  end

  -- The buffer is syntactically broken by the very `;` we are deciding on, so
  -- error recovery cannot be trusted. Parse a what-if copy instead.
  local new_line
  if has then
    new_line = line:sub(1, close_col + 1) .. ";" .. line:sub(close_col + 2)
  else
    new_line = line:sub(1, close_col) .. close_char .. ";" .. line:sub(close_col + 1)
  end
  local node = whatif_semicolon(bufnr, filetype, row, new_line, close_col + 1)
  if not node then
    return false
  end
  return terminates_statement(node, kinds)
end

-- Deciding at open time: the auto-pair is about to insert `open_char` +
-- `close_char`; say whether the `;` belongs right after that closer.
function M.opening_needs_semicolon(bufnr, open_char, close_char)
  local filetype = vim.bo[bufnr].filetype
  local kinds = SEMI_STATEMENTS[filetype]
  if not kinds then
    return false
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  -- Only when the auto-inserted closer would land at the end of the line.
  if not line:sub(col + 1):match("^%s*$") then
    return false
  end

  local new_line = line:sub(1, col) .. open_char .. close_char .. ";" .. line:sub(col + 1)
  local node = whatif_semicolon(bufnr, filetype, row, new_line, col + 2)
  if not node then
    return false
  end
  return terminates_statement(node, kinds)
end

function M.handle_cr()
  local bufnr = vim.api.nvim_get_current_buf()
  local pairs = M.get_pairs_for_buf(bufnr)
  local char_before, char_after = M.get_cursor_context()
  if pairs[char_before] == char_after then
    return cr_expand
  end
  -- Finishing a statement should place the `;` for you. Only when the cursor is
  -- at the end of a line whose last non-blank char is a deciding bracket.
  local col = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_get_current_line()
  local prev = line:sub(col, col)
  if SEMI_BRACKETS[prev] and line:sub(col + 1):match("^%s*$")
      and M.needs_semicolon(bufnr, prev, col - 1) then
    return "<End>;<CR>"
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
