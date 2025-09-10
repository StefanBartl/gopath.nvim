---@module 'gopath'
---@brief Public setup and API surface for gopath.nvim.

local C = require("gopath.config")
local R = require("gopath.resolve")

local M = {}

---@param opts GopathOptions|nil
function M.setup(opts)
  C.setup(opts)
end

--- Core resolve entry (data only).
---@param opts GopathResolveOpts|nil
---@return GopathResult|nil, string|nil
function M.resolve(opts)
  return R.resolve_at_cursor(opts)
end

M.commands = require("gopath.commands")

return M
