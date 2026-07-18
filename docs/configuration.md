# Configuration

Full `setup()` option reference for gopath.nvim, with defaults and inline
comments. For deep dives into specific subsystems, see the
[Documentation index](./README.md) (cache/truncated-path resolution,
resolution pipeline, Lua symbol resolution, keymap/command cheatsheet).

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

  -- Offer to create a resolved-but-missing file instead of just erroring
  -- (gP/g|/g\/g}). `gC` / :GopathCheck always offer, regardless of `enable`.
  -- Dialog: lib.nvim's ui.kit.confirm, falling back to vim.ui.select.
  create_on_missing = {
    enable  = true,
    confirm = true,  -- false = create silently, no dialog
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
    check         = "gC",
    probe         = "<leader>pp",  -- n + v mode
  },

  -- User commands (false = all disabled; individual keys = false to skip)
  commands = {
    resolve = true,
    open    = true,
    copy    = true,
    debug   = true,
    check   = true,
  },

  -- Label the probe keymap via which-key.nvim, if installed (no-op otherwise)
  which_key = true,
})
```
