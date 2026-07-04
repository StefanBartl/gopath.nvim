---@module 'gopath.util.log'
---@brief Unified, dev_mode-gated logging for gopath.nvim.
---@description
--- Single source of truth for all user-facing notifications inside gopath.
--- Debug-level messages are silenced unless `config.dev_mode = true`.
--- All other callers should import this module instead of calling vim.notify
--- directly so that the prefix and level policy stay consistent.
---
--- lib.nvim is a soft dependency: when its notifier is installed, info/warn/
--- error/debug delegate to it (consistent notification styling across the
--- author's plugins); otherwise this falls back to plain vim.notify.

local M = {}

local PREFIX = "[gopath]"

local _cfg = nil

---@return boolean
local function dev_mode()
  local ok, cfg = pcall(function()
    if not _cfg then _cfg = require("gopath.config") end
    return _cfg.get()
  end)
  return ok and type(cfg) == "table" and cfg.dev_mode == true
end

---@type table|nil
local lib_notify
do
  local ok, mod = pcall(require, "lib.nvim.notify")
  if ok and type(mod) == "table" and type(mod.create) == "function" then
    local create_ok, notifier = pcall(mod.create, PREFIX)
    if create_ok and type(notifier) == "table" then
      lib_notify = notifier
    end
  end
end

---Whether lib.nvim's notifier is in use (for :checkhealth reporting).
---@return boolean
function M.using_lib()
  return lib_notify ~= nil
end

---Emit a message only when dev_mode is active.
---@param msg string
function M.debug(msg)
  if not dev_mode() then return end
  if lib_notify then
    lib_notify.debug(msg)
  else
    vim.notify(PREFIX .. " " .. msg, vim.log.levels.DEBUG)
  end
end

---@param msg string
function M.info(msg)
  if lib_notify then
    lib_notify.info(msg)
  else
    vim.notify(PREFIX .. " " .. msg, vim.log.levels.INFO)
  end
end

---@param msg string
function M.warn(msg)
  if lib_notify then
    lib_notify.warn(msg)
  else
    vim.notify(PREFIX .. " " .. msg, vim.log.levels.WARN)
  end
end

---@param msg string
function M.error(msg)
  if lib_notify then
    lib_notify.error(msg)
  else
    vim.notify(PREFIX .. " " .. msg, vim.log.levels.ERROR)
  end
end

return M
