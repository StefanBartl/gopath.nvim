---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.
---@description
--- Central dispatch hub. Three tables drive everything:
---   • RES           — resolver modules, keyed by filetype then resolver name.
---   • BUILTIN_ORDER — ordered resolver names the *builtin* provider runs per ft.
---   • PIPELINE      — one handler per provider (lsp / treesitter / builtin).
--- Adding a language means: register its resolver(s) in RES, list them in
--- BUILTIN_ORDER, and add a `languages.<ft>` config entry. No changes to
--- resolve.lua are required. User-supplied `custom_resolvers` run before the
--- built-in ones for their filetype.

local C = require("gopath.config")
local LOG = require("gopath.util.log")

-- Resolver modules, keyed by filetype then resolver name.
-- Several filetypes share one resolver module (ts↔js, cpp↔c).
local js_import = require("gopath.resolvers.javascript.import_path")
local c_include = require("gopath.resolvers.c.include_path")

local RES = {
  lua = {
    require_path = require("gopath.resolvers.lua.require_path"),
    binding_index = require("gopath.resolvers.lua.binding_index"),
    alias_index = require("gopath.resolvers.lua.alias_index"),
    chain = require("gopath.resolvers.lua.chain"),
    value_origin = require("gopath.resolvers.lua.value_origin"),
    symbol_locator = require("gopath.resolvers.lua.symbol_locator"),
    identifier_locator = require("gopath.resolvers.lua.identifier_locator"),
  },
  python = { import_path = require("gopath.resolvers.python.import_path") },
  javascript = { import_path = js_import },
  javascriptreact = { import_path = js_import },
  typescript = { import_path = js_import },
  typescriptreact = { import_path = js_import },
  rust = { use_path = require("gopath.resolvers.rust.use_path") },
  go = { import_path = require("gopath.resolvers.go.import_path") },
  c = { include_path = c_include },
  cpp = { include_path = c_include },
  cs = { using_path = require("gopath.resolvers.csharp.using_path") },
  zig = { import_path = require("gopath.resolvers.zig.import_path") },
  java = { import_path = require("gopath.resolvers.java.import_path") },
  common = {
    filetoken = require("gopath.resolvers.common.filetoken"),
    help = require("gopath.resolvers.common.help"),
  },
}

-- Ordered resolver names the builtin provider tries, per filetype.
-- (filetoken is run separately, before this list, for every filetype.)
local BUILTIN_ORDER = {
  lua = { "require_path" },
  python = { "import_path" },
  javascript = { "import_path" },
  javascriptreact = { "import_path" },
  typescript = { "import_path" },
  typescriptreact = { "import_path" },
  rust = { "use_path" },
  go = { "import_path" },
  c = { "include_path" },
  cpp = { "include_path" },
  cs = { "using_path" },
  zig = { "import_path" },
  java = { "import_path" },
}

---@private
local function has_name(list, name)
  if not list then return true end
  for i = 1, #list do
    if list[i] == name then return true end
  end
  return false
end

---Run any user-supplied custom resolvers for `lang_cfg`.
---Each entry is a Resolver table or a module name string returning one.
---@private
---@param lang_cfg GopathLanguageOptions
---@return GopathResult|nil
local function run_custom_resolvers(lang_cfg)
  local list = lang_cfg.custom_resolvers
  if type(list) ~= "table" then return nil end

  for i = 1, #list do
    local entry = list[i]
    local resolver = entry

    -- Allow a module name string for convenience.
    if type(entry) == "string" then
      local ok, mod = pcall(require, entry)
      resolver = ok and mod or nil
    end

    if type(resolver) == "table" and type(resolver.resolve) == "function" then
      local ok, result = pcall(resolver.resolve)
      if ok and result then
        return result
      elseif not ok then
        LOG.debug("custom resolver error: " .. tostring(result))
      end
    end
  end

  return nil
end

-- Provider pipelines. Each receives (L, cfg, lang_cfg, filetype).
---@type table<string, fun(L:table, cfg:GopathOptions, lang_cfg:GopathLanguageOptions, filetype:string): GopathResult|nil>
local PIPELINE = {

  lsp = function(L, cfg, _, _)
    local hr = RES.common.help.resolve()
    if hr then return hr end

    if L.symbol_locator then
      local r = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
      if r then return r end
    end
    if L.require_path then
      local r = L.require_path.resolve()
      if r then return r end
    end
    return nil
  end,

  treesitter = function(L, _, lang_cfg, _)
    local hr = RES.common.help.resolve()
    if hr then return hr end

    local active = lang_cfg.resolvers

    if has_name(active, "value_origin") and L.value_origin then
      local r = L.value_origin.resolve()
      if r then return r end
    end

    local chain = nil
    if has_name(active, "chain") and L.chain then chain = L.chain.get_chain_at_cursor() end
    local bind = nil
    if has_name(active, "binding_index") and L.binding_index then
      bind = L.binding_index.get_map()
    end

    if has_name(active, "identifier_locator") and L.identifier_locator then
      local r = L.identifier_locator.resolve()
      if r then return r end
    end

    if has_name(active, "symbol_locator") and L.symbol_locator and chain and bind then
      local r = L.symbol_locator.via_treesitter(chain, bind)
      if r then return r end
    end

    if has_name(active, "require_path") and L.require_path then
      local r = L.require_path.resolve()
      if r then return r end
    end
    return nil
  end,

  builtin = function(L, _, lang_cfg, filetype)
    local active = lang_cfg.resolvers

    -- NOTE: the generic filetoken resolver is intentionally NOT run here.
    -- resolve.lua already runs it before the language pipeline and keeps any
    -- non-existing result as a last-resort fallback. Running it here again
    -- would short-circuit on non-existing tokens (e.g. "./util", "/foo")
    -- before the language-specific resolver gets a chance.
    local order = BUILTIN_ORDER[filetype] or {}
    for i = 1, #order do
      local name = order[i]
      if has_name(active, name) and L[name] then
        local r = L[name].resolve()
        if r then return r end
      end
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
  local cfg = C.get()
  local lang_cfg = cfg.languages[filetype]

  if not (lang_cfg and lang_cfg.enable ~= false) then return nil end

  local L = RES[filetype]
  if not L then return nil end

  -- User-supplied custom resolvers take precedence over built-ins.
  local custom = run_custom_resolvers(lang_cfg)
  if custom then return custom end

  local handler = PIPELINE[provider]
  if not handler then return nil end

  return handler(L, cfg, lang_cfg, filetype)
end

---Return the list of available resolver names for `filetype` (for UI/debug).
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
  local t = RES[filetype] or {}
  local out = {}
  local i = 0
  for k in pairs(t) do
    i = i + 1
    out[i] = k
  end
  table.sort(out)
  return out
end

return M
