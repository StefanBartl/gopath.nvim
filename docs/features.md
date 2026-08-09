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
When the exact file does not exist, suggests similar files using Levenshtein
distance with a prefix bonus (a truncated/abbreviated name sharing a long
common prefix with the target, e.g. `confi` vs `config.lua`, scores at
least as high as its prefix-length ratio). Each candidate in the selection
list shows its size and modification recency (`filename (85%) — 2.3 KB,
modified 5m ago`). The picker itself defers to your configured
`vim.ui.select` backend (telescope-ui-select, dressing.nvim, …) when one is
installed, via lib.nvim's `ui.kit.select` with `respect_override = true` —
there is no separate `alternate.ui_backend` config key to set.

## Create on missing
If no file and no fuzzy alternate is found, gopath offers to create the file (button dialog via lib.nvim's `ui.kit.confirm`, falling back to `vim.ui.select` when lib.nvim is absent) and jumps straight into it. If the unresolved path has an existing ancestor directory and [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) is installed and set up, the dialog also offers to open that directory there instead. Disable with `create_on_missing.enable = false` — the `gC` keymap / `:GopathCheck` command still offer to create even then, since that's an explicit user action. See [docs/configuration.md](./configuration.md) and [docs/RESOLUTION.md](./RESOLUTION.md) for details.

## External file opening
Images, PDFs, media files open automatically in the system default
application. `external.extensions` extends the built-in extension list
(does not replace it); `external.enable = false` disables the whole
feature. See [docs/configuration.md](./configuration.md).

Opener fallback chain: [open.nvim](https://github.com/StefanBartl/open.nvim)'s
`default` handler (if installed) → lib.nvim's cross-platform system opener →
a minimal built-in per-OS opener (`open`/`xdg-open`/`explorer.exe`). Each
stage falls through to the next on dispatch failure (e.g. `open.nvim`
erroring, or no `xdg-open` on a bare Linux install) instead of giving up
after the first one that's merely *available*.

---

## Language Support

### Lua (full support)
- `require("a.b.c")` → resolves to `lua/a/b/c.lua`
- Bare identifier: `local resolver = require("gopath.resolve")` → cursor on
  `resolver` alone (no `.field`) → opens `resolve.lua` (`identifier_locator`,
  treesitter-provider pass, runs before the chain resolver)
- `local x = require("mod"); x.func()` → cursor on `x` → opens mod.lua
- Table chain: `config.get()` → opens definition of `get` in `config` module
- LSP-first: when `order = { "lsp", "treesitter", "builtin" }` (the default),
  a chain like `config.setup()` first tries `symbol_locator.via_lsp`, which
  jumps straight to the exact definition line/column; treesitter's own chain
  walk only runs as a fallback when LSP has no client or times out
  (`lsp_timeout_ms`)
- `local_to_module` enhancement: LSP results pointing to `require()` lines
- Value origin: follows config table values to their source module, e.g.
  `local cfg = require("plugin.config"); cfg.highlight.enable_x` → cursor on
  `enable_x` → `config.lua` at the `enable_x = ...` line, however deeply the
  key is nested (`M.foo = {...}`, `M = { foo = {...} }`, `return { foo =
  {...} }`, …); the file's root-identifier candidates are cached per mtime

### All filetypes (universal)
- File paths (relative, absolute, with `:line:col`, `(line)`, `+line`)
- URLs → `vim.ui.open` / system browser
- `:help` tags
- `$ENV_VAR/path/file.md`
- Whole-line stacktrace extraction
- Suffix-based partial-path search
