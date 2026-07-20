---@module 'gopath.resolvers.lua.require_path'
---@brief Resolve require("x.y") under/near cursor into a module file path.
---@description
--- Two detection modes:
---   1. `require("a.b.c")` — finds the call expression that intersects the cursor
---      (also checks the previous line for multi-line expressions).
---   2. Bare dotted name at cursor — catches `@module 'a.b.c'`, `@see a.b.c`
---      and error-message fragments like `module 'x.y' not found`.
--- Resolution is then delegated to `PATH.search_module`, which checks rtp,
--- package.path and finally the install dirs of installed-but-unloaded plugins.

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

---Resolve a dotted Lua module string into a file path.
---Shared by `require("a.b.c")` and bare/annotation dotted names ("a.b.c").
---@param mod string Dotted module name (e.g. "custom.markdown.hl_options")
---@return string|nil abs Absolute file path, or nil if not found
local function module_to_path(mod)
  return PATH.search_module(mod)
end

---Extract a dotted module name under the cursor, independent of `require(...)`.
---This gives gf-parity for `@module 'a.b.c'`, `@see a.b.c` and bare dotted
---module names that appear in error messages ("module 'x.y' not found").
---@return string|nil mod Dotted module name, or nil
local function find_dotted_module_at_cursor()
  local ok, token = pcall(function()
    return require("gopath.providers.token").get_token()
  end)
  if not ok or type(token) ~= "string" or token == "" then
    return nil
  end

  -- Strip surrounding quotes left by annotations/strings.
  token = token:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

  -- Must look like a dotted module: word segments joined by dots, no path
  -- separators, at least two segments. Reject anything with slashes.
  if token:match("[/\\]") then
    return nil
  end
  if not token:match("^[%w_]+%.[%w_%.]+$") then
    return nil
  end

  return token
end

---@return table|nil  -- GopathResult
function M.resolve()
  local mod, hint_line, hint_col = find_require_module_at_cursor()

  -- Fallback: dotted module under cursor without a require(...) wrapper.
  if not mod then
    mod = find_dotted_module_at_cursor()
  end

  if not mod then
    return nil
  end

  local abs = module_to_path(mod)

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
    exists     = true,
  }
end

return M
