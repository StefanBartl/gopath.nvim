---@module 'gopath.keymaps'
--- Automatic keymap registration based on config.

local M = {}

---Setup default keymaps if not disabled in config
---@param config GopathOptions
function M.setup(config)
  if config.mappings == false then
    return -- User disabled all mappings
  end

  local maps = config.mappings or {}
  local commands = require("gopath.commands")

  -- Helper to set keymap if not disabled
  local function map(mode, lhs, rhs, desc)
    if lhs and lhs ~= false and lhs ~= "" then
      vim.keymap.set(mode, lhs, rhs, {
        noremap = true,
        silent = true,
        desc = "gopath: " .. desc,
      })
    end
  end

  -- Open here (current window)
  map("n", maps.open_here, function()
    commands.resolve_and_open("edit")
  end, "open here")

  -- Open in horizontal split
  map("n", maps.open_split, function()
    commands.resolve_and_open("window")
  end, "open in split")

  -- Open in vertical split
  map("n", maps.open_vsplit, function()
    commands.resolve_and_open("vsplit")
  end, "open in vsplit")

  -- Open in new tab
  map("n", maps.open_tab, function()
    commands.resolve_and_open("tab")
  end, "open in tab")

  -- Copy location (path:line:col)
  map("n", maps.copy_location, function()
    commands.resolve_and_copy()
  end, "copy path:line:col")

  -- Debug under cursor
  map("n", maps.debug, function()
    commands.debug_under_cursor()
  end, "debug under cursor")
end

return M
