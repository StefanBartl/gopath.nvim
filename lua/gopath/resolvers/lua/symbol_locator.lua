---@module 'gopath.resolvers.lua.symbol_locator'
---@brief Locate functions/fields/tables/primitives inside a module file with LSP precision.

local PATH = require("gopath.util.path")
local LOC = require("gopath.util.location")
local LSP  = require("gopath.providers.lsp")

local M = {}

---LSP-first: Get precise definition for symbol under cursor.
---This is the HIGHEST PRECISION resolver - use whenever LSP is available.
---@param opts { timeout_ms?: integer }|nil
---@return table|nil  -- GopathResult
function M.via_lsp(opts)
  local timeout = (opts and opts.timeout_ms) or 200
  local defs = LSP.definition_at_cursor(timeout)

  if not defs or #defs == 0 then
    return nil
  end

  -- Use first definition (usually the most relevant)
  local d = defs[1]

  -- Validate definition has required fields
  if not d.path then
    return nil
  end

  return {
    language   = "lua",
    kind       = "symbol",  -- Generic symbol (could be function, field, etc.)
    path       = d.path,
    range      = LOC.normalize_range(d.range),
    chain      = nil,
    source     = "lsp",
    confidence = 1.0,  -- LSP provides exact locations
  }
end

---Treesitter fallback: Use chain + binding to find module, then locate symbol.
---Less precise than LSP but works without language server.
---@param chain { base:string, chain:string[] }
---@param bind table<string,string>
---@return table|nil
function M.via_treesitter(chain, bind)
  -- Validate inputs
  if not chain or not bind then
    return nil
  end

  -- Resolve base identifier to module
  local mod = bind[chain.base]
  if not mod then
    return nil
  end

  -- Find module file
  local rel = mod:gsub("%.", "/")
  local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" })
           or PATH.search_with_package_path(mod)

  if not abs then
    return nil
  end

  -- If no chain (just module reference), return module path
  if not chain.chain or #chain.chain == 0 then
    return {
      language   = "lua",
      kind       = "module",
      path       = abs,
      range      = nil,
      chain      = nil,
      source     = "treesitter",
      confidence = 0.7,
    }
  end

  -- Try to locate the symbol within the file
  local needle = chain.chain[#chain.chain]
  local lines = vim.fn.readfile(abs)
  local best_line, best_col

  -- Heuristic patterns (in priority order)
  local patterns = {
    -- 1. Function definitions: function M.needle(...) or function X:needle(...)
    ("function%s+[%%w_%.:]*%f[^%%w_]" .. needle .. "%f[^%%w_]%s*%("),

    -- 2. Field assignment with function: M.needle = function(...)
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*=%s*function%s*%("),

    -- 3. Local function: local function needle(...)
    ("^%s*local%s+function%s+" .. needle .. "%s*%("),

    -- 4. Field assignment (any value): M.needle = value
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*="),

    -- 5. Table key: needle = value (in return table or local table)
    ("%f[%w_]" .. needle .. "%s*="),
  }

  for i = 1, #lines do
    local s = lines[i]
    for _, pat in ipairs(patterns) do
      local c = s:find(pat)
      if c then
        best_line = i
        best_col = c
        break
      end
    end
    if best_line then
      break
    end
  end

  -- Return result (even if symbol not found - user can navigate file manually)
  if not best_line then
    return {
      language   = "lua",
      kind       = "module",
      path       = abs,
      range      = nil,
      chain      = chain.chain,
      source     = "treesitter",
      confidence = 0.5,
    }
  end

  return {
    language   = "lua",
    kind       = "field",
    path       = abs,
    range      = LOC.create_range(best_line, best_col),
    chain      = chain.chain,
    source     = "treesitter",
    confidence = 0.75,
  }
end

return M
