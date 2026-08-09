---@module 'gopath.resolvers.lua.ts_lua_ast'
---@brief Shared Treesitter helpers for locating tables/symbols in arbitrary
---Lua source text (not necessarily an open buffer). Used by `table_locator`
---and `symbol_locator` as their treesitter-first strategy, with each caller
---keeping its own line-pattern implementation as a fallback when a parser
---isn't available or no query matches.

local TS = require("gopath.providers.treesitter")

local M = {}

-- Compiled-query cache, keyed by an arbitrary name chosen by the caller.
-- `false` marks a query that failed to compile (e.g. no "lua" parser), so
-- repeated calls don't retry a doomed pcall.
local query_cache = {}

---Parse `lines` (as joined by "\n", matching their 1-based row/col positions)
---into a Lua syntax tree.
---@param lines string[]
---@return TSNode|nil root
---@return string|nil src  the exact joined text the tree was parsed from
function M.parse(lines)
  local src = table.concat(lines, "\n")
  local root = TS.parse_string(src, "lua")
  if not root then return nil, nil end
  return root, src
end

---Get (and cache) a compiled Lua query.
---@internal
---@param name string  cache key
---@param query_str string
---@return TSQuery|nil
function M.get_query(name, query_str)
  local cached = query_cache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local ok, q = pcall(vim.treesitter.query.parse, "lua", query_str)
  query_cache[name] = ok and q or false
  return ok and q or nil
end

---Text spanned by `node` in `src`, or nil on failure.
---@param node TSNode
---@param src string
---@return string|nil
function M.node_text(node, src)
  local ok, txt = pcall(vim.treesitter.get_node_text, node, src)
  return ok and txt or nil
end

---Literal text of a `string` node's content (without quotes).
---@internal
---@param str_node TSNode  type() == "string"
---@param src string
---@return string
function M.string_key_text(str_node, src)
  local content = str_node:field("content")[1]
  if content then return M.node_text(content, src) or "" end
  local raw = M.node_text(str_node, src) or ""
  return raw:sub(2, -2)
end

---Build the dotted segment chain for an lvalue node (`identifier`,
---`dot_index_expression`, or `bracket_index_expression` with a string key).
---Returns nil when the chain contains a dynamic (non-literal) segment, e.g.
---`t[expr]`, since that can't be matched against a textual chain.
---@param node TSNode
---@param src string
---@return string[]|nil
function M.chain_of(node, src)
  local t = node:type()
  if t == "identifier" then
    local txt = M.node_text(node, src)
    return txt and { txt } or nil
  elseif t == "dot_index_expression" then
    local base = node:field("table")[1]
    local field = node:field("field")[1]
    if not base or not field then return nil end
    local chain = M.chain_of(base, src)
    if not chain then return nil end
    local ftxt = M.node_text(field, src)
    if not ftxt then return nil end
    chain[#chain + 1] = ftxt
    return chain
  elseif t == "bracket_index_expression" or t == "method_index_expression" then
    local base = node:field("table")[1]
    local key = node:field("field")[1]
    if not base or not key then return nil end
    if t == "bracket_index_expression" then
      if key:type() ~= "string" then return nil end
      local chain = M.chain_of(base, src)
      if not chain then return nil end
      chain[#chain + 1] = M.string_key_text(key, src)
      return chain
    end
    -- method_index_expression: `obj:method` — treat like a dotted segment.
    local chain = M.chain_of(base, src)
    if not chain then return nil end
    local ftxt = M.node_text(key, src)
    if not ftxt then return nil end
    chain[#chain + 1] = ftxt
    return chain
  end
  return nil
end

---@param a string[]
---@param b string[]
---@return boolean
function M.chains_equal(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

---Whether `chain[from..]` equals `other`.
---@param chain string[]
---@param from integer
---@param other string[]
---@return boolean
function M.chain_tail_equal(chain, from, other)
  if (#chain - from + 1) ~= #other then return false end
  for i = 1, #other do
    if chain[from + i - 1] ~= other[i] then return false end
  end
  return true
end

---@param t string[]
---@param from integer
---@return string[]
function M.slice(t, from)
  local out = {}
  for i = from, #t do
    out[#out + 1] = t[i]
  end
  return out
end

---Literal key text of a table_constructor `field` node (`name = ...`,
---`["name"] = ...`, `['name'] = ...`), or nil for a dynamic bracket key
---(`[expr] = ...`) or an array-style entry with no key at all.
---@param field_node TSNode  type() == "field"
---@param src string
---@return string|nil
function M.field_key_text(field_node, src)
  local name = field_node:field("name")[1]
  if not name then return nil end
  if name:type() == "string" then return M.string_key_text(name, src) end
  if name:type() == "identifier" then
    -- `[key] = v` with a bare identifier `key` is a *dynamic* lookup, not a
    -- literal key named "key" — distinguish it from bare `key = v` by
    -- checking whether the field opens with a literal "[" token.
    local first = field_node:child(0)
    if first and first:type() == "[" then return nil end
    return M.node_text(name, src)
  end
  return nil
end

---1-based (start_line, end_line) spanned by `node`.
---@param node TSNode
---@return integer start_line
---@return integer end_line
function M.node_lines(node)
  local sr, _, er = node:range()
  return sr + 1, er + 1
end

---1-based (line, col) of `node`'s start.
---@param node TSNode
---@return integer line
---@return integer col
function M.node_start(node)
  local sr, sc = node:range()
  return sr + 1, sc + 1
end

return M
