---@module 'gopath.open.edit'
---@brief Open a resolved location in current window.

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then return end
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

