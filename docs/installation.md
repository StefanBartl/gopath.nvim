# Installation

Full installation reference for gopath.nvim: plugin-manager snippets, optional
dependencies, and recommended CLI tools. For a minimal quickstart, see the
[project README](../README.md).

## Contents

- [lazy.nvim](#lazynvim)
- [packer](#packer)
- [Optional dependencies](#optional-dependencies)
- [Recommended CLI tools](#recommended-cli-tools)

---

## lazy.nvim

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

## packer

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

## Optional dependencies

- *(optional)* [lib.nvim](https://github.com/StefanBartl/lib.nvim) — declared
  dependency for cross-platform path separators, notify styling, and the
  `ui.kit.confirm` create-on-missing dialog; falls back to built-ins /
  `vim.ui.select` when absent
- *(optional)* [open.nvim](https://github.com/StefanBartl/open.nvim) — external
  files (images, PDFs, URLs, …) are routed through its `default` handler
  (WSL-aware); falls back to gopath's built-in per-OS opener when absent
- *(optional)* [which-key.nvim](https://github.com/folke/which-key.nvim) — labels
  the `probe` keymap when installed
- *(optional)* [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) —
  adds an "Open in filetree" button to the create-on-missing dialog when the
  unresolved path has an existing ancestor directory

## Recommended CLI tools

| Tool | Purpose |
|------|---------|
| `fd` / `fdfind` | Fast file search for tailsearch and truncated.finder |
| `rg` (ripgrep)  | Fallback search when fd is unavailable |
| `git`           | Git-root detection for search roots |
