---@module 'gopath.resolvers.lua.require_path'
---@brief Resolve require("x.y") under/near cursor into a module file path.

local PATH = require("gopath.util.path")
local LOC = require("gopath.util.location")

local M = {}

local function cursor_in(span_s, span_e, col)
  return span_s and span_e and col >= span_s and col <= span_e
end

---Find a require call on current or adjacent lines that intersects the cursor.
---@return string|nil module_name "a.b/c"
---@return integer|nil line Optional line number from comment
---@return integer|nil col Optional column number from comment
local function find_require_module_at_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  col = col -- 1-based

  local lines = {
    { row, vim.api.nvim_get_current_line() },
  }

  -- Also consider previous line if cursor on chained call
  if row > 1 then
    lines[#lines + 1] = {
      row - 1,
      vim.api.nvim_buf_get_lines(0, row - 2, row - 1, false)[1] or "",
    }
  end

  for _, item in ipairs(lines) do
    local _, ln = item[1], item[2]

    -- require "x", require('x'), require [[x]]
    local s1, e1, m1 = ln:find("require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
    if s1 and cursor_in(s1, e1, (_ == 1 and col) or 1e9) then
      return m1, nil, nil
    end

    local s2, e2, m2 = ln:find("require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
    if s2 and cursor_in(s2, e2, (_ == 1 and col) or 1e9) then
      return m2, nil, nil
    end
  end

  return nil, nil, nil
end

---@return table|nil  -- GopathResult
function M.resolve()
  local mod, hint_line, hint_col = find_require_module_at_cursor()

  if not mod then
    return nil
  end

  -- Convert "a.b/c" -> "a/b/c"
  local rel = mod:gsub("%.", "/")

  -- Candidates inside runtimepath
  local candidates = {
    rel .. ".lua",
    rel .. "/init.lua",
  }

  local abs = PATH.search_in_rtp(candidates)

  if not abs then
    abs = PATH.search_with_package_path(mod)
  end

  if not abs then
    return nil
  end

  return {
    language   = "lua",
    kind       = "module",
    path       = abs,
    range      = LOC.create_range(hint_line, hint_col),
    chain      = nil,
    source     = "builtin",
    confidence = 0.85,
  }
end

return M
