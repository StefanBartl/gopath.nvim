---@module 'gopath.config'
---@brief User-options merge and sane defaults.
---@description
--- Owns a single module-level state table that is populated once by `setup()`
--- and read-only afterwards via `get()`. Deep-merges user options on top of
--- the built-in defaults (see `gopath.config.DEFAULTS`) so that callers can
--- override only what they need.

local M = {}

local defaults = require("gopath.config.DEFAULTS")

---True when `t` is a plain array: keys are exactly `1..n` with no holes and
---no string keys. An empty table counts as a list.
---@private
---@param t table
---@return boolean
local function is_list(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

---Recursively merge `src` into `dst`, preferring `src` values.
---
---Closed, curated array fields (e.g. `order`, `truncated.excluded_dirs`) are
---replaced wholesale rather than merged index-wise: index-wise merging (the
---same trap `vim.tbl_deep_extend` has for lists) would otherwise leave
---trailing default entries behind a shorter user-supplied list. E.g. a user
---setting `order = { "treesitter" }` to opt out of "lsp" and "builtin" would,
---under index-wise merging, get back `{ "treesitter", "treesitter", "builtin" }`
---(index 1 overwritten, indices 2-3 left over from the 3-element default) —
---"builtin" silently keeps running despite being explicitly left out.
---@private
---@param dst table
---@param src table
local function deep_merge_into(dst, src)
  assert(type(dst) == "table", "deep_merge_into: dst must be a table")
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      if is_list(v) and is_list(dst[k]) then
        dst[k] = vim.deepcopy(v)
      else
        deep_merge_into(dst[k], v)
      end
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
  if opts and type(opts) == "table" then deep_merge_into(state, opts) end
end

---Return the current effective configuration (read-only reference).
---@return GopathOptions
function M.get()
  return state
end

return M
