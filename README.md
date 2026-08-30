> **Active development.** This repository is in its development phase — breaking changes are to be expected at any time. Pin a commit or tag if you depend on it.

# Gopath.nvim — Intelligent Navigation for Neovim
```
   ___  ___  ___  __ _____  _  _
  / __|/ _ \| _ \/_\|_   _|| || |
 | (_ | (_) |  _/ _ \ | |  | __ |
  \___|\___/|_|/_/ \_\|_|  |_||_|
```

![CI](https://github.com/StefanBartl/gopath.nvim/actions/workflows/ci.yml/badge.svg)
![version](https://img.shields.io/badge/version-0.3.0-blue.svg)
![status](https://img.shields.io/badge/status-beta-orange.svg)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-success.svg)
![Lazy.nvim](https://img.shields.io/badge/lazy.nvim-supported-success.svg)
![Lua](https://img.shields.io/badge/language-Lua-yellow.svg)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey.svg)

A modular file-navigation plugin for Neovim. gopath.nvim resolves symbols, `require()` paths, and arbitrary file references under your cursor using a multi-phase pipeline — LSP → Treesitter → whole-line extraction → suffix search → fuzzy alternate — so a single keypress takes you to the right file, at the right line, however the reference is written. Non-text targets (images, PDFs, other media) open straight in your system's default application instead of as a text buffer.

> Pairs well with [buffer-ctx.nvim](https://github.com/StefanBartl/buffer-ctx.nvim):
> use buffer-ctx to generate a `require("foo.bar")` / `path:line` reference,
> and gopath to jump straight back to it from anywhere.

---

## Table of Content

- [Quickstart](#quickstart)
- [Documentation](#documentation)

---

## Quickstart

```lua
-- lazy.nvim
{
  "StefanBartl/gopath.nvim",
  event = "VeryLazy",
  dependencies = {
    "StefanBartl/lib.nvim",             -- required: :Gopath command layer + path helpers
    "nvim-treesitter/nvim-treesitter",  -- optional but recommended
  },
  opts = {
    mode = "hybrid",
  },
}
```

> `event = "VeryLazy"` (or another lazy-load trigger: `cmd`, `keys`, `ft`,
> or `lazy = false`) is **required**. Without one, lazy.nvim never sources
> the plugin — no error, no keymaps, `gP` just does nothing.

Then press `gP` with your cursor on a `require("a.b")`, a file path, a `:help` tag, or a stack-trace line to jump straight to it. If the resolved path doesn't exist, gopath offers to create it (`gC` / `:GopathCheck` always offer this explicitly). Run `:checkhealth gopath` to verify your setup.

See [docs/installation.md](./docs/installation.md) for the packer snippet and optional dependencies.

`fd`/`fdfind`/`rg` speed up resolving a truncated path tail — declared in
[`docs/install.json`](docs/install.json), parsed by lib.nvim's
[`deps` module](https://github.com/StefanBartl/lib.nvim/blob/main/lua/lib/nvim/deps/README.md).
A popup explains what's missing the first time `setup()` runs after
installing gopath.nvim; `:Lib deps show gopath.nvim` repeats it any time.
Disable it **right in this plugin's own spec**:
`require("gopath").setup({ deps_popup = false })`.
`vim.g.lib_nvim_deps_disable_first_run = true` (every plugin) /
`vim.g.lib_nvim_deps_disabled_plugins = { "gopath.nvim" }` also still
work, for turning it off without touching any plugin's config.

---

## Documentation

- [Features](./docs/FEATURES/README.md) — navigation capabilities, per-language support, the filesystem cache, and external-file opening.
- [Installation](./docs/installation.md) — lazy.nvim/packer snippets, optional dependencies, recommended CLI tools.
- [Configuration](./docs/configuration.md) — full `setup()` option reference with defaults.
- [Keymaps, commands & autocommands](./docs/BINDINGS.md) — full cheatsheet of every binding, including `create_on_missing`.
- [Resolution pipeline](./docs/RESOLUTION.md) — how the cursor token becomes an opened file ([Deutsch](./docs/RESOLUTION-DE.md)).
- [Filesystem cache & truncated-path resolution](./docs/CACHE.md) — the `truncated.*` subsystem ([Deutsch](./docs/CACHE-DE.md)).
- [Lua symbol & require resolution](./docs/LUA-SYMBOLS.md) — the Lua language layer ([Deutsch](./docs/LUA-SYMBOLS-DE.md)).
- [Health check & troubleshooting](./docs/troubleshooting.md) — `:checkhealth gopath` and common issues.
- [Developer notes](./docs/Developer-Notes/DEV-README.md) — architecture, providers, resolvers, for contributors.

Full index of all docs: [docs/README.md](./docs/README.md).

## License

MIT — see [LICENSE](LICENSE).
