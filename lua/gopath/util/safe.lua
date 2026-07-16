---@module 'gopath.util.safe'
---@brief Minimal safe-call helper with traceback preservation.
---@description
--- Wraps `xpcall` with `debug.traceback` so that errors arriving from deep
--- resolver chains include a full stack trace. Every caller should prefer
--- `safe.call` over a bare `pcall` when the error message matters.
--- Delegates to lib.lua.error.safe_call, which does the same thing (also
--- correctly forwards multiple/nil-embedded return values on LuaJIT, which
--- lacks table.pack) — the one difference is its failure value is a
--- structured `{kind, message, data}` table rather than a raw traceback
--- string, which this module's only caller (gopath.resolve) never reads.

local M = {}

---Execute `fn(...)` and return `(true, result)` on success or
---`(false, error)` on error.
---@generic T
---@param fn  fun(...): T
---@param ... any
---@return boolean ok, T|table result_or_error
function M.call(fn, ...)
  return require("lib.lua.error").safe_call(fn, ...)
end

return M
