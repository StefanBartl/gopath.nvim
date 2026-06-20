---@module 'gopath.util.log'
---@brief Unified, dev_mode-gated logging for gopath.nvim.
---@description
--- Single source of truth for all user-facing notifications inside gopath.
--- Debug-level messages are silenced unless `config.dev_mode = true`.
--- All other callers should import this module instead of calling vim.notify
--- directly so that the prefix and level policy stay consistent.

local M = {}

local _cfg = nil

---@return boolean
local function dev_mode()
  local ok, cfg = pcall(function()
    if not _cfg then _cfg = require("gopath.config") end
    return _cfg.get()
  end)
  return ok and type(cfg) == "table" and cfg.dev_mode == true
end

---Emit a message only when dev_mode is active.
---@param msg string
function M.debug(msg)
  if dev_mode() then
    vim.notify("[gopath] " .. msg, vim.log.levels.DEBUG)
  end
end

---@param msg string
function M.info(msg)
  vim.notify("[gopath] " .. msg, vim.log.levels.INFO)
end

---@param msg string
function M.warn(msg)
  vim.notify("[gopath] " .. msg, vim.log.levels.WARN)
end

---@param msg string
function M.error(msg)
  vim.notify("[gopath] " .. msg, vim.log.levels.ERROR)
end

return M
