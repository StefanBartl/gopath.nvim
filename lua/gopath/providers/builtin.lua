---@module 'gopath.providers.builtin'
---@brief Tiny helpers around built-in motions/expands.

local M = {}

---@return string|nil
function M.expand_cfile()
  local cfile = vim.fn.expand("<cfile>")
  if type(cfile) == "string" and cfile ~= "" then
    return cfile
  end
  return nil
end

return M
