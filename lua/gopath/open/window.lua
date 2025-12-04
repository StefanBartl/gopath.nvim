---@module 'gopath.open.window'
---@brief Open a resolved location in a new split window, with external file support.

local LOC = require("gopath.util.location")

local M = {}

---@param res GopathResult
---@param opts { vsplit?: boolean }|nil
function M.open(res, opts)
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

  local vs = opts and opts.vsplit or false
  if vs then
    vim.cmd.vsplit()
  else
    vim.cmd.split()
  end

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
