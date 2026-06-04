---@module 'gopath.config'
---@brief User-options merge and sane defaults.
---@description
--- Owns a single module-level state table that is populated once by `setup()`
--- and read-only afterwards via `get()`. Deep-merges user options on top of
--- the built-in defaults so that callers can override only what they need.

local M = {}

---@type GopathOptions
local defaults = {
  dev_mode = false,
  mode     = "hybrid",
  order    = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,

  -- Per-filetype resolver configuration.
  -- `enable=false` disables gopath's language resolvers for that filetype
  -- (universal features like file paths and help tags still work).
  -- `custom_resolvers` are user resolvers that run BEFORE the built-in ones.
  languages = {
    lua             = { enable = true, resolvers = nil, custom_resolvers = nil },
    python          = { enable = true, resolvers = nil, custom_resolvers = nil },
    javascript      = { enable = true, resolvers = nil, custom_resolvers = nil },
    javascriptreact = { enable = true, resolvers = nil, custom_resolvers = nil },
    typescript      = { enable = true, resolvers = nil, custom_resolvers = nil },
    typescriptreact = { enable = true, resolvers = nil, custom_resolvers = nil },
    rust            = { enable = true, resolvers = nil, custom_resolvers = nil },
    go              = { enable = true, resolvers = nil, custom_resolvers = nil },
    c               = { enable = true, resolvers = nil, custom_resolvers = nil },
    cpp             = { enable = true, resolvers = nil, custom_resolvers = nil },
    cs              = { enable = true, resolvers = nil, custom_resolvers = nil },
    zig             = { enable = true, resolvers = nil, custom_resolvers = nil },
    java            = { enable = true, resolvers = nil, custom_resolvers = nil },
  },

  alternate = {
    enable               = true,
    similarity_threshold = 75,
  },

  external = {
    enable     = true,
    extensions = nil,
  },

  env_variable_resolution = {
    enable = true,
  },

  truncated = {
    enable                  = true,
    use_cache               = true,
    cache_refresh_interval  = 600,
    max_cache_age           = 3600,
    live_search_fallback    = true,
    similarity_threshold    = 75,
    cache_roots             = nil,
    max_depth               = 6,
    excluded_dirs           = {
      ".git", ".github", "node_modules", "target",
      "build", ".cache", "venv",
    },
    watch_patterns          = nil,
    auto_rebuild_on_save    = false,
  },

  mappings = {
    open_here      = "gP",
    open_split     = "g|",
    open_vsplit    = "g\\",
    open_tab       = "g}",
    copy_location  = "gY",
    debug          = "g?",
  },

  commands = {
    resolve = true,
    open    = true,
    copy    = true,
    debug   = true,
  },
}

---Recursively merge `src` into `dst`, preferring `src` values.
---@private
---@param dst table
---@param src table
local function deep_merge_into(dst, src)
  assert(type(dst) == "table", "deep_merge_into: dst must be a table")
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_merge_into(dst[k], v)
    else
      dst[k] = v
    end
  end
end

---@type GopathOptions
local state = vim.deepcopy(defaults)

---Merge `opts` on top of the built-in defaults.
---Calling setup() more than once re-merges on top of the previous state.
---@param opts GopathOptions|nil
function M.setup(opts)
  if opts and type(opts) == "table" then
    deep_merge_into(state, opts)
  end
end

---Return the current effective configuration (read-only reference).
---@return GopathOptions
function M.get()
  return state
end

return M
