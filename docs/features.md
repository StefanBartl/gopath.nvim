# Features

Overview of gopath.nvim's navigation capabilities, and how they apply across
languages and filetypes. See the [project README](../README.md) for a quick
install/usage snippet, or the [Documentation index](./README.md) for deep
dives into individual subsystems.

## Contents

- [Core navigation](#core-navigation)
- [Whole-line extraction](#whole-line-extraction)
- [Suffix-based search](#suffix-based-search)
- [Visual selection probe](#visual-selection-probe)
- [Fuzzy alternate resolution](#fuzzy-alternate-resolution)
- [Create on missing](#create-on-missing)
- [External file opening](#external-file-opening)
- [Language Support](#language-support)

---

## Core navigation
- **Multi-provider**: LSP → Treesitter → Builtin, configurable order
- **Lua-aware**: `require("a.b")`, variable chains (`config.get()`), table keys
- **Help tags**: `vim.api.*`, `vim.fn.*`, `vim.loop` → `:help` target
- **Env vars**: `$VAR/path/file.md`, `${VAR}\rest\of\path.txt`
- **Line/column**: `file.lua:42:8`, `file.lua(42)`, `file.lua +42`

## Whole-line extraction  *(new in 0.3 — absorbed from pathfinder)*
Scans the **entire current line** for path-like strings using three heuristics:
- Stacktrace patterns (`path:line:col`, `path:line`)
- Extension-driven expansion (150+ extensions)
- Absolute paths (`/unix/path`, `C:\windows\path`, `\\unc\path`)

Works even when the cursor is **not** on the path segment itself (e.g. you're on a log message word and the path is elsewhere in the line).

## Suffix-based search  *(new in 0.3 — absorbed from pathprobe)*
Resolves **partial, truncated, and relative** paths by matching path tails across multiple search roots (buffer dir → cwd → git root → stdpath config/data/cache).

```
...nvim-data/lazy/gopath.nvim/lua/gopath/init.lua:42
gopath/resolvers/common/tailsearch.lua
health.lua
```

## Visual selection probe
`<leader>pp` in **visual mode**: select a path token and resolve it via suffix search.

## Fuzzy alternate resolution
When the exact file does not exist, suggests similar files using Levenshtein distance.

## Create on missing
If no file and no fuzzy alternate is found, gopath offers to create the file (button dialog via lib.nvim's `ui.kit.confirm`, falling back to `vim.ui.select` when lib.nvim is absent) and jumps straight into it. If the unresolved path has an existing ancestor directory and [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) is installed and set up, the dialog also offers to open that directory there instead. Disable with `create_on_missing.enable = false` — the `gC` keymap / `:GopathCheck` command still offer to create even then, since that's an explicit user action. See [docs/configuration.md](./configuration.md) and [docs/RESOLUTION.md](./RESOLUTION.md) for details.

## External file opening
Images, PDFs, media files open automatically in the system default application.

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
