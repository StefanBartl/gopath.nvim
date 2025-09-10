---@module 'gopath.tab'
---@brief Open a resolved location in a new tabpage.

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then return end
  vim.cmd.tabedit(vim.fn.fnameescape(res.path))
  if res.range then
    local l = math.max(res.range.line, 1)
    local c = math.max((res.range.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  end
end

return M

