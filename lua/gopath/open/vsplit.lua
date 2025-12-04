---@module 'gopath.open.vsplit'
---@brief Open a resolved location in a vertical split window.

local LOC = require("gopath.util.location")

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then
    return
  end

  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  if res.exists == false then
    vim.notify(
      string.format("[gopath] File not found: %s", res.path),
      vim.log.levels.ERROR
    )
    return
  end

  vim.cmd.vsplit()
  vim.cmd.edit(vim.fn.fnameescape(res.path))

  if res.range then
    local normalized = LOC.normalize_range(res.range)
    if normalized then
      local l = normalized.line
      local c = normalized.col - 1
      pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
      vim.cmd("normal! zz")
    end
  end
end

return M
