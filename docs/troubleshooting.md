# Health Check & Troubleshooting

Diagnostics and fixes for common gopath.nvim issues.

## Contents

- [Health Check](#health-check)
- [Troubleshooting](#troubleshooting)

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
