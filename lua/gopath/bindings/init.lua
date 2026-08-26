---@module 'gopath.bindings'
---@brief Orchestrates gopath's keymaps, user commands and autocommands.
---
--- The which-key group label is no longer wired here: it is one field in the
--- keymap spec, applied by lib.nvim's keymap registry. Per-key labels never
--- needed registering at all -- which-key reads the mappings' own `desc`.

local M = {}

---@param config GopathOptions
function M.setup(config)
  require("gopath.bindings.keymaps").setup(config)
  require("gopath.bindings.usrcmds").setup(config)
  require("gopath.bindings.autocmds").setup(config)
end

return M
