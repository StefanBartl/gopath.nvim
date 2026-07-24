---@module 'gopath.bindings.keymaps'
--- Automatic keymap registration based on config.
--- Supports single lhs (string) or multiple lhs (string[]).

local map = require("lib.nvim.map")

local M = {}

--- Normalize lhs into a list of strings.
--- Returns nil if mapping is disabled.
---@param lhs string|string[]|false|nil
---@return string[]|nil
local function normalize_lhs(lhs)
  if lhs == false or lhs == nil or lhs == "" then return nil end

  if type(lhs) == "string" then
    ---@type string[]
    return { lhs }
  end

  if type(lhs) == "table" then
    ---@type string[]
    return lhs
  end

  return nil
end

--- Set one or multiple keymaps safely.
---@param mode string|string[]
---@param lhs string|string[]|false|nil
---@param rhs function|string
---@param desc string
---@return nil
local function map_many(mode, lhs, rhs, desc)
  local lhs_list = normalize_lhs(lhs)
  if not lhs_list then return end

  for _, key in ipairs(lhs_list) do
    map(mode, key, rhs, {}, "gopath: " .. desc)
  end
end

--- Setup default keymaps if not disabled in config.
---@param config GopathOptions
---@return nil
function M.setup(config)
  if config.mappings == false then return end

  local maps = config.mappings or {}
  local commands = require("gopath.commands")

  -- Open here (current window)
  map_many("n", maps.open_here, function()
    commands.resolve_and_open("edit")
  end, "open here")

  -- Open in horizontal split
  map_many("n", maps.open_split, function()
    commands.resolve_and_open("window")
  end, "open in split")

  -- Open in vertical split
  map_many("n", maps.open_vsplit, function()
    commands.resolve_and_open("vsplit")
  end, "open in vsplit")

  -- Open in new tab
  map_many("n", maps.open_tab, function()
    commands.resolve_and_open("tab")
  end, "open in tab")

  -- Copy location
  map_many("n", maps.copy_location, function()
    commands.resolve_and_copy()
  end, "copy path:line:col")

  -- Debug
  map_many("n", maps.debug, function()
    commands.debug_under_cursor()
  end, "debug under cursor")

  -- Check: report existence of path under cursor; offer to create if missing
  map_many("n", maps.check, function()
    commands.check_under_cursor()
  end, "check path exists / offer create")

  -- Probe: suffix-based search in normal and visual mode
  if maps.probe then
    local lhs_list = normalize_lhs(maps.probe)
    if lhs_list then
      for _, key in ipairs(lhs_list) do
        -- Normal mode: probe <cfile> / token under cursor
        map("n", key, function()
          commands.probe_selection({ open_cmd = "vsplit", ask = true })
        end, {}, "gopath: probe path under cursor (vsplit)")

        -- Visual mode: probe selection
        map("v", key, function()
          -- Exit visual mode first so marks '< '> are set
          vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "x",
            false
          )
          vim.schedule(function()
            commands.probe_selection({ open_cmd = "vsplit", ask = true })
          end)
        end, {}, "gopath: probe selected path (vsplit)")
      end
    end
  end
end

return M
