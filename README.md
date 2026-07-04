> This project is in beta. Core features are stable; APIs may evolve.

# Gopath.nvim — Intelligent Navigation for Neovim
```
   ___  ___  ___  __ _____  _  _
  / __|/ _ \| _ \/_\|_   _|| || |
 | (_ | (_) |  _/ _ \ | |  | __ |
  \___|\___/|_|/_/ \_\|_|  |_||_|
```

![version](https://img.shields.io/badge/version-0.3.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lazy.nvim](https://img.shields.io/badge/lazy.nvim-supported-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

> 💡 Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim):
> use buffer-ctx to generate a `require("foo.bar")` / `path:line` reference,
> and gopath to jump straight back to it from anywhere.

A modular file-navigation plugin for Neovim. Resolves symbols, require() paths, and arbitrary file references using a multi-phase pipeline: LSP → Treesitter → whole-line extraction → suffix search → fuzzy alternate.

---

## Contents

- [Features](#features)
- [Installation](#installation)
- [Keymaps](#keymaps)
- [Commands](#commands)
- [Resolution Pipeline](#resolution-pipeline)
- [Configuration](#configuration)
- [Documentation](#documentation)
- [Language Support](#language-support)
- [Health Check](#health-check)
- [Troubleshooting](#troubleshooting)

---

## Features

### Core navigation
- **Multi-provider**: LSP → Treesitter → Builtin, configurable order
- **Lua-aware**: `require("a.b")`, variable chains (`config.get()`), table keys
- **Help tags**: `vim.api.*`, `vim.fn.*`, `vim.loop` → `:help` target
- **Env vars**: `$VAR/path/file.md`, `${VAR}\rest\of\path.txt`
- **Line/column**: `file.lua:42:8`, `file.lua(42)`, `file.lua +42`

### Whole-line extraction  *(new in 0.3 — absorbed from pathfinder)*
Scans the **entire current line** for path-like strings using three heuristics:
- Stacktrace patterns (`path:line:col`, `path:line`)
- Extension-driven expansion (150+ extensions)
- Absolute paths (`/unix/path`, `C:\windows\path`, `\\unc\path`)

Works even when the cursor is **not** on the path segment itself (e.g. you're on a log message word and the path is elsewhere in the line).

### Suffix-based search  *(new in 0.3 — absorbed from pathprobe)*
Resolves **partial, truncated, and relative** paths by matching path tails across multiple search roots (buffer dir → cwd → git root → stdpath config/data/cache).

```
...nvim-data/lazy/gopath.nvim/lua/gopath/init.lua:42
gopath/resolvers/common/tailsearch.lua
health.lua
```

### Visual selection probe
`<leader>pp` in **visual mode**: select a path token and resolve it via suffix search.

### Fuzzy alternate resolution
When the exact file does not exist, suggests similar files using Levenshtein distance.

### Nearest-folder fallback
If no file and no alternate is found, opens the nearest existing ancestor directory (picked up by netrw / oil / nvim-tree).

### External file opening
Images, PDFs, media files open automatically in the system default application.

---

## Installation

### lazy.nvim

```lua
{
  "StefanBartl/gopath.nvim",
  event = "VeryLazy",
  dependencies = {
    "StefanBartl/lib.nvim",             -- cross-platform path helpers
    "nvim-treesitter/nvim-treesitter",  -- optional but recommended
  },
  opts = {
    mode = "hybrid",
  },
}
```

> **`lib.nvim`** provides the cross-platform separator handling (forward-slash
> canonicalization internally, OS-native paths when opening files). gopath
> degrades to built-in fallbacks and warns once if it is missing, but installing
> it is recommended for correct behaviour on Windows.

### packer

```lua
use {
  "StefanBartl/gopath.nvim",
  requires = {
    "StefanBartl/lib.nvim",             -- optional, cross-platform path helpers
    "nvim-treesitter/nvim-treesitter",  -- optional but recommended
  },
  config = function()
    require("gopath").setup({
      mode = "hybrid",
    })
  end,
}
```

### Optional dependencies

- *(optional)* [lib.nvim](https://github.com/StefanBartl/lib.nvim) — cross-platform
  path separators and notify styling; falls back to built-ins when absent
- *(optional)* [which-key.nvim](https://github.com/folke/which-key.nvim) — labels
  the `probe` keymap when installed

### Recommended CLI tools

| Tool | Purpose |
|------|---------|
| `fd` / `fdfind` | Fast file search for tailsearch and truncated.finder |
| `rg` (ripgrep)  | Fallback search when fd is unavailable |
| `git`           | Git-root detection for search roots |

---

## Keymaps

All keymaps are configurable. Defaults:

| Key | Mode | Action |
|-----|------|--------|
| `gP` | n | Open in current window |
| `g\|` | n | Open in horizontal split |
| `g\` | n | Open in vertical split |
| `g}` | n | Open in new tab |
| `gY` | n | Copy `path:line:col` to clipboard |
| `g?` | n | Debug resolution under cursor |
| `<leader>pp` | n | Probe path under cursor (suffix search, vsplit) |
| `<leader>pp` | v | Probe selected text (suffix search, vsplit) |

### Disable / remap

```lua
opts = {
  mappings = {
    open_here  = "gP",
    open_split = "g|",
    open_vsplit = "g\\",
    open_tab   = "g}",
    copy_location = "gY",
    debug      = "g?",
    probe      = "<leader>pp",   -- false to disable
  },
}
```

---

## Commands

### Unified command

```
:Gopath <subcommand> [args]
```

Tab-completion works at every level.

| Command | Action |
|---------|--------|
| `:Gopath open [edit\|split\|vsplit\|tab]` | Resolve and open |
| `:Gopath copy` | Copy `path:line:col` to clipboard |
| `:Gopath debug` | Print resolution chain to `:messages` |
| `:Gopath probe [edit\|split\|vsplit]` | Probe path under cursor / selection |
| `:Gopath cache build` | Rebuild filesystem index |
| `:Gopath cache info` | Show cache statistics |
| `:Gopath cache add-root <dir>` | Add directory to cache search roots |

### Individual aliases

All original commands are preserved as aliases:

| Alias | Equivalent |
|-------|-----------|
| `:GopathOpen [mode]` | `:Gopath open [mode]` |
| `:GopathCopy` | `:Gopath copy` |
| `:GopathDebug` | `:Gopath debug` |
| `:GopathResolve` | `:Gopath debug` |
| `:GopathProbe[!]` | `:Gopath probe` (`!` = split) |
| `:GopathCacheBuild` | `:Gopath cache build` |
| `:GopathCacheInfo` | `:Gopath cache info` |
| `:GopathCacheAddRoot <dir>` | `:Gopath cache add-root <dir>` |

---

## Resolution Pipeline

Each phase runs in order; the first success is returned.

| Phase | Resolver | Trigger |
|-------|----------|---------|
| 1 | `:help` subject | token looks like a vim help tag |
| 2 | `$VAR` env path | token starts with `$` or `${` |
| 3 | filetoken | `<cfile>` under cursor; searches rtp, &path, tailsearch |
| 3.5 | **linepath** | scans whole current line; absolute → cwd-rel → tailsearch |
| 4 | Language (Lua) | LSP / Treesitter / builtin Lua resolvers |
| 5 | Fallback | raw `<cfile>` result or filetoken low-confidence |

When a file is not found:
1. **Fuzzy alternate** — Levenshtein similarity in the same directory
2. **Nearest folder** — opens closest existing ancestor directory

> Full walkthrough (async open flow, token normalization, fallbacks):
> [docs/RESOLUTION.md](./docs/RESOLUTION.md).

---

## Configuration

Full reference with defaults:

```lua
require("gopath").setup({
  -- Resolution mode: "hybrid" | "lsp" | "treesitter" | "builtin"
  mode  = "hybrid",
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,

  -- Language-specific resolvers
  languages = {
    lua = { enable = true },
  },

  -- Whole-line path extraction (Phase 3.5)
  linepath = {
    enable = true,
  },

  -- Suffix-based filesystem search
  tailsearch = {
    enable           = true,
    max_components   = 6,       -- number of trailing path segments to try
    ask_on_ambiguous = true,    -- show vim.ui.select when multiple matches
    roots            = nil,     -- nil = auto: bufdir→cwd→git root→stdpaths
    limit            = 100,     -- max files returned per root
  },

  -- Fuzzy alternate when file not found
  alternate = {
    enable               = true,
    similarity_threshold = 75,  -- 0-100; higher = stricter
  },

  -- External file opener (images, PDFs, etc.)
  external = {
    enable     = true,
    extensions = nil,  -- nil = use built-in list
  },

  -- $VAR / ${VAR} prefix expansion
  env_variable_resolution = {
    enable = true,
  },

  -- Truncated path cache ("..." prefix paths) — see docs/CACHE.md
  truncated = {
    enable                 = true,
    use_cache              = true,
    cache_refresh_interval = 600,   -- seconds between auto-refreshes
    max_cache_age          = 3600,  -- seconds before cache is considered stale
    live_search_fallback   = true,
    similarity_threshold   = 75,
    cache_roots            = nil,   -- nil = auto-detect drives/stdpaths
    max_depth              = 6,
    excluded_dirs          = { ".git", "node_modules", "target", "build", ".cache" },
    auto_rebuild_on_save   = false,
  },

  -- Keymaps (false = disabled, string | string[] = key(s))
  mappings = {
    open_here     = "gP",
    open_split    = "g|",
    open_vsplit   = "g\\",
    open_tab      = "g}",
    copy_location = "gY",
    debug         = "g?",
    probe         = "<leader>pp",  -- n + v mode
  },

  -- User commands (false = all disabled; individual keys = false to skip)
  commands = {
    resolve = true,
    open    = true,
    copy    = true,
    debug   = true,
  },

  -- Label the probe keymap via which-key.nvim, if installed (no-op otherwise)
  which_key = true,
})
```

---

## Documentation

Deep-dive docs for the more complex subsystems, available in English and German.
Full index: [docs/README.md](./docs/README.md).

| Topic | English | Deutsch |
|-------|---------|---------|
| Filesystem cache & truncated-path resolution | [Cache](./docs/CACHE.md) | [Cache-DE](./docs/CACHE-DE.md) |
| Resolution pipeline (cursor → opened file) | [Resolution](./docs/RESOLUTION.md) | [Resolution-DE](./docs/RESOLUTION-DE.md) |
| Lua symbol & require resolution | [Lua Symbols](./docs/LUA-SYMBOLS.md) | [Lua-Symbols-DE](./docs/LUA-SYMBOLS-DE.md) |

See also: [docs/BINDINGS.md](./docs/BINDINGS.md) (full keymap/command/autocmd
cheatsheet) and [docs/ROADMAP.md](./docs/ROADMAP.md) (implemented features,
checklist audits, planned work).

For contributors, see the [Developer Notes](./docs/Developer-Notes/DEV-README.md).

---

## Language Support

### Lua (full support)
- `require("a.b.c")` → resolves to `lua/a/b/c.lua`
- `local x = require("mod"); x.func()` → cursor on `x` → opens mod.lua
- Table chain: `config.get()` → opens definition of `get` in `config` module
- `local_to_module` enhancement: LSP results pointing to `require()` lines
- Value origin: follows config table values to their source module

### All filetypes (universal)
- File paths (relative, absolute, with `:line:col`, `(line)`, `+line`)
- URLs → `vim.ui.open` / system browser
- `:help` tags
- `$ENV_VAR/path/file.md`
- Whole-line stacktrace extraction
- Suffix-based partial-path search

---

## Health Check

```vim
:checkhealth gopath
```

Checks:
- Neovim version compatibility
- External tools: `fd`/`fdfind`, `rg`, `git`
- Active LSP clients
- Tree-sitter parsers
- which-key.nvim availability
- Configuration (linepath, tailsearch, alternate, keymaps)
- Truncated path cache status

---

## Troubleshooting

### `gP` does nothing
1. `:Gopath debug` — shows what the resolver found (or why it failed)
2. `:checkhealth gopath` — verify external tools and config
3. Ensure Neovim ≥ 0.9

### Path not found
- Try `<leader>pp` (probe) — uses suffix search across more roots
- Run `:Gopath probe` to see if tailsearch finds it
- Add an explicit root: `:Gopath cache add-root <dir>`

### Truncated path (`...`) not resolving
- Check cache: `:Gopath cache info`
- Rebuild: `:Gopath cache build`
- Ensure `fd` or `rg` is installed (`:checkhealth gopath`)

### Multiple matches / wrong file opened
- `tailsearch.ask_on_ambiguous = true` (default) shows `vim.ui.select`
- Set `tailsearch.roots` explicitly to narrow the search scope
