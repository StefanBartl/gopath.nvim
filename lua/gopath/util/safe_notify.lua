---@module 'gopath.util.safe_notify'
---@brief Schedule vim.notify calls safely from fast / async contexts.
---@description
--- All functions here are gated on `dev_mode` intentionally: they are designed
--- for debug-tracing from event callbacks and luv timers where calling
--- vim.notify directly would crash. For regular warn/error notifications that
--- must always fire, use `gopath.util.log` instead.
---
--- The scheduling itself (schedule/defer/wrap) delegates to
--- `lib.nvim.notify.safe`, which implements the same three strategies; this
--- module only adds the gopath-specific dev_mode gate on top.

local safe = require("lib.nvim.notify.safe")

local M = {}

-- Safe notify using vim.schedule: schedules the notify on the main loop immediately.
-- Usage: M.safe_notify_schedule("message", vim.log.levels.INFO, { timeout = 3000 })
function M.safe_notify_schedule(msg, level, opts)
  local config = require("gopath.config").get()
  if not config.dev_mode then return nil end
  safe.schedule(msg, level, opts)
end

-- Safe notify using vim.defer_fn: defers execution by `delay_ms`.
-- Usage: M.safe_notify_defer("message", vim.log.levels.INFO, { timeout = 3000 }, 50)
function M.safe_notify_defer(msg, level, opts, delay_ms)
  local config = require("gopath.config").get()
  if not config.dev_mode then return nil end
  safe.defer(msg, level, opts, tonumber(delay_ms) or 0)
end

-- Safe notify using schedule_wrap: returns a function that is already scheduled.
-- This is convenient for repeated calls from fast contexts.
-- Usage:
--   local notify = require('utils.safe_notify').scheduled_notifier()
--   notify("hello", vim.log.levels.INFO)
function M.scheduled_notifier()
  local config = require("gopath.config").get()
  if not config.dev_mode then return nil end
  return safe.wrap()
end

-- Convenience wrapper that chooses scheduling method; prevents accidental immediate calls.
-- mode: "schedule" | "defer" | "wrap"
function M.safe_notify(msg, level, opts, mode, delay_ms)
  local config = require("gopath.config").get()
  if not config.dev_mode then return nil end

  mode = mode or "schedule"
  if mode == "defer" then
    M.safe_notify_defer(msg, level, opts, delay_ms or 0)
  elseif mode == "wrap" then
    local wrapped = M.scheduled_notifier()
    if not wrapped then return nil end
    wrapped(msg, level, opts)
  else
    M.safe_notify_schedule(msg, level, opts)
  end
end

return M
