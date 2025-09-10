---@module 'gopath.util.safe'
---@brief Minimal safe-call helpers with traceback preservation.

local M = {}

---@generic T
---@param fn fun(...): T
---@param ... any
---@return boolean ok, T|any result_or_err
function M.call(fn, ...)
  local function runner(...)
    return fn(...)
  end
  local ok, res = xpcall(runner, debug.traceback, ...)
  if ok then
    return true, res
  else
    return false, res
  end
end

return M

