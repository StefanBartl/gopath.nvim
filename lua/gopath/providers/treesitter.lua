---@module 'gopath.providers.treesitter'
---@brief Small helpers around Tree-sitter to get nodes/captures at cursor.

local M = {}

local function has_ts()
  return pcall(require, "vim.treesitter")
end

---@return userdata|nil
function M.node_at_cursor()
  if not has_ts() then return nil end
  local ts = require("vim.treesitter")
  local ok, parser = pcall(ts.get_parser, 0)
  if not ok or not parser then return nil end
  local tree = parser:parse()[1]
  if not tree then return nil end
  local root = tree:root()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  return root and root:named_descendant_for_range(row, col, row, col) or nil
end

--- Return capture names at position (best-effort; works on 0.10+ and falls back for 0.9).
---@param row integer  -- 0-based
---@param col integer  -- 0-based
---@return string[]
function M.captures_at_pos(row, col)
  if not has_ts() then return {} end

  -- Neovim 0.10+
  local ok_core, core = pcall(function() return vim.treesitter.get_captures_at_pos(0, row, col) end)
  if ok_core and type(core) == "table" then
    return core
  end

  -- Fallback: nvim-treesitter helper (0.9)
  local ok_ts, tsu = pcall(require, "nvim-treesitter.ts_utils")
  if ok_ts and tsu and type(tsu.get_captures_at_pos) == "function" then
    local list = tsu.get_captures_at_pos(0, row, col)
    if type(list) == "table" then return list end
  end

  return {}
end

return M
