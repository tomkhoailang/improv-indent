# improv-indent.nvim

A lightweight, configuration-driven auto-indentation engine for Neovim that ports VS Code's indentation rules and electric bracket-alignment algorithms.

## Why does it exist?

For over a decade, Vim and Neovim users have wrestled with inconsistent indentation. Native Vim indent scripts are written in legacy, bug-prone Vimscript that is difficult to maintain and customize. Conversely, Treesitter indentation, while modern, is experimental and fails to capture visual line-continuation context (such as dot-chain alignments or generic parameters), often causing cursor jumps or under-indents.

`improv-indent` exists to solve this by providing a clean, configuration-driven alternative. It ports the exact regex rules, electric-bracket alignment, and on-enter actions used by VS Code's production-grade editor core into a micro Lua engine, delivering a seamless, real-time typing indentation experience out of the box.

## Disclaimer / A Note from the Author

Maybe there's already a plugin out there that solves this perfectly and provides consistent indentation, or maybe I just didn't know about it! In any case, this was built from scratch to solve my own editor frustrations, ft. Antigravity.

## How it works under the hood

To replicate VS Code's indentation behavior within Neovim, the engine performs the following operations:

1. **Comment & String Stripping:** Before counting brackets, it strips line comments (e.g. `#` in Ruby, `//` in Rust/C#/Java) and block comments (`/* ... */`), as well as string literals from the line. This prevents brackets inside comments or strings from throwing off the indentation count.
2. **VS Code-Parity Regex Evaluation:** If a language defines `increaseIndentPattern` or `decreaseIndentPattern` in `indent_rules.lua` (which are translated from VS Code's configurations), we compile and evaluate them. If a language doesn't have regex rules (like C#, Java, C++), the engine automatically falls back to token-based bracket tracking.
3. **Optimized Bracket Alignment (`searchpairpos`):** Instead of just doing a naive `base_indent - shiftwidth` when a closing bracket (`}`, `)`, `]`) is typed, the engine uses Neovim's built-in, C-optimized `searchpairpos()` to search backwards and locate the exact opening bracket. It queries Neovim's syntax highlighting tree (`synIDattr`) to ignore matches inside comments and strings. Once the exact opener line is found, we match its indentation level 1-to-1, replicating VS Code's `electricCharacter.ts` matching bracket alignment.
4. **Smart Dot Chain Alignment:** When splitting a line or typing a dot (`.`), if `align_dot_chains` is enabled, the engine scans the previous line, finds the first method call dot operator (excluding comments, strings, and numbers like `1.5`), and aligns the dot precisely.
5. **VS Code-Parity Autopairs:** When typing opening characters (`(`, `[`, `{`, `"`, `'`, `` ` ``), the engine evaluates word boundaries and character whitelists modeled after VS Code's `characterPair.ts` heuristics. If matched, it auto-closes the pair. It also handles overtyping, backspace deletion, Enter-key expansion, and visual selection wrapping natively.

## Features

- **VS Code Indentation Parity:** Executes regular expressions and comment-ignoring logic imported straight from VS Code's official language bundles.
- **Electric Bracket Alignment:** Emulates VS Code's `electricCharacter.ts` by searching backwards in the buffer (using Vim's optimized `searchpairpos`) to align closing brackets (`}`, `)`, `]`) exactly with their matching openers.
- **Rider/JetBrains-style Dot Chain Alignment:** Automatically aligns multiline dot chains to the first dot operator of the parent line, avoiding snapping back to column 0 or standard indent shifts.
- **Fully Automated Hooking:** Automatically disables native Vim indenter files and takes over the buffer's `indentexpr` for any language marked as `enabled = true`.
- **Session-Restore Support:** Automatically restores custom indentation settings after loading user sessions (`SessionLoadPost`).
- **VS Code-Parity Autopairs:** Implements smart auto-closing pair heuristics, quote word-boundary checks, overtyping (skip closing character), backspace pair deletion, and visual selection wrapping.

## Examples & Usecases

Here are some real-world usecases showing how the **indentation level** behaves when typing or pressing Enter:

### 1. Ruby/JavaScript Multiline Dot Chains
* **Before:** Default auto-indenters snap dot operators back to column 0 or standard block levels, losing visual alignment:
  ```ruby
  counts_map = MasterSamples.cupping_session_samples
  # Hit Enter and type '.joins':
  .joins(:score) # <- Snapped to column 0 or standard indent
  ```
* **After:** `improv-indent` automatically detects the chain and aligns the dot precisely with the first dot of the parent line:
  ```ruby
  counts_map = MasterSamples.cupping_session_samples
                            .joins(:score) # <- Snapped to align perfectly with the first dot
  ```

### 2. Unmatched Delimiter Indent (All Languages)
* **Before:** Hitting Enter after an unclosed delimiter might fail to indent the next line:
  ```rust
  let x = my_function(
  # Hit Enter: cursor is placed at column 0 without indent
  ```
* **After:** The engine tracks unmatched opening delimiters (`{`, `(`, `[`) to automatically indent the next line:
  ```rust
  let x = my_function(
      # Automatically indents by +4 spaces (shiftwidth) on Enter
  ```

### 3. Closing Bracket Snapping & Alignment (All Languages)
* **Before:** Typing a closing bracket on a new line might remain at the current block level or snap to the wrong column:
  ```rust
  fn main() {
      if condition {
          do_something();
          } -- Typing '}' stays at column 8
  ```
* **After:** Typing a closing bracket instantly queries the buffer, finds the matching opener line, and aligns the closing bracket line with it:
  ```rust
  fn main() {
      if condition {
          do_something();
      } -- Snaps to column 4 to align with the 'if' line
  } -- Snaps to column 0 to align with the 'fn' line
  ```

---

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "tomkhoailang/improv-indent",
  config = function()
    require("improv-indent").setup({
      -- Global configuration options (optional)
      align_dot_chains = true, -- Enable Rider-style dot chain alignment
      rules = {
        -- Overrides or new languages can be defined here
        -- e.g. to enable python:
        -- python = { enabled = true }
      }
    })
  end
}
```

---

## Configuration

By default, only `ruby` and `rust` are enabled out of the box. 

To enable/disable languages, you can either:
1. Open the plugin's `lua/indent_rules.lua` file and toggle `enabled = true` / `enabled = false`.
2. Or pass overrides inside the `setup()` function:

```lua
require("improv-indent").setup({
  rules = {
    rust = { enabled = false },   -- Disable custom indenter for Rust
    cs = { enabled = true },       -- Enable custom indenter for C#
    java = { enabled = true },     -- Enable custom indenter for Java
  }
})
```

### VS Code-style Autopair (Branch: `autopair`)

If you are on the `autopair` branch, `improv-indent` ships with a complete standalone, VS Code-parity autopair implementation. It can be customized or disabled via the `autopair_opts` table in the setup call:

```lua
require("improv-indent").setup({
  align_dot_chains = true,
  -- Autopair options (optional)
  autopair = true, -- Set to false to disable the autopair engine completely
  autopair_opts = {
    -- Set to false if you want to manage CR/BS mappings in your own mapping chain
    map_cr = true, 
    map_bs = true,
  }
})
```

**Heuristics implemented:**
- **Opening Pair Auto-closing:** Opening brackets auto-close only when typed before spaces, closing brackets, or punctuation.
- **Quote Word-Boundary Check:** Quotes do not auto-close when typed immediately after a word character (e.g. typing `'` in `don't` will not insert a closing quote).
- **Overtyping:** Typing a closing character moves the cursor past the existing character instead of inserting a duplicate.
- **Smart Delete:** Pressing `<BS>` inside empty brackets (e.g. `(|)`) deletes both the opening and closing brackets.
- **Visual Selection Wrapping:** Selecting text in Visual mode and typing an opening character wraps the selection in the corresponding pair.

### Disabling Treesitter Indentation Conflicts

Since `nvim-treesitter`'s experimental indentation engine often overrides `indentexpr`, it is recommended to disable it for any languages where you enable `improv-indent`:

```lua
require("nvim-treesitter.configs").setup({
  indent = {
    enable = true,
    disable = { "ruby", "rust" } -- Disable treesitter's indenter for these languages
  }
})
```

---

## Supported Languages

The plugin comes pre-configured with rules extracted from VS Code's source repo for over 35 languages, including:
- Ruby
- Rust
- C++ / C
- C# (`cs`)
- Java
- Go
- HTML / CSS / SCSS / Less
- Lua
- YAML / JSON
- Swift
- Julia
- Dart
- and more!

## License

MIT
