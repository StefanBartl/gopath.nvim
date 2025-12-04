---@module 'gopath.resolvers.common.filetoken'
---@brief Resolve <cfile> with smart token extraction and location parsing.

local P = require("gopath.providers.builtin")
local U = require("gopath.util.path")
local LOC = require("gopath.util.location")

local M = {}

---Check if a string looks like a file path (heuristic)
---@param str string
---@return boolean
local function looks_like_path(str)
	if not str or str == "" then
		return false
	end

	-- REJECT: Lua chain without path separator
	if str:match("^[%w_]+%.[%w_]+$") and not str:match("[/\\]") then
		local common_exts = { "lua", "txt", "md", "vim", "json", "toml", "yaml", "py", "js", "ts", "html", "css" }
		local ext = str:match("%.([^%.]+)$")
		local has_common_ext = ext and vim.tbl_contains(common_exts, ext)

		if not has_common_ext then
			return false
		end
	end

	-- ACCEPT: Has file extension
	if str:match("%.[a-zA-Z][a-zA-Z0-9]*$") then
		return true
	end

	-- ACCEPT: Has path separator
	if str:match("[/\\]") then
		return true
	end

	-- ACCEPT: Starts with ~/ or ./
	if str:match("^[~%.][\\/]") then
		return true
	end

	-- ACCEPT: Has explicit line number
	if str:match(":%d+") or str:match("%(%d+%)") then
		return true
	end

	-- ACCEPT: Starts with ... (truncated)
	if str:match("^%.%.%.") then
		return true
	end

	return false
end

---Clean and parse token
---@param raw string Raw token
---@return table|nil parsed { path: string, line: integer|nil, col: integer|nil }
local function parse_token(raw)
	if not raw or raw == "" then
		return nil
	end

	-- Strip leading error message prefixes
	local cleaned = raw
	local prefixes = {
		"^Error%s+in%s+",
		"^%s*at%s+",
		"^%s*in%s+",
		"^%s*from%s+",
	}

	for _, prefix in ipairs(prefixes) do
		cleaned = cleaned:gsub(prefix, "")
	end

	-- Parse location (handles :line:col, (line), etc.)
	local parsed = LOC.parse_location(cleaned)

	if not parsed.path or parsed.path == "" then
		return nil
	end

	-- Additional cleaning
	local path = parsed.path
	path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1") -- Strip quotes
	path = path:gsub("^%.%.%./", "") -- Strip leading ...
	path = path:gsub("^%s+", ""):gsub("%s+$", "") -- Trim

	-- Final validation
	if not looks_like_path(path) then
		return nil
	end

	return {
		path = path,
		line = parsed.line,
		col = parsed.col,
	}
end

---@return GopathResult|nil
function M.resolve()
	local raw = P.expand_cfile()
	if not raw then
		return nil
	end

	local parsed = parse_token(raw)
	if not parsed then
		return nil
	end

	local token = parsed.path

	-- Search for file
	local abs = U.search_with_vim_path(token)

	if not abs then
		local tail = token:match("/lua/(.+)$")
		if tail then
			abs = U.search_in_rtp({ tail })
		end
	end

	if not abs then
		local segs = vim.split(token, "/", { trimempty = true, plain = true })
		for k = math.max(1, #segs - 2), math.max(1, #segs - 1) do
			local t = table.concat(segs, "/", k)
			abs = U.search_in_rtp({ t })
			if abs then
				break
			end
		end
	end

	-- Build absolute path even if not found
	if not abs then
		local cwd = vim.fn.expand("%:p:h")
		if token:match("^[/\\]") or token:match("^[A-Za-z]:") then
			abs = token
		else
			abs = vim.fn.fnamemodify(cwd .. "/" .. token, ":p")
		end
	end

	local exists = U.exists(abs)

	return {
		language = vim.bo.filetype or "text",
		kind = exists and "module" or "file",
		path = abs,
		range = LOC.create_range(parsed.line, parsed.col),
		chain = nil,
		source = "builtin",
		confidence = exists and 0.75 or 0.3,
		exists = exists,
	}
end

return M
