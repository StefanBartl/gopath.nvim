---@module 'gopath.resolvers.lua.symbol_locator'
---@brief Locate functions/fields/tables with LSP precision and smart fallbacks.
---@description
--- `via_treesitter` tries a real Treesitter query first (`ts_find_symbol`:
--- function_declaration / assignment-with-function_definition / plain
--- assignment nodes), falling back to `legacy_find_symbol`'s line patterns
--- when no "lua" parser is available or none of the queries match.

local PATH = require("gopath.util.path")
local LOC = require("gopath.util.location")
local LSP = require("gopath.providers.lsp")
local AST = require("gopath.resolvers.lua.ts_lua_ast")

local M = {}

---LSP-first: Get precise definition for symbol under cursor.
---@param opts { timeout_ms?: integer }|nil
---@return table|nil  -- GopathResult
function M.via_lsp(opts)
  local timeout = (opts and opts.timeout_ms) or 200
  local defs = LSP.definition_at_cursor(timeout)

  if not defs or #defs == 0 then return nil end

  local d = defs[1]

  if not d.path then return nil end

  local base_result = {
    language = "lua",
    kind = "symbol",
    path = d.path,
    range = LOC.normalize_range(d.range),
    chain = nil,
    source = "lsp",
    confidence = 1.0,
  }

  -- If LSP points to a local require() binding, resolve to the actual module instead.
  local enhancer = require("gopath.resolvers.lua.local_to_module")
  local enhanced = enhancer.enhance_lsp_result(base_result)

  if enhanced then
    return enhanced -- Jump to module, not local variable
  end

  return base_result -- Standard LSP result
end

-- ========= legacy (line-pattern) fallback =========

