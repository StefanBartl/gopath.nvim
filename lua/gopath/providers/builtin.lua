---@module 'gopath.providers.builtin'
---@brief Tiny helpers around built-in motions/expands.

local M = {}

-- ---@return string|nil
-- function M.cfile()
--   local cfile = vim.fn.expand("<cfile>")
--   if type(cfile) == "string" and cfile ~= "" then
--     return cfile
--   end
--   return nil
-- end

---@return string|nil
function M.expand_cfile()
  -- Use smart token extraction
  local token_provider = require("gopath.providers.token")
  return token_provider.get_token()
end

return M
