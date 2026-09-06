---@module 'gopath.providers.builtin'
---@brief Tiny helpers around built-in motions/expands.

local M = {}

---@return string|nil
function M.expand_cfile()
  local token_provider = require("gopath.providers.token")
  return token_provider.get_token()
end

return M