---Legacy line-pattern symbol search, kept as the fallback path for files the
---treesitter strategy (`ts_find_symbol`) can't handle (no parser available,
---or none of its tiers matched).
---@internal
---@param lines string[]
---@param needle string
---@return integer|nil line 1-based
---@return integer|nil col 1-based
local function legacy_find_symbol(lines, needle)
  -- Note: the first pattern's `%f[%w_]` word-start frontier (before `needle`)
  -- was historically written as `%f[^%%w_]` — a stray double "%%" plus an
  -- inverted frontier direction that together made it never match anything
  -- with a dotted/colon prefix (e.g. "function M.setup(...)"). Fixed here;
  -- kept as a comment since it's easy to reintroduce by "simplifying" it back.
  --
  -- `needle` is normally a plain identifier (regex/chain extraction restricts
  -- it to [%w_]), but the treesitter chain path (gopath.resolvers.lua.chain)
  -- can also hand back a raw string-literal segment (e.g. from `t["a.b%c"]`
  -- bracket indexing), which may contain Lua-pattern-magic characters. Escape
  -- it so it is always matched literally — an unescaped needle can otherwise
  -- turn into a malformed pattern (e.g. trailing "%") and make `s:find(pat)`
  -- raise a hard error instead of just failing to match.
  needle = vim.pesc(needle)
  local patterns = {
    ("function%s+[%w_%.:]*%f[%w_]" .. needle .. "%f[^%w_]%s*%("),
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*=%s*function%s*%("),
    ("^%s*local%s+function%s+" .. needle .. "%s*%("),
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*="),
    ("%f[%w_]" .. needle .. "%s*="),
  }

  for i = 1, #lines do
    local s = lines[i]
    for _, pat in ipairs(patterns) do
      local c = s:find(pat)
      if c then return i, c end
    end
  end
  return nil, nil
end

-- ========= treesitter (primary) =========

---Any `function_declaration` (`function X.needle(...)`, `function
---X:needle(...)`, or `local function needle(...)`) whose name's last
---segment equals `needle`.
---@internal
---@param root TSNode
---@param src string
---@param needle string
---@return integer|nil line 1-based
---@return integer|nil col 1-based
local function ts_find_function_decl(root, src, needle)
  local q = AST.get_query("fn_decl", "(function_declaration name: (_) @name) @decl")
  if not q then return nil end
  for id, node in q:iter_captures(root, src) do
    if q.captures[id] == "name" then
      local chain = AST.chain_of(node, src)
      if chain and chain[#chain] == needle then return AST.node_start(node) end
    end
  end
  return nil
end

---`<chain>.needle = function(...)` — a dotted/bracketed assignment whose RHS
---is a function literal and whose LHS's last segment equals `needle`.
---@internal
---@param root TSNode
---@param src string
---@param needle string
---@return integer|nil line 1-based
---@return integer|nil col 1-based
local function ts_find_function_assignment(root, src, needle)
  local q = AST.get_query(
    "assign_fn",
    [[
      (assignment_statement
        (variable_list
          name: (_) @lhs)
        (expression_list
          value: (function_definition) @fn))
    ]]
  )
  if not q then return nil end

  local pending_lhs
  for id, node in q:iter_captures(root, src) do
    local cap = q.captures[id]
    if cap == "lhs" then
      pending_lhs = node
    elseif cap == "fn" and pending_lhs then
      local chain = AST.chain_of(pending_lhs, src)
      if chain and #chain >= 2 and chain[#chain] == needle then
        return AST.node_start(pending_lhs)
      end
      pending_lhs = nil
    end
  end
  return nil
end

---Any assignment (any RHS) whose LHS's last segment equals `needle` —
---covers both dotted (`M.needle = ...`) and bare (`needle = ...`) targets.
---@internal
---@param root TSNode
---@param src string
---@param needle string
---@return integer|nil line 1-based
---@return integer|nil col 1-based
local function ts_find_any_assignment(root, src, needle)
  local q = AST.get_query(
    "assign_any_lhs",
    [[
      (assignment_statement
        (variable_list
          name: (_) @lhs))
    ]]
  )
  if not q then return nil end
  for _, node in q:iter_captures(root, src) do
    local chain = AST.chain_of(node, src)
    if chain and chain[#chain] == needle then return AST.node_start(node) end
  end
  return nil
end

---Treesitter-based symbol search, mirroring `legacy_find_symbol`'s pattern
---priority with real syntax-tree queries. Returns nil (falling through to
---`legacy_find_symbol`) when no "lua" parser is available or nothing matches.
---@internal
---@param lines string[]
---@param needle string
---@return integer|nil line 1-based
---@return integer|nil col 1-based
local function ts_find_symbol(lines, needle)
  local root, src = AST.parse(lines)
  if not root or not src then return nil end

  local l, c = ts_find_function_decl(root, src, needle)
  if l then return l, c end

  l, c = ts_find_function_assignment(root, src, needle)
  if l then return l, c end

  return ts_find_any_assignment(root, src, needle)
end

-- ========= main entrypoint =========

---Treesitter fallback: Use chain + binding to find module, then locate symbol.
---@param chain { base:string, chain:string[] }
---@param bind table<string,string>
---@return table|nil
function M.via_treesitter(chain, bind)
  if not chain or not bind then return nil end

  local mod = bind[chain.base]
  if not mod then return nil end

  local abs = PATH.search_module(mod)

  if not abs then return nil end

  -- If no chain (just module reference), return module path
  if not chain.chain or #chain.chain == 0 then
    return {
      language = "lua",
      kind = "module",
      path = abs,
      range = nil,
      chain = nil,
      source = "treesitter",
      confidence = 0.7,
    }
  end

  -- Locate symbol in file
  local needle = chain.chain[#chain.chain]
  local lines = vim.fn.readfile(abs)

  local best_line, best_col = ts_find_symbol(lines, needle)
  if not best_line then
    best_line, best_col = legacy_find_symbol(lines, needle)
  end

  if not best_line then
    return {
      language = "lua",
      kind = "module",
      path = abs,
      range = nil,
      chain = chain.chain,
      source = "treesitter",
      confidence = 0.5,
    }
  end

  return {
    language = "lua",
    kind = "field",
    path = abs,
    range = LOC.create_range(best_line, best_col),
    chain = chain.chain,
    source = "treesitter",
    confidence = 0.75,
  }
end

return M
