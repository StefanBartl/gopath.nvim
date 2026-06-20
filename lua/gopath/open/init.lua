---@module 'gopath.open'
---@brief Unified opener for resolved locations.
---@description
--- Replaces the previous per-mode openers (edit/window/vsplit/tab). A single
--- `M.open(res, mode)` handles external files, existence checks, window/tab
--- placement and the optional line/col jump. Help results are handled by
--- `gopath.open.help` and routed separately by `gopath.commands`.

local LOC = require("gopath.util.location")

local M = {}

---@alias GopathOpenMode "edit"|"window"|"vsplit"|"tab"

---Place the cursor in the freshly opened buffer according to a target window.
---Each entry returns nothing; it only runs the window/tab command. The actual
---`:edit` of the file happens afterwards so it is shared across all modes.
---@type table<GopathOpenMode, fun()>
local PLACEMENT = {
  edit = function() end,
  window = function() vim.cmd.split() end,
  vsplit = function() vim.cmd.vsplit() end,
  tab = function() vim.cmd.tabnew() end,
}

---Jump to the result's range (if any), normalized to 1-based line / 0-based col.
---@param range table|nil
---@return nil
local function jump_to_range(range)
  if not range then
    return
  end

  local normalized = LOC.normalize_range(range)
  if not normalized then
    return
  end

  local l = normalized.line
  local c = math.max(0, normalized.col - 1)
  pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  vim.cmd("normal! zz")
end

---Open a resolved location.
---@param res GopathResult Resolution result (needs at least `path`)
---@param mode GopathOpenMode|nil Placement mode (default "edit")
---@return nil
function M.open(res, mode)
  if not (res and res.path) then
    return
  end

  -- External files (images, PDFs, URLs, ...) bypass window handling entirely.
  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  -- Refuse to open a non-existent path (user-facing error is intentional).
  if res.exists == false then
    vim.notify(
      string.format("[gopath] File not found: %s", res.path),
      vim.log.levels.ERROR
    )
    return
  end

  -- 1) Create the target window/tab (no-op for "edit").
  local place = PLACEMENT[mode or "edit"] or PLACEMENT.edit
  place()

  -- 2) Edit the file in that window (shared across all modes).
  vim.cmd.edit(vim.fn.fnameescape(res.path))

  -- 3) Optional cursor jump.
  jump_to_range(res.range)
end

return M
