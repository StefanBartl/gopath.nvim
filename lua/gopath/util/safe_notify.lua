---@module 'util.safe_notify'
--- Small utilities to safely call vim.notify from fast event contexts.
--- Provides helpers using vim.schedule, vim.defer_fn and vim.schedule_wrap.

local M = {}

-- Safe notify using vim.schedule: schedules the notify on the main loop immediately.
-- Usage: M.safe_notify_schedule("message", vim.log.levels.INFO, { timeout = 3000 })
-- English comments in code as requested.
function M.safe_notify_schedule(msg, level, opts)
    local config = require("gopath.config").get()
    if not config.dev_mode then return nil end
    -- schedule a function that calls vim.notify (do not call vim.notify here)
    vim.schedule(function()
        vim.notify(msg, level, opts)
    end)
end

-- Safe notify using vim.defer_fn: defers execution by `delay_ms`.
-- Usage: M.safe_notify_defer("message", vim.log.levels.INFO, { timeout = 3000 }, 50)
function M.safe_notify_defer(msg, level, opts, delay_ms)
    local config = require("gopath.config").get()
    if not config.dev_mode then return nil end
    -- ensure delay_ms is a number (fallback to 0)
    local dt = tonumber(delay_ms) or 0
    -- pass a function as first argument, not the result of vim.notify(...)
    vim.defer_fn(function()
        vim.notify(msg, level, opts)
    end, dt)
end

-- Safe notify using schedule_wrap: returns a function that is already scheduled.
-- This is convenient for repeated calls from fast contexts.
-- Usage:
--   local notify = require('utils.safe_notify').scheduled_notifier()
--   notify("hello", vim.log.levels.INFO)
function M.scheduled_notifier()
    local config = require("gopath.config").get()
    if not config.dev_mode then return nil end
    -- schedule_wrap returns a function that queues its body on the main loop.
    return vim.schedule_wrap(function(msg, level, opts)
        vim.notify(msg, level, opts)
    end)
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
        -- use schedule_wrap for minimal overhead when notifying repeatedly
        local wrapped = M.scheduled_notifier()
        if not wrapped then return nil end
        wrapped(msg, level, opts)
    else
        M.safe_notify_schedule(msg, level, opts)
    end
end

return M
