---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.
---@description
--- Central dispatch table: maps (filetype, provider) pairs to resolver pipelines.
--- Adding support for a new language means registering its resolvers in `RES`
--- and adding a pipeline entry in `PIPELINE`. No changes to `resolve.lua` needed.

local C = require("gopath.config")

-- Language resolver modules, keyed by filetype then resolver name.
local RES = {
  lua = {
    require_path      = require("gopath.resolvers.lua.require_path"),
    binding_index     = require("gopath.resolvers.lua.binding_index"),
    alias_index       = require("gopath.resolvers.lua.alias_index"),
    chain             = require("gopath.resolvers.lua.chain"),
    value_origin      = require("gopath.resolvers.lua.value_origin"),
    symbol_locator    = require("gopath.resolvers.lua.symbol_locator"),
    identifier_locator= require("gopath.resolvers.lua.identifier_locator"),
  },
  common = {
    filetoken = require("gopath.resolvers.common.filetoken"),
    help      = require("gopath.resolvers.common.help"),
  },
}

---@private
local function has_name(list, name)
  if not list then return true end
  for i = 1, #list do
    if list[i] == name then return true end
  end
  return false
end

-- Provider pipelines as a dispatch table.
-- Each entry receives (L, cfg, active) and returns GopathResult|nil.
---@type table<string, fun(L:table, cfg:GopathOptions, active:string[]|nil): GopathResult|nil>
local PIPELINE = {

  lsp = function(L, cfg, active)
    -- Help check (cheap, runs before any LSP round-trip)
    local hr = RES.common.help.resolve()
    if hr then return hr end

    -- Precise symbol definition via LSP
    if has_name(active, "symbol_locator") and L.symbol_locator then
      local r = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
      if r then return r end
    end

    -- Module resolution (fast, no LSP)
    if has_name(active, "require_path") and L.require_path then
      local r = L.require_path.resolve()
      if r then return r end
    end

    return nil
  end,

  treesitter = function(L, _, active)
    -- Help check
    local hr = RES.common.help.resolve()
    if hr then return hr end

    -- Value origin: cfg.* → M.cfg.*
    if has_name(active, "value_origin") and L.value_origin then
      local r = L.value_origin.resolve()
      if r then return r end
    end

    -- Gather semantic context for downstream resolvers
    local chain = nil
    if has_name(active, "chain") and L.chain then
      chain = L.chain.get_chain_at_cursor()
    end
    local bind = nil
    if has_name(active, "binding_index") and L.binding_index then
      bind = L.binding_index.get_map()
    end

    -- Bare identifier → module
    if has_name(active, "identifier_locator") and L.identifier_locator then
      local r = L.identifier_locator.resolve()
      if r then return r end
    end

    -- Symbol with treesitter context
    if has_name(active, "symbol_locator") and L.symbol_locator and chain and bind then
      local r = L.symbol_locator.via_treesitter(chain, bind)
      if r then return r end
    end

    -- Module path resolution
    if has_name(active, "require_path") and L.require_path then
      local r = L.require_path.resolve()
      if r then return r end
    end

    return nil
  end,

  builtin = function(L, _, active)
    -- Generic filetoken (works for any filetype)
    if has_name(active, "filetoken") then
      local r = RES.common.filetoken.resolve()
      if r then return r end
    end

    -- Lua require path
    if has_name(active, "require_path") and L.require_path then
      local r = L.require_path.resolve()
      if r then return r end
    end

    return nil
  end,
}

local M = {}

---Run the per-language pipeline for one provider pass.
---@param filetype string
---@param provider  "lsp"|"treesitter"|"builtin"
---@param _opts     table|nil  (reserved for future per-call options)
---@return GopathResult|nil
---@diagnostic disable-next-line: unused-local
function M.run_language_pipeline(filetype, provider, _opts)
  local cfg      = C.get()
  local lang_cfg = cfg.languages[filetype]

  if not (lang_cfg and lang_cfg.enable ~= false) then return nil end

  local L = RES[filetype]
  if not L then return nil end

  local handler = PIPELINE[provider]
  if not handler then return nil end

  return handler(L, cfg, lang_cfg.resolvers)
end

---Return the list of available resolver names for `filetype` (for UI/debug).
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
  local t   = RES[filetype] or {}
  local out = {}
  local i   = 0
  for k in pairs(t) do
    i = i + 1
    out[i] = k
  end
  table.sort(out)
  return out
end

return M
