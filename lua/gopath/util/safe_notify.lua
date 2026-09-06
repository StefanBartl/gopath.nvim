---@module 'gopath.util.safe_notify'
---@brief Schedule vim.notify calls safely from fast / async contexts.
---@description
--- Gated on `dev_mode` intentionally: designed for debug-tracing from event
--- callbacks and luv timers where calling vim.notify directly would crash.
--- For regular warn/error notifications that must always fire, use
--- `gopath.util.log` instead.
---
--- The scheduling itself delegates to `lib.nvim.notify.safe`; this module only
--- adds the gopath-specific dev_mode gate on top.

local safe = require("lib.nvim.notify.safe")

local M = {}

---Safe notify using vim.defer_fn: defers execution by `delay_ms`.
---@param msg string
---@param level integer  vim.log.levels.*
---@param opts table|nil
---@param delay_ms integer|nil
function M.safe_notify_defer(msg, level, opts, delay_ms)
  local config = require("gopath.config").get()
  if not config.dev_mode then return nil end
  safe.defer(msg, level, opts, tonumber(delay_ms) or 0)
end

return M
