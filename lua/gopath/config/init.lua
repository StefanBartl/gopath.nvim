---@module 'gopath.config'
---@brief User-options merge and sane defaults.
---@description
--- Owns a single module-level state table that is populated once by `setup()`
--- and read-only afterwards via `get()`. Deep-merges user options on top of
--- the built-in defaults (see `gopath.config.DEFAULTS`) so that callers can
--- override only what they need.

local M = {}

local defaults = require("gopath.config.DEFAULTS")

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
