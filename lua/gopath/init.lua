---@module 'gopath'
---@brief Public setup and API surface for gopath.nvim.

local C = require("gopath.config")
local R = require("gopath.resolve")

local M = {}

---Setup gopath with user options and register keymaps/commands
---@param opts GopathOptions|nil
function M.setup(opts)
  -- Setup configuration
  C.setup(opts)

  local config = C.get()

  -- Register keymaps if enabled
  require("gopath.keymaps").setup(config)

  -- Register user commands if enabled
  require("gopath.usercommands").setup(config)
end

--- Core resolve entry (data only).
---@param opts GopathResolveOpts|nil
---@return GopathResult|nil, string|nil
function M.resolve(opts)
  return R.resolve_at_cursor(opts)
end

-- Expose commands API for manual usage
M.commands = require("gopath.commands")

return M
