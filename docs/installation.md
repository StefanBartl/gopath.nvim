# Installation

Full installation reference for gopath.nvim: plugin-manager snippets, optional
dependencies, and recommended CLI tools. For a minimal quickstart, see the
[project README](../README.md).

## Contents

- [lazy.nvim](#lazynvim)
- [packer](#packer)
- [Dependencies](#dependencies)
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

> **`lib.nvim`** is now **required**: the `:Gopath` command layer is built on
> `lib.nvim.usercmd.composer`, which registers unconditionally. It also
> provides cross-platform separator handling (forward-slash canonicalization
> internally, OS-native paths when opening files) and the `ui.kit.confirm`
> create-on-missing dialog — those specific integrations still degrade to
> built-in fallbacks / `vim.ui.select` if lib.nvim is somehow missing, but
> `:Gopath` itself will fail to register without it.

## packer

```lua
use {
  "StefanBartl/gopath.nvim",
  requires = {
    "StefanBartl/lib.nvim",             -- required: :Gopath command layer + path helpers
    "nvim-treesitter/nvim-treesitter",  -- optional but recommended
  },
  config = function()
    require("gopath").setup({
      mode = "hybrid",
    })
  end,
}
```

## Dependencies

- **Required**: [lib.nvim](https://github.com/StefanBartl/lib.nvim) — the
  `:Gopath` command layer (`lib.nvim.usercmd.composer`); also used for
  cross-platform path separators, notify styling, and the `ui.kit.confirm`
  create-on-missing dialog (those specific integrations still fall back to
  built-ins / `vim.ui.select` if lib.nvim is somehow missing)
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
