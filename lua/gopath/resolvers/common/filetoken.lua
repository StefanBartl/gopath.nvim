---@module 'gopath.resolvers.common.filetoken'
---@brief Resolve <cfile> against &path, &suffixesadd, includeexpr-like transforms.

local P = require("gopath.providers.builtin")
local U = require("gopath.util.path")

local M = {}

---@return GopathResult|nil
function M.resolve()
  local cfile = P.expand_cfile()
  if not cfile then return nil end
  local abs = U.search_with_vim_path(cfile)  -- implement: &path + suffixesadd
  if not abs then return nil end
  return {
    language = vim.bo.filetype or "text",
    kind = "module",
    path = abs,
    range = nil,
    chain = nil,
    source = "builtin",
    confidence = 0.6,
  }
end

return M

