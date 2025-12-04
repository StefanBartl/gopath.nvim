---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.

local C = require("gopath.config")

-- Language resolvers
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
	common = {
		filetoken = require("gopath.resolvers.common.filetoken"),
		help = require("gopath.resolvers.common.help"),
	},
}

local function has_name(list, name)
	if not list then
		return true
	end
	for i = 1, #list do
		if list[i] == name then
			return true
		end
	end
	return false
end

local M = {}

---Run the per-language pipeline for one provider pass.
---@param filetype string
---@param provider "lsp"|"treesitter"|"builtin"
---@param _opts table|nil
---@return table|nil  -- GopathResult
---@diagnostic disable-next-line: unused-local _opts
function M.run_language_pipeline(filetype, provider, _opts)
	local cfg = C.get()
	local lang_cfg = cfg.languages[filetype]

	if not (lang_cfg and lang_cfg.enable ~= false) then
		return nil
	end

	local L = RES[filetype]
	if not L then
		return nil
	end

	local active = lang_cfg.resolvers

	-- Always allow quick :help match (cheap, safe)
	do
		local hr = RES.common.help.resolve()
		if hr then
			return hr
		end
	end

	-- === LSP PROVIDER === (HIGHEST PRECISION)
	if provider == "lsp" then
		-- For LSP, prioritize symbol locator (gets exact definitions)
		if has_name(active, "symbol_locator") and L.symbol_locator then
			local rr = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
			if rr then
				return rr -- Precise symbol definition with line/col
			end
		end

		-- Fallback: module resolution
		if has_name(active, "require_path") and L.require_path then
			local rp = L.require_path.resolve()
			if rp then
				return rp
			end
		end

		return nil
	end

	-- === TREESITTER PROVIDER === (SEMANTIC ANALYSIS)
	if provider == "treesitter" then
		-- 1. Value origin (cfg.* → M.cfg.*)
		if has_name(active, "value_origin") and L.value_origin then
			local vo = L.value_origin.resolve()
			if vo then
				return vo
			end
		end

		-- 2. Build context for symbol locator
		local chain = nil
		if has_name(active, "chain") and L.chain then
			chain = L.chain.get_chain_at_cursor()
		end

		local bind = nil
		if has_name(active, "binding_index") and L.binding_index then
			bind = L.binding_index.get_map()
		end

		-- 3. Identifier locator (bare variable → module)
		if has_name(active, "identifier_locator") and L.identifier_locator then
			local id_result = L.identifier_locator.resolve()
			if id_result then
				return id_result
			end
		end

		-- 4. Symbol locator with treesitter fallback
		if has_name(active, "symbol_locator") and L.symbol_locator and chain and bind then
			local rr = L.symbol_locator.via_treesitter(chain, bind)
			if rr then
				return rr
			end
		end

		-- 5. Require path resolution
		if has_name(active, "require_path") and L.require_path then
			local rp = L.require_path.resolve()
			if rp then
				return rp
			end
		end

		return nil
	end

	-- === BUILTIN PROVIDER === (FALLBACK)
	if provider == "builtin" then
		-- 1. Generic file token (works for all file types)
		if has_name(active, "filetoken") then
			local r = RES.common.filetoken.resolve()
			if r then
				return r
			end
		end

		-- 2. Require path (Lua-specific)
		if has_name(active, "require_path") and L.require_path then
			local rr = L.require_path.resolve()
			if rr then
				return rr
			end
		end

		return nil
	end

	return nil
end

---For UI/debug.
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
	local t = RES[filetype] or {}
	local out, i = {}, 0
	for k, _ in pairs(t) do
		i = i + 1
		out[i] = k
	end
	table.sort(out)
	return out
end

return M
