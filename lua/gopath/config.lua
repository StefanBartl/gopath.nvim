---@module 'gopath.config'
---@brief User options merge + sane defaults. If `languages[ft].resolvers` is nil, we later expand to "all resolvers" for that language in the registry.

local M = {}

---@type GopathOptions
local defaults = {
  mode = "hybrid",
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,
  languages = {
    lua = { enable = true, resolvers = nil }, -- nil means "all resolvers"
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

