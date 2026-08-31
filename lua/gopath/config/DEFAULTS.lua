---@module 'gopath.config.DEFAULTS'
---@brief Plugin-side default configuration for gopath.nvim.

---@type GopathOptions
return {
  dev_mode = false,
  mode = "hybrid",
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,

  -- Per-filetype resolver configuration.
  -- `enable=false` disables gopath's language resolvers for that filetype
  -- (universal features like file paths and help tags still work).
  -- `custom_resolvers` are user resolvers that run BEFORE the built-in ones.
  languages = {
    lua = { enable = true, resolvers = nil, custom_resolvers = nil },
    python = { enable = true, resolvers = nil, custom_resolvers = nil },
    javascript = { enable = true, resolvers = nil, custom_resolvers = nil },
    javascriptreact = { enable = true, resolvers = nil, custom_resolvers = nil },
    typescript = { enable = true, resolvers = nil, custom_resolvers = nil },
    typescriptreact = { enable = true, resolvers = nil, custom_resolvers = nil },
    rust = { enable = true, resolvers = nil, custom_resolvers = nil },
    go = { enable = true, resolvers = nil, custom_resolvers = nil },
    c = { enable = true, resolvers = nil, custom_resolvers = nil },
    cpp = { enable = true, resolvers = nil, custom_resolvers = nil },
    cs = { enable = true, resolvers = nil, custom_resolvers = nil },
    zig = { enable = true, resolvers = nil, custom_resolvers = nil },
    java = { enable = true, resolvers = nil, custom_resolvers = nil },
  },

  alternate = {
    enable = true,
    similarity_threshold = 75,

    -- Candidates you have chosen from this dialog before rise within their
    -- similarity band. `max_bonus` is that band, in similarity points: 10 on
    -- a 0-100 scale that admits everything from 75 up, so history breaks
    -- near-ties and never inverts a clear winner. 0 disables the reordering
    -- while still recording; `enable = false` disables both.
    frecency = {
      enable = true,
      max_bonus = 10,
      dir = nil, -- default: lib.nvim's own, stdpath("data")/lib.nvim/frecency
    },
  },

  external = {
    enable = true,
    extensions = nil,

    -- PDF handling. Only takes effect when pdfport.nvim is installed;
    -- without it a PDF always goes straight to the system viewer.
    pdf = {
      picker = true, -- false → always open with `default`, no chooser
      default = "system", -- mode used when picker = false
    },
  },

  url = {
    enable = true,
    bare_hosts = true,
    schemes = nil,
    tlds = nil,
  },

  env_variable_resolution = {
    enable = true,
  },

  create_on_missing = {
    enable = true,
    confirm = true,
  },

  truncated = {
    enable = true,
    use_cache = true,
    cache_refresh_interval = 600,
    -- How long the per-runtimepath-entry name index stays valid, in ms. Only
    -- a brand-new top-level entry can be hidden by a stale index; lower this
    -- if you install plugins while Neovim is running.
    rtp_index_ttl_ms = 30000,
    max_cache_age = 3600,
    live_search_fallback = true,
    similarity_threshold = 75,
    cache_roots = nil,
    max_depth = 6,
    excluded_dirs = {
      ".git",
      ".github",
      "node_modules",
      "target",
      "build",
      ".cache",
      "venv",
    },
    watch_patterns = nil,
    auto_rebuild_on_save = false,
  },

  linepath = {
    enable = true,
    cascade = true,
  },

  tailsearch = {
    enable = true,
    max_components = 6,
    ask_on_ambiguous = true,
    roots = nil,
    limit = 100,
  },

  mappings = {
    open_here = "gP",
    open_split = "g|",
    open_vsplit = "g\\",
    open_tab = "g}",
    open_explorer = "gM",
    copy_location = "gY",
    debug = "g?",
    probe = "<leader>pp",
    check = "gC",
  },

  commands = {
    resolve = true,
    open = true,
    copy = true,
    debug = true,
    check = true,
  },

  -- which-key.nvim is a soft dependency: label registration for the
  -- probe keymap is skipped silently when which-key is not installed.
  which_key = true,

  -- One-time "which CLI tools does this plugin want, and why" popup on
  -- first setup() after install (via lib.nvim.deps). false disables it for
  -- this plugin specifically, right here in the spec passed to setup() —
  -- no vim.g needed. See README.
  deps_popup = true,
}
