---@module 'gopath.open'
---@brief Unified opener for resolved locations.
---@description
--- Replaces the previous per-mode openers (edit/window/vsplit/tab). A single
--- `M.open(res, mode)` handles external files, existence checks, window/tab
--- placement and the optional line/col jump. Help results are handled by
--- `gopath.open.help` and routed separately by `gopath.commands`.

local LOC = require("gopath.util.location")
local LOG = require("gopath.util.log")
local CROSS = require("gopath.util.cross")

local M = {}

---@alias GopathOpenMode "edit"|"window"|"vsplit"|"tab"

---Create the target window/tab before editing the file.
---Each function is a no-op or issues one window-management command only.
---@type table<GopathOpenMode, fun()>
local PLACEMENT = {
  edit = function() end,
  window = function()
    vim.cmd.split()
  end,
  vsplit = function()
    vim.cmd.vsplit()
  end,
  tab = function()
    vim.cmd.tabnew()
  end,
}

---@private
---@param range GopathRange|nil
local function jump_to_range(range)
  if not range then return end
  local normalized = LOC.normalize_range(range)
  if not normalized then return end
  local l = normalized.line
  local c = math.max(0, normalized.col - 1)
  pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  vim.cmd("normal! zz")
end

---Open a resolved location in the specified window mode.
---@param res  GopathResult
---@param mode GopathOpenMode|nil  defaults to "edit"
function M.open(res, mode)
  if not (res and res.path) then return end

  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  if res.exists == false then
    local CREATE = require("gopath.create")
    CREATE.offer(res, function(created_res)
      M.open(created_res, mode)
    end)
    return
  end

  local place = PLACEMENT[mode or "edit"] or PLACEMENT.edit
  place()

  -- Hand the OS / editor an OS-native path (backslashes on Windows) via lib.nvim.
  local target = CROSS.to_native(res.path)
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(target))
  if not ok then
    LOG.error("Could not open file: " .. tostring(err))
    return
  end

  jump_to_range(res.range)
end

return M
