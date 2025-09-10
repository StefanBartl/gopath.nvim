---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.

local C = require("gopath.config")

-- Language resolvers (1 file = 1 feature)
local RES = {
  lua = {
    require_path   = require("gopath.resolvers.lua.require_path"),
    binding_index  = require("gopath.resolvers.lua.binding_index"),
    chain          = require("gopath.resolvers.lua.chain"),
    symbol_locator = require("gopath.resolvers.lua.symbol_locator"),
  },
  common = {
    filetoken = require("gopath.resolvers.common.filetoken"),
  },
}

local function keys_of(t)
  local out, i = {}, 0
  for k, _ in pairs(t or {}) do i = i + 1; out[i] = k end
  table.sort(out)
  return out
end

---@param list string[]|nil
---@param name string
---@return boolean
local function has_name(list, name)
  if not list then return true end -- nil means "use all"
  for i = 1, #list do
    if list[i] == name then return true end
  end
  return false
end

local M = {}

--- Run the per-language pipeline for one provider pass.
--- Provider: "lsp" | "treesitter" | "builtin"
---@param filetype string
---@param provider "lsp"|"treesitter"|"builtin"
---@param opts table|nil
---@return table|nil  -- GopathResult
---@diagnostic disable-next-line unused-param
function M.run_language_pipeline(filetype, provider, opts)
  local cfg = C.get()
  local lang_cfg = cfg.languages[filetype]
  if not (lang_cfg and lang_cfg.enable) then
    return nil
  end

  local L = RES[filetype]
  if not L then return nil end

  -- Active resolvers:
  -- If user didn't specify `resolvers`, we treat it as "all available for this language".
  local active = lang_cfg.resolvers -- can be nil

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
    -- Go for precise symbol if enabled
    if has_name(active, "symbol_locator") and L.symbol_locator then
      local rr = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
      if rr then return rr end
    end
    -- Fallback to module open (useful if cursor is inside require(...))
    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end
    return nil
  end

  if provider == "treesitter" then
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

    -- Fallback: pure require(...) to at least open module file
    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end
    return nil
  end

  return nil
end

--- Expose what resolvers exist for a given language (useful for UI/debug).
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
  return keys_of(RES[filetype] or {})
end

return M
