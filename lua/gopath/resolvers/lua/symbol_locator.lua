---@module 'gopath.resolvers.lua.symbol_locator'
---@brief Locate functions/fields/tables with LSP precision and smart fallbacks.

local PATH = require("gopath.util.path")
local LOC = require("gopath.util.location")
local LSP  = require("gopath.providers.lsp")

local M = {}

---LSP-first: Get precise definition for symbol under cursor.
---@param opts { timeout_ms?: integer }|nil
---@return table|nil  -- GopathResult
function M.via_lsp(opts)
  local timeout = (opts and opts.timeout_ms) or 200
  local defs = LSP.definition_at_cursor(timeout)

  if not defs or #defs == 0 then
    return nil
  end

  local d = defs[1]

  if not d.path then
    return nil
  end

  local base_result = {
    language   = "lua",
    kind       = "symbol",
    path       = d.path,
    range      = LOC.normalize_range(d.range),
    chain      = nil,
    source     = "lsp",
    confidence = 1.0,
  }

  -- ENHANCEMENT: Check if LSP points to local require()
  -- If so, resolve to the actual module instead
  local enhancer = require("gopath.resolvers.lua.local_to_module")
  local enhanced = enhancer.enhance_lsp_result(base_result)

  if enhanced then
    return enhanced  -- Jump to module, not local variable
  end

  return base_result  -- Standard LSP result
end

---Treesitter fallback: Use chain + binding to find module, then locate symbol.
---@param chain { base:string, chain:string[] }
---@param bind table<string,string>
---@return table|nil
function M.via_treesitter(chain, bind)
  if not chain or not bind then
    return nil
  end

  local mod = bind[chain.base]
  if not mod then
    return nil
  end

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

  -- Locate symbol in file
  local needle = chain.chain[#chain.chain]
  local lines = vim.fn.readfile(abs)
  local best_line, best_col

  local patterns = {
    ("function%s+[%%w_%.:]*%f[^%%w_]" .. needle .. "%f[^%%w_]%s*%("),
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*=%s*function%s*%("),
    ("^%s*local%s+function%s+" .. needle .. "%s*%("),
    ("[%w_%.]+%s*%.%s*" .. needle .. "%s*="),
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
    if best_line then break end
  end

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
