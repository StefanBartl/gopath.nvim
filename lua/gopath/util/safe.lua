---@module 'gopath.util.safe'
---@brief Minimal safe-call helper with traceback preservation.
---@description
--- Wraps `xpcall` with `debug.traceback` so that errors arriving from deep
--- resolver chains include a full stack trace. Every caller should prefer
--- `safe.call` over a bare `pcall` when the error message matters.

local M = {}

---Execute `fn(...)` and return `(true, result)` on success or
---`(false, traceback_string)` on error.
---@generic T
---@param fn  fun(...): T
---@param ... any
---@return boolean ok, T|string result_or_traceback
function M.call(fn, ...)
  return xpcall(fn, debug.traceback, ...)
end

return M
