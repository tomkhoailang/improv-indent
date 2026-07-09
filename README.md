# improv-indent.nvim

A lightweight, configuration-driven auto-indentation engine for Neovim that ports VS Code's indentation rules and electric bracket-alignment algorithms.

## Features

- **VS Code Indentation Parity:** Executes regular expressions and comment-ignoring logic imported straight from VS Code's official language bundles.
- **Electric Bracket Alignment:** Emulates VS Code's `electricCharacter.ts` by searching backwards in the buffer (using Vim's optimized `searchpairpos`) to align closing brackets (`}`, `)`, `]`) exactly with their matching openers.
- **Rider/JetBrains-style Dot Chain Alignment:** Automatically aligns multiline dot chains to the first dot operator of the parent line, avoiding snapping back to column 0 or standard indent shifts.
- **Fully Automated Hooking:** Automatically disables native Vim indenter files and takes over the buffer's `indentexpr` for any language marked as `enabled = true`.
- **Session-Restore Support:** Automatically restores custom indentation settings after loading user sessions (`SessionLoadPost`).

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
