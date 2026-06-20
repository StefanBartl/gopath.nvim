---@meta
---@module 'gopath.resolvers.lua.@types'
---@brief Type definitions for the Lua language-specific resolvers.

-- #####################################################################
-- chain.lua

---@class LuaChainInfo
--- Result of `chain.get_chain_at_cursor`.
---@field base  string    Root identifier (e.g. "M" or "vim")
---@field chain string[]  Dotted members accessed after the root (e.g. {"api", "nvim_buf_get_lines"})

-- #####################################################################
-- binding_index.lua

---@alias LuaBindingMap table<string, string>
--- Maps local identifier names to the module path they were bound to.
--- E.g. `{ M = "gopath.resolve", safe = "gopath.util.safe" }`.

-- #####################################################################
-- alias_index.lua

---@class LuaAliasEntry
--- One entry in the per-buffer alias cache.
---@field kind   '"require"'|'"chain"'|'"id"'
---@field module string|nil   Dotted module path (for "require" entries)
---@field chain  string|nil   Dotted chain suffix (for "chain" entries)
---@field id     string|nil   Identifier name (for "id" entries)

---@class LuaAliasCache
--- Versioned per-buffer cache of resolved aliases.
---@field tick integer               Buffer changetick at which this cache was built
---@field map  table<string,LuaAliasEntry>  Map of identifier → alias info

-- #####################################################################
-- require_path.lua  /  local_to_module.lua

---@class LuaModuleResolution
--- Intermediate result from module-name → file-path conversion.
---@field mod  string      Dotted module name (e.g. "custom.markdown.hl_groups.blockquote")
---@field path string|nil  Resolved absolute file path, or nil if not found on rtp/package.path

return {}
