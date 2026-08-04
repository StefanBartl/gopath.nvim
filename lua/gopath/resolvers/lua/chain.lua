---@module 'gopath.resolvers.lua.chain'
---@brief Extract base identifier and member chain at cursor, including ':' methods.

local TS = require("gopath.providers.treesitter")

local M = {}

---@class LuaChain
---@field base string
---@field chain string[]

---Split a dotted/colon token ("M.cfg:foo") into a base identifier and the
---remaining chain segments. Returns nil when there are fewer than 2 segments.
---@internal
---@param tok string
---@return LuaChain|nil
local function split_chain(tok)
  local parts = {}
  for p in tok:gmatch("[^%.:]+") do
    parts[#parts + 1] = p
  end
  if #parts < 2 then return nil end
  local base = parts[1]
  table.remove(parts, 1)
  return { base = base, chain = parts }
end

---Regex-based fallback: extract the dotted/colon chain touching the cursor
---from the raw line text, without treesitter.
---@internal
---@return LuaChain|nil
local function regex_chain_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local left = line:sub(1, col):match("([%w_%.:]+)%s*$")
  local right = line:sub(col + 1):match("^([%w_%.:]+)")
  local tok = (left or "") .. (right or "")
  if tok == "" or not tok:find("[%.:]") then return nil end
  return split_chain(tok)
end

---Treesitter-based chain extraction: climb up through field/index/method
---nodes from the node under the cursor to build the dotted chain.
---@internal
---@return LuaChain|nil
local function ts_chain_at_cursor()
  local node = TS.node_at_cursor() ---@type TSNode|nil
  if not node then return nil end

  -- Best-effort: climb up through field/index/method nodes to form a chain string.
  local leaf = node ---@type TSNode
  local pieces = {}

  ---Return the source text spanned by `n`, or nil for a nil node.
  ---@internal
  ---@param n TSNode|nil
  ---@return string|nil
  local function text_of(n)
    if not n then return nil end
    local sr, sc, _, ec = n:range()
    local line = vim.api.nvim_buf_get_lines(0, sr, sr + 1, false)[1] or ""
    return line:sub(sc + 1, ec)
  end

  -- Walk up while parent looks like a field/index/method expression.
  local cur = leaf ---@type TSNode
  while cur do
    local t = cur:type()
    if t == "identifier" or t == "property_identifier" or t == "string" then
      local txt = text_of(cur) or ""
      txt = txt:gsub("^[\"']", ""):gsub("[\"']$", "")
      pieces[#pieces + 1] = txt
    end
    local p = cur:parent() ---@type TSNode|nil
    if not p then break end
    local pt = p:type()
    if
      pt == "field_expression"
      or pt == "index_expression"
      or pt == "method_index_expression"
      or pt == "method"
    then
      cur = p
    else
      break
    end
  end

  if #pieces == 0 then return nil end

  local rev = {}
  for i = #pieces, 1, -1 do
    rev[#rev + 1] = pieces[i]
  end
  local tok = table.concat(rev, ".")
  return split_chain(tok)
end

---@return LuaChain|nil
function M.get_chain_at_cursor()
  -- Prefer TS (more semantic), otherwise fall back to regex.
  return ts_chain_at_cursor() or regex_chain_at_cursor()
end

return M
