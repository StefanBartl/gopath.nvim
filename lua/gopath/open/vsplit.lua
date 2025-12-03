---@module 'gopath.open.vsplit'
--- Open a resolved location in a vertical split window.

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then
    return
  end

  -- Check if file should be opened externally
  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  -- Check if file exists
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
    local l = math.max(res.range.line, 1)
    local c = math.max((res.range.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  end
end

return M
