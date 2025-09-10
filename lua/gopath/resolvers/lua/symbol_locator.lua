---@module 'gopath.resolvers.lua.symbol_locator'
---@brief Locate functions/fields/tables/primitives inside a module file.

local PATH = require("gopath.util.path")
local LSP  = require("gopath.providers.lsp")
-- local BIX  = require("gopath.resolvers.lua.binding_index")
-- local CHN  = require("gopath.resolvers.lua.chain")
-- local REQ  = require("gopath.resolvers.lua.require_path")

local M = {}

--- LSP-first: try getting a Definition for the symbol under cursor.
---@param opts { timeout_ms?: integer }|nil
---@return table|nil  -- GopathResult
function M.via_lsp(opts)
  local timeout = (opts and opts.timeout_ms) or 200
  local defs = LSP.definition_at_cursor(timeout)
  if not defs then return nil end
  local d = defs[1]
  return {
    language   = "lua",
    kind       = "field", -- best-effort; precise kind is not essential for opening
    path       = d.path,
    range      = d.range,
    chain      = nil,
    source     = "lsp",
    confidence = 1.0,
  }
end

-- Fallback: use chain + binding to find module path, then locate last element.
---@param chain { base:string, chain:string[] }
---@param bind table<string,string>
---@return table|nil
function M.via_treesitter(chain, bind)
  local mod = bind[chain.base]
  if not mod then return nil end

  local rel = mod:gsub("%.", "/")
  local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" }) or PATH.search_with_package_path(mod)
  if not abs then return nil end

  local needle = chain.chain[#chain.chain]
  local lines = vim.fn.readfile(abs)
  local best_line, best_col

  -- Heuristic priority: function defs > field assign > table return key
  local patterns = {
    -- function M.needle( ... )  | function X:needle( ... )
    ("function%s+[%%w_%.:]*%f[^%%w_]" .. needle .. "%f[^%%w_]"),
    -- M.needle = function( ... ) | M['needle'] = function(
    ("[%w_%.]+%s*[%[:]['\"]?" .. needle .. "['\"]?[]:]?%s*=%s*function%s*%f[^%w_]"),
    -- needle = function( ... )
    ("^%s*" .. needle .. "%s*=%s*function%f[^%w_]"),
    -- table field assignment: needle = <value>
    ("[%w_%.]+%s*[%[:]['\"]?" .. needle .. "['\"]?[]:]?%s*="),
    -- return { needle = ... }
    ("return%s*{%s*.*" .. needle .. "%s*="),
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
    -- No exact match; still return module path so the caller can open the file.
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
    range      = { line = best_line, col = best_col },
    chain      = chain.chain,
    source     = "treesitter",
    confidence = 0.75,
  }
end

return M
