---@module 'gopath.config'
--- User options merge + sane defaults with default keymaps and commands.

local M = {}

---@type GopathOptions
local defaults = {
    _debug = true,
  mode = "hybrid",
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,

  -- Language configuration
  -- nil/empty = universal features (filetoken, help) work for ALL filetypes
  -- Specific languages can add enhanced features
  languages = {
    lua = {
      enable = true,
      resolvers = nil, -- nil = all available resolvers
      custom_resolvers = nil, -- User-provided resolver modules
    },
  },

  -- Fuzzy alternate resolution
  alternate = {
    enable = true,
    similarity_threshold = 75,
  },

  -- External file opening
  external = {
    enable = true,
    extensions = nil, -- nil = use built-in defaults
  },

  -- Default keymaps (set to false to disable all, or set individual keys to false)
  mappings = {
    open_here = "gP",
    open_split = "g|",
    open_vsplit = "g\\",
    open_tab = "g}",
    copy_location = "gY",
    debug = "g?",
  },

  -- User commands (set to false to disable all)
  commands = {
    resolve = true,  -- :GopathResolve
    open = true,     -- :GopathOpen [edit|window|vsplit|tab]
    copy = true,     -- :GopathCopy
    debug = true,    -- :GopathDebug
  },
}

---@param dst table
---@param src table
local function deep_merge_into(dst, src)
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

---@param opts GopathOptions|nil
function M.setup(opts)
  if opts and type(opts) == "table" then
    deep_merge_into(state, opts)
  end
end

---@return GopathOptions
function M.get()
  return state
end

return M
