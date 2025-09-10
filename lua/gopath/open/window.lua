---@module 'gopath.open.window'
---@brief Open a resolved location in a new split window (horizontal by default).

local M = {}

---@param res GopathResult
---@param opts { vsplit?: boolean }|nil
function M.open(res, opts)
  if not (res and res.path) then return end
  local vs = opts and opts.vsplit or false
  if vs then
    vim.cmd.vsplit()
  else
    vim.cmd.split()
  end
  vim.cmd.edit(vim.fn.fnameescape(res.path))
  if res.range then
    local l = math.max(res.range.line, 1)
    local c = math.max((res.range.col or 1) - 1, 0)
    pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
  end
end

return M
