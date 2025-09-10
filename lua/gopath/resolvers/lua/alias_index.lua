---@module 'gopath.resolvers.lua.alias_index'
---@brief Build alias graph: id -> { kind="require"/"chain"/"id", ... } with changedtick cache.

local M = {}


local cache = setmetatable({}, { __mode = "k" }) -- bufnr -> _AliasCache

local function cur_tick(bufnr) return vim.api.nvim_buf_get_changedtick(bufnr) end

---@param bufnr integer
---@return table<string,_AliasEntry>
local function rebuild(bufnr)
	local n = vim.api.nvim_buf_line_count(bufnr)
	local map = {}
	for i = 1, n do
		local s = vim.api.nvim_buf_get_lines(bufnr, i - 1, i, false)[1] or ""

		-- local X = require "mod"    / local X = require('mod')  / local X = require [[mod]]
		local id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
		if not id then
			id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
		end
		if id and mod then
			map[id] = { kind = "require", module = mod }; goto continue
		end
		if id and mod then
			map[id] = { kind = "require", module = mod }; goto continue
		end

		-- local X = Y.Z or X = Y.Z (simple chain)
		local id2, chain = s:match("^%s*local%s+([%w_]+)%s*=%s*([%w_%.]+)")
		if id2 and chain and not chain:match("^require%s*%(") then
			map[id2] = { kind = "chain", chain = chain }; goto continue
		end
		local id3, chain2 = s:match("^%s*([%w_]+)%s*=%s*([%w_%.]+)")
		if id3 and chain2 and not chain2:match("^require%s*%(") then
			map[id3] = { kind = "chain", chain = chain2 }; goto continue
		end

		-- Very simple alias: local A = B
		local id4, idref = s:match("^%s*local%s+([%w_]+)%s*=%s*([%w_]+)%s*$")
		if id4 and idref then
			map[id4] = { kind = "id", id = idref }; goto continue
		end

		::continue::
	end
	return map
end

--- Get alias map for current buffer with changedtick cache.
---@return table<string,_AliasEntry>
function M.get_map()
	local buf = 0
	local e = cache[buf]
	local tick = cur_tick(buf)
	if e and e.tick == tick then return e.map end
	local map = rebuild(buf)
	cache[buf] = { tick = tick, map = map }
	return map
end

return M
