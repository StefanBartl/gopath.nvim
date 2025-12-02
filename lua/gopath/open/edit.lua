---@module 'gopath.open.edit'
---@brief Open a resolved location in current window, with external file support.

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then
    return
  end

  -- Check if file should be opened externally FIRST
  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  -- Check if file exists
  if res.exists == false then
    -- File doesn't exist and wasn't caught by alternate resolution
    vim.notify(
      string.format("[gopath] File not found: %s", res.path),
      vim.log.levels.ERROR
    )
    return
  end

  -- Open file in current window
  vim.cmd.edit(vim.fn.fnameescape(res.path))

  -- Jump to position if provided
  if res.range then
    local l = math.max(res.range.line, 1)
    local c = math.max((res.range.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  end
end

return M
