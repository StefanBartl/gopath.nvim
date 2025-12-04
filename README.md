# Gopath.nvim - Intelligent Navigation for Neovim
```
   ___  ___  ___  __ _____  _  _
  / __|/ _ \| _ \/_\|_   _|| || |
 | (_ | (_) |  _/ _ \ | |  | __ |
  \___|\___/|_|/_/ \_\|_|  |_||_|
```

![version](https://img.shields.io/badge/version-0.2.0-blue.svg)
![status](https://img.shields.io/badge/status-stable-success.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lazy.nvim](https://img.shields.io/badge/lazy.nvim-supported-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A powerful, modular navigation plugin for Neovim that intelligently resolves symbols, modules, and file paths using LSP, Treesitter, and custom resolvers. Features fuzzy alternate resolution and automatic external file opening.

---

## Table of content

  - [✨ Features](#features)
    - [Smart Navigation](#smart-navigation)
    - [Fuzzy Alternate Resolution](#fuzzy-alternate-resolution)
    - [External File Opening](#external-file-opening)
    - [Line/Column Support (currently lua only)](#linecolumn-support-currently-lua-only)
  - [Direct Symbol Definition Jump](#direct-symbol-definition-jump)
  - [Summary](#summary)
  - [📦 Installation](#installation)
    - [Using lazy.nvim (Recommended)](#using-lazynvim-recommended)
      - [Minimal Setup (with defaults)](#minimal-setup-with-defaults)
      - [Custom Configuration](#custom-configuration)
    - [Using packer.nvim](#using-packernvim)
  - [🚀 Usage](#usage)
    - [Default Keymaps](#default-keymaps)
    - [User Commands](#user-commands)
  - [💡 Examples](#examples)
    - [Lua Module Navigation](#lua-module-navigation)
    - [Markdown Links](#markdown-links)
    - [Image Files](#image-files)
    - [Typo Correction](#typo-correction)
    - [Help Tags](#help-tags)
  - [⚙️ Configuration](#configuration)
    - [Modes](#modes)
    - [Provider Order](#provider-order)
    - [Alternate Resolution](#alternate-resolution)
    - [External File Opening](#external-file-opening-1)
  - [🎨 Language Support](#language-support)
    - [Built-in Support](#built-in-support)
    - [Universal Features (work in any filetype)](#universal-features-work-in-any-filetype)
  - [🐛 Troubleshooting](#troubleshooting)
    - [Nothing happens when I press `gP`](#nothing-happens-when-i-press-gp)
    - ["No match: no-match"](#no-match-no-match)
    - [External files open with wrong app](#external-files-open-with-wrong-app)
    - [Alternate resolution not working](#alternate-resolution-not-working)
  - [📚 Advanced Usage](#advanced-usage)
  - [🗺️ Roadmap](#roadmap)
    - [Planned Features](#planned-features)
    - [Under Consideration](#under-consideration)
  - [🤝 Contributing](#contributing)
  - [💬 Feedback](#feedback)
  - [📄 License](#license)
  - [🙏 Acknowledgments](#acknowledgments)

---

## ✨ Features

### Smart Navigation
 **Multi-Provider Resolution**: LSP → Treesitter → Builtin fallback chain
 **Universal File Support**: Works in **any filetype** (Lua, Markdown, Text, etc.)
 **Context-Aware**: Understands Lua modules, require() paths, table chains, and more
 **Help Integration**: Seamless `:help` tag resolution for `vim.api`, `vim.fn`, `vim.loop`

---

### Fuzzy Alternate Resolution
When a file path has a typo or doesn't exist:
* Finds similar files using Levenshtein distance (configurable threshold)
* Interactive selection with similarity percentages
* Auto-sorted by match quality

**Example:**
```lua
-- Typo in path
"lua/cofnig.lua"  -- Press gP
→ Shows: config.lua (87%), confirm.lua (65%)
```

---

### External File Opening
Automatically opens non-text files with system default apps:
* **Images**: png, jpg, gif, svg, webp...
* **Documents**: pdf, docx, xlsx, pptx...
* **Media**: mp4, mp3, avi, mkv...
* **URLs**: http://, https://, file://

**Cross-platform**: macOS (`open`), Linux (`xdg-open`), Windows (PowerShell)

---

### Line/Column Support (currently lua only)
Gopath automatically parses and respects line and column numbers in file paths:
`"lua/gopath/config.lua:15:8"` -> Opens file and cursor jumps directly in line and row ()

Also works in...
- Error message format:
`Error in ...nvim-data/lazy/gopath.nvim/lua/gopath/init.lua:42`

- Parenthesis format:
`init.lua(42)`

- Vim-style format:
`init.lua +42`

---

## Direct Symbol Definition Jump
Jump not just to file, but to exact line where symbol is defined.
**Example:**

```lua
local config = require("gopath.config")

-- Later in file...
config.get()
^^^^^^
-- Cursor here on config → gP
-- Opens gopath/config.lua (not at specific line, module-level)
```

---

## Summary

Feature 3 is now fully implemented:

✅ **LSP prioritization**: `order = { "lsp", "treesitter", "builtin" }`
✅ **Enhanced symbol_locator**: Better LSP handling, fallback logic
✅ **New identifier_locator**: Bare variable → module resolution (Feature 2!)
✅ **Smart registry**: Proper provider ordering and fallbacks
✅ **Precise navigation**: Jump directly to symbol definitions

**Bonus:** Feature 2 (Symbol-to-Path) is also complete as part of this implementation!

**What works now:**
- `local x = require("mod")` → cursor on `x` → opens `mod.lua`
- `x.func()` → cursor on `func` → opens `mod.lua` at `func` definition
- `require("mod").func` → opens `mod.lua` at `func` definition
- All with LSP precision when available, treesitter fallback when not


---

## 📦 Installation

### Using lazy.nvim (Recommended)

#### Minimal Setup (with defaults)
```lua
{
  "yourusername/gopath.nvim",
  event = "VeryLazy",
  config = function()
    require("gopath").setup()
  end,
}
```

#### Custom Configuration
```lua
{
  "yourusername/gopath.nvim",
  event = "VeryLazy",
  dependencies = {
    "nvim-treesitter/nvim-treesitter", -- Optional but recommended
  },
  opts = {
    mode = "hybrid",  -- "hybrid" | "lsp" | "treesitter" | "builtin"

    -- Fuzzy alternate resolution
    alternate = {
      enable = true,
      similarity_threshold = 75,  -- 0-100
    },

    -- External file opening
    external = {
      enable = true,
    },

    -- Custom keymaps (optional - defaults shown)
    mappings = {
      open_here = "gP",        -- Open in current window
      open_split = "g|",       -- Open in horizontal split
      open_vsplit = "g\\",     -- Open in vertical split
      open_tab = "g}",         -- Open in new tab
      copy_location = "gY",    -- Copy path:line:col
      debug = "g?",            -- Debug resolution
      -- Set any to false to disable
    },

    -- User commands (optional)
    commands = {
      resolve = true,  -- :GopathResolve
      open = true,     -- :GopathOpen [edit|window|vsplit|tab]
      copy = true,     -- :GopathCopy
      debug = true,    -- :GopathDebug
    },
  },
}
```

### Using packer.nvim
```lua
use {
  "yourusername/gopath.nvim",
  config = function()
    require("gopath").setup({
      -- Your config here
    })
  end,
}
```

---

## 🚀 Usage

### Default Keymaps

After installation, these keymaps work **in any buffer** (code, markdown, help, terminal, messages):

| Keymap | Action | Description |
|--------|--------|-------------|
| `gP` | Open here | Open target in current window |
| `g\|` | Open split | Open target in horizontal split |
| `g\` | Open vsplit | Open target in vertical split |
| `g}` | Open tab | Open target in new tab |
| `gY` | Copy location | Copy `path:line:col` to clipboard |
| `g?` | Debug | Show resolution debug info |

**Disable default keymaps:**
```lua
opts = {
  mappings = false,  -- Disable all default keymaps
}
```

**Custom keymaps:**
```lua
-- In your lazy.nvim config
keys = {
  { "<leader>gd", function() require("gopath.commands").resolve_and_open() end, desc = "Go to definition" },
  { "<leader>gs", function() require("gopath.commands").resolve_and_open("window") end, desc = "Go to split" },
},
opts = {
  mappings = false,  -- Disable defaults when using custom
}
```

### User Commands

| Command | Description |
|---------|-------------|
| `:GopathResolve` | Show resolution debug info |
| `:GopathOpen [mode]` | Open target (modes: `edit`, `window`, `vsplit`, `tab`) |
| `:GopathCopy` | Copy location to clipboard |
| `:GopathDebug` | Debug resolution under cursor |

---

## 💡 Examples

### Lua Module Navigation
```lua
local config = require("gopath.config")
--                      ^^^^^^^^^^^^^^
-- Cursor here → gP → Opens lua/gopath/config.lua

config.get()
--     ^^^
-- Cursor here → gP → Jumps to get() function definition
```

### Markdown Links
```markdown
Check out [this file](lua/gopath/init.lua)
                      ^^^^^^^^^^^^^^^^^^^^
Cursor here → gP → Opens the file

Visit [GitHub](https://github.com/user/repo)
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Cursor here → gP → Opens in browser
```

### Image Files
```markdown
![Logo](assets/logo.png)
        ^^^^^^^^^^^^^^^^
Cursor here → gP → Opens in image viewer
```

### Typo Correction
```lua
require("gopaht.config")
--       ^^^^^^
-- Typo: "gopaht" instead of "gopath"
-- gP → Shows selection:
--   gopath.config (92%)
--   gopath.commands (78%)
```

### Help Tags
```lua
vim.api.nvim_buf_get_lines(0, 0, -1, false)
--      ^^^^^^^^^^^^^^^^^^^
-- Cursor here → gP → Opens :help nvim_buf_get_lines()
```

---

## ⚙️ Configuration

### Modes

| Mode | Description | Providers Used |
|------|-------------|----------------|
| `hybrid` (default) | Try all providers in order | LSP → Treesitter → Builtin |
| `lsp` | LSP-only (fastest for LSP-enabled files) | LSP only |
| `treesitter` | Treesitter-only (semantic analysis) | Treesitter only |
| `builtin` | Builtin-only (no dependencies) | Builtin only |

### Provider Order
```lua
opts = {
  mode = "hybrid",
  order = { "treesitter", "lsp", "builtin" },  -- Custom order
}
```

### Alternate Resolution
```lua
opts = {
  alternate = {
    enable = true,
    similarity_threshold = 80,  -- Higher = stricter matching (0-100)
  },
}
```

### External File Opening
```lua
opts = {
  external = {
    enable = true,
    extensions = { "png", "jpg", "pdf" },  -- Custom list (nil = use defaults)
  },
}
```

---

## 🎨 Language Support

### Built-in Support
* **Lua**: Full support (modules, chains, tables, fields)
* **All others**: Universal features (file paths, URLs, help tags)

### Universal Features (work in any filetype)
* ✅ File paths (relative, absolute, with line numbers)
* ✅ URLs (http://, https://, file://)
* ✅ Help tags (`:help` subjects)
* ✅ `<cfile>` expansion
* ✅ Fuzzy alternate resolution
* ✅ External file opening

---

## 🐛 Troubleshooting

### Nothing happens when I press `gP`
1. Check if plugin is loaded: `:lua print(vim.inspect(require("gopath")))`
2. Run `:GopathDebug` to see resolution details
3. Check Neovim version (requires 0.9+)

### "No match: no-match"
* The text under cursor couldn't be resolved
* Try visual selection or move cursor to a different position
* Check if file path is correct

### External files open with wrong app
* **Windows**: Check file associations in Settings → Apps → Default apps
* **macOS**: Right-click file → Get Info → Open with
* **Linux**: Check `xdg-mime` default associations

### Alternate resolution not working
* Check threshold: Lower values find more matches
* Verify target directory exists
* Run `:GopathDebug` to see what path was attempted

---

## 📚 Advanced Usage

For advanced features like:
* Custom language resolvers
* Provider configuration
* Debugging internals
* Contributing guidelines

See [DEV-README.md](DEV-README.md)

---

## 🗺️ Roadmap

### Planned Features
- [ ] User-defined custom language resolvers
- [ ] TypeScript/JavaScript support
- [ ] Python import resolution
- [ ] Go package navigation
- [ ] Configurable UI backend for alternate selection (Telescope, fzf-lua)
- [ ] File preview in alternate selection
- [ ] Learning system (prioritize frequently selected alternates)
- [ ] Async file scanning for large directories
- [ ] Truncated Path Resolution - Resolve abbreviated paths from logs and error messages (e.g., `...AppData\Local\nvim\init.lua`).
- [ ] Symbol-to-Module Resolution - Jump from variable to the module it references

---

### Under Consideration
- [ ] Remote file support (SSH, HTTP)
- [ ] Git integration (jump to remote repository)
- [ ] Project-local configuration files
- [ ] Custom similarity algorithms

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes
4. Test thoroughly
5. Submit a pull request

See [DEV-README.md](DEV-README.md) for development guidelines.

---

## 💬 Feedback

Your feedback is very welcome!

Use the [GitHub Issue Tracker](https://github.com/yourusername/gopath.nvim/issues) to:
* Report bugs
* Suggest new features
* Ask usage questions
* Share thoughts on workflow

For discussions, visit [GitHub Discussions](https://github.com/yourusername/gopath.nvim/discussions).

If you find this plugin useful, please give it a ⭐ on GitHub!

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

* Inspired by Vim's `gf` command
* Built on Neovim's LSP and Treesitter APIs
* Community feedback and contributions

---
