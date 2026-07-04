---@module 'gopath.bindings'
---@brief Orchestrates gopath's keymaps, user commands, autocommands, and the
--- optional which-key label.

local M = {}

---@param config GopathOptions
function M.setup(config)
  require("gopath.bindings.keymaps").setup(config)
  require("gopath.bindings.usrcmds").setup(config)
  require("gopath.bindings.autocmds").setup(config)

  if config.which_key ~= false then
    require("gopath.bindings.which_key").setup(config)
  end
end

return M
