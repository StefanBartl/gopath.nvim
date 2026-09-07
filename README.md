> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# gopath.nvim

```
   ___  ___  ___  __ _____  _  _
  / __|/ _ \| _ \/_\|_   _|| || |
 | (_ | (_) |  _/ _ \ | |  | __ |
  \___|\___/|_|/_/ \_\|_|  |_||_|
                            .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
[![CI](https://github.com/StefanBartl/gopath.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/gopath.nvim/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)

One key, and you are at the file the cursor is pointing at — however that
reference happens to be written.

gopath.nvim resolves symbols, `require()` paths and arbitrary file references
under the cursor through a multi-phase pipeline, so a `require("a.b")`, a bare
path, a `:help` tag and a stack-trace line all end in the same place: the right
file, at the right line.

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get with the defaults](#what-you-get-with-the-defaults)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Full index of every page: [docs/README.md](./docs/README.md).

- [Features](./docs/FEATURES/README.md) — navigation capabilities, per-language support, the filesystem cache, and external-file opening.
- [Workflow](./docs/WORKFLOW.md) — which keymap to reach for, when to let the cache warm up, and what happens when the target does not exist.
- [Installation](./docs/installation.md) — every plugin manager, optional dependencies, recommended CLI tools.
- [Configuration](./docs/configuration.md) — every `setup()` option and its default.
- [Bindings cheatsheet](./docs/BINDINGS.md) — every keymap, command and autocommand, including `create_on_missing`.
- [Resolution pipeline](./docs/resolution.md) — how the cursor token becomes an opened file.
- [Filesystem cache](./docs/cache.md) — the `truncated.*` subsystem and truncated-path resolution.
- [Lua symbols and require resolution](./docs/lua-symbols.md) — the Lua language layer.
- [Health check and troubleshooting](./docs/troubleshooting.md) — `:checkhealth gopath` and the common issues.
- [Developer notes](./docs/Developer-Notes/DEV-README.md) — architecture, providers, resolvers.
- [Contributing](./docs/CONTRIBUTING.md) — ground rules, project layout, and how to add a resolver.

`:help gopath` is the same reference inside the editor.

---

## What it does

`gf` opens the file under the cursor, as long as the file under the cursor is
written as a path that exists relative to somewhere Neovim already knows about.
That covers a fraction of the references people actually write. A
`require("a.b.c")`, an `import` with a truncated tail, a `:help` tag, a
`file.lua:42:7` out of a stack trace — none of them are paths, and all of them
name a file.

gopath resolves them through a pipeline that tries progressively less certain
methods and stops at the first that answers:

| Phase | Uses |
| --- | --- |
| **LSP** | The language server's own definition, when there is one |
| **Treesitter** | The syntax node under the cursor, so a string is read as a string |
| **Whole-line extraction** | The line's shape — a stack-trace frame, a `:help` tag, a diagnostic |
| **Suffix search** | A truncated tail matched against the filesystem cache |
| **Fuzzy alternate** | The nearest plausible file, offered rather than opened |

Non-text targets — images, PDFs, other media — open in the system's default
application instead of being loaded as a text buffer. And if the resolved path
does not exist, gopath offers to create it rather than reporting failure.

---

## Around it

> **[buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim)** — the
> other direction: it *writes* a `require("foo.bar")` or `path:line` reference,
> gopath jumps back to one.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** and
> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — both call
> `resolve_at_cursor()` from outside, through `pcall`, so gopath stays a soft
> dependency on their side. What they rely on is
> [docs/FEATURES/INTEGRATIONS.md](./docs/FEATURES/INTEGRATIONS.md).
>
> **[open.nvim](https://github.com/StefanBartl/open.nvim)** — takes over where
> the target is not a file at all: a URL, a directory, an application.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — the `:Gopath` command tree, the keymaps, the autocommands and the path helpers |

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Strongly recommended — the Treesitter phase reads the node under the cursor instead of guessing at the line |
| An LSP client | The first and most certain phase of the pipeline |
| `fd` / `fdfind` / `rg` | Speed up resolving a truncated path tail; without them the cache is built by walking |

The CLI tools are declared in [docs/install.json](./docs/install.json) and read
by lib.nvim's
[deps module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains what is missing the first time `setup()` runs after installing;
`:Lib deps show gopath.nvim` repeats it any time. Turn the popup off in this
plugin's own spec with `deps_popup = false`, or globally with
`vim.g.lib_nvim_deps_disable_first_run = true`.

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/gopath.nvim",
  event = "VeryLazy",
  dependencies = {
    "StefanBartl/lib.nvim",            -- required
    "nvim-treesitter/nvim-treesitter", -- optional but recommended
  },
  opts = {
    mode = "hybrid",
  },
}
```

> **A lazy-load trigger is required.** `event = "VeryLazy"`, or `cmd` / `keys` /
> `ft` / `lazy = false` — but one of them. Without any, lazy.nvim never sources
> the plugin: no error, no keymaps, and `gP` silently does nothing.

The packer snippet and the optional dependencies are in
[docs/installation.md](./docs/installation.md).

---

## Quickstart

Put the cursor on a `require("a.b")`, a file path, a `:help` tag or a
stack-trace line, and press:

```
gP
```

That is the whole plugin. If the resolved path does not exist, gopath offers to
create it.

The command tree does the same jobs without keymaps, and answers a few questions
keymaps cannot:

```vim
:Gopath open vsplit    " resolve and open in a vertical split
:Gopath copy           " copy path:line:col to the clipboard
:Gopath check          " does the path under the cursor exist? offer to create
:Gopath debug          " print the resolution chain to :messages
:Gopath cache build    " warm the filesystem cache for truncated tails
```

Verify your setup any time with:

```vim
:checkhealth gopath
```

---

## What you get with the defaults

| Key | Does |
| --- | --- |
| `gP` | Resolve and open in the current window |
| `g\|` / `g\` / `g}` | The same, in a horizontal split, a vertical split, a new tab |
| `gM` | Reveal the target in the system file manager instead of opening it |
| `gY` | Copy `path:line:col` to the clipboard |
| `gC` | Check the path under the cursor exists; offer to create it if not |
| `g?` | Print the resolution chain to `:messages` — the first thing to try when a jump goes somewhere odd |
| `<leader>pp` | Probe the path under the cursor, or the selection, in a vertical split |

Set any config key to `false` to disable a single mapping, or
`mappings = false` for all of them. The full set, including the `:Gopath`
subcommand tree and its legacy `:GopathX` aliases, is the
[bindings cheatsheet](./docs/BINDINGS.md).

---

## Health check

```vim
:checkhealth gopath
```

Reports whether `lib.nvim` resolved, whether Treesitter and an LSP client are
available for the first two phases, which of `fd`/`fdfind`/`rg` was found, and
the state of the filesystem cache. Common issues are in
[docs/troubleshooting.md](./docs/troubleshooting.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.
[docs/CONTRIBUTING.md](./docs/CONTRIBUTING.md) has the ground rules and the
project layout; [docs/Developer-Notes/DEV-README.md](./docs/Developer-Notes/DEV-README.md)
covers the provider and resolver architecture a new phase has to fit into.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/gopath.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/gopath.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](./LICENSE).
