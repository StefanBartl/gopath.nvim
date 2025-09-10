---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.

local C = require("gopath.config")

-- Language resolvers (1 file = 1 feature)
local RES = {
  lua = {
    require_path   = require("gopath.resolvers.lua.require_path"),
    binding_index  = require("gopath.resolvers.lua.binding_index"),
    alias_index    = require("gopath.resolvers.lua.alias_index"),
    chain          = require("gopath.resolvers.lua.chain"),
    value_origin   = require("gopath.resolvers.lua.value_origin"),
    symbol_locator = require("gopath.resolvers.lua.symbol_locator"),
  },
  common = {
    filetoken = require("gopath.resolvers.common.filetoken"),
    help      = require("gopath.resolvers.common.help"),
  },
}

local function has_name(list, name)
  if not list then return true end
  for i = 1, #list do
    if list[i] == name then return true end
  end
  return false
end

local M = {}

--- Run the per-language pipeline for one provider pass.
---@param filetype string
---@param provider "lsp"|"treesitter"|"builtin"
---@param opts table|nil
---@return table|nil  -- GopathResult
---@diagnostic disable-next-line unsued-param 'opts'
function M.run_language_pipeline(filetype, provider, opts)
  local cfg = C.get()
  local lang_cfg = cfg.languages[filetype]
  if not (lang_cfg and lang_cfg.enable) then return nil end
  local L = RES[filetype]
  if not L then return nil end
  local active = lang_cfg.resolvers -- nil => all

  -- Always allow a quick :help match regardless of provider (cheap, safe).
  do
    local hr = RES.common.help.resolve()
    if hr then return hr end
  end

  if provider == "builtin" then
    -- 1) generic file token (common)
    if has_name(active, "filetoken") then
      local r = RES.common.filetoken.resolve()
      if r then return r end
    end
    -- 2) require(...) path (lua)
    if has_name(active, "require_path") and L.require_path then
      local rr = L.require_path.resolve()
      if rr then return rr end
    end
    return nil
  end

  if provider == "lsp" then
    -- Prefer precise symbol via LSP
    if has_name(active, "symbol_locator") and L.symbol_locator then
      local rr = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
      if rr then return rr end
    end
    -- Fallback to module open
    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end
    return nil
  end

  if provider == "treesitter" then
    -- Prefer value-origin initializer (cfg.* → M.cfg.*) before anything else
    if has_name(active, "value_origin") and L.value_origin then
      local vo = L.value_origin.resolve()
      if vo then return vo end
    end

    -- chain + binding index help symbol locator for module fields
    local chain = nil
    if has_name(active, "chain") and L.chain then
      chain = L.chain.get_chain_at_cursor()
    end
    local bind = nil
    if has_name(active, "binding_index") and L.binding_index then
      bind = L.binding_index.get_map()
    end

    if has_name(active, "symbol_locator") and L.symbol_locator and chain and bind then
      local rr = L.symbol_locator.via_treesitter(chain, bind)
      if rr then return rr end
    end

    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end
    return nil
  end

  return nil
end

--- For UI/debug.
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
  local t = RES[filetype] or {}
  local out, i = {}, 0
  for k, _ in pairs(t) do i=i+1; out[i]=k end
  table.sort(out)
  return out
end

return M
