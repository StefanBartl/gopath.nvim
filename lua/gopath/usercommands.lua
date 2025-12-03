---@module 'gopath.usercommands'
--- Automatic user command registration based on config.

local M = {}

---Setup user commands if not disabled in config
---@param config GopathOptions
function M.setup(config)
  if config.commands == false then
    return -- User disabled all commands
  end

  local cmds = config.commands or {}
  local commands = require("gopath.commands")

  -- :GopathResolve - Show resolution result
  if cmds.resolve ~= false then
    vim.api.nvim_create_user_command("GopathResolve", function()
      commands.debug_under_cursor()
    end, {
      desc = "Gopath: Show resolution result for symbol under cursor",
    })
  end

  -- :GopathOpen [mode] - Open with specified mode
  if cmds.open ~= false then
    vim.api.nvim_create_user_command("GopathOpen", function(opts)
      local mode = opts.args and opts.args ~= "" and opts.args or "edit"

      -- Normalize mode aliases
      if mode == "window_vsplit" or mode == "vsplit" then
        mode = "vsplit"
      elseif mode == "window" or mode == "split" then
        mode = "window"
      end

      commands.resolve_and_open(mode)
    end, {
      nargs = "?",
      complete = function()
        return { "edit", "window", "vsplit", "tab" }
      end,
      desc = "Gopath: Open target (edit|window|vsplit|tab)",
    })
  end

  -- :GopathCopy - Copy location to clipboard
  if cmds.copy ~= false then
    vim.api.nvim_create_user_command("GopathCopy", function()
      commands.resolve_and_copy()
    end, {
      desc = "Gopath: Copy path:line:col to clipboard",
    })
  end

  -- :GopathDebug - Debug resolution under cursor
  if cmds.debug ~= false then
    vim.api.nvim_create_user_command("GopathDebug", function()
      commands.debug_under_cursor()
    end, {
      desc = "Gopath: Debug resolution under cursor",
    })
  end
end

return M
