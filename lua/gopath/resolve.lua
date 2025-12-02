---@module 'gopath.resolve'
---@brief Orchestrates providers to produce a GopathResult (path + optional range).

local C    = require("gopath.config")
local REG  = require("gopath.registry")
local safe = require("gopath.util.safe")

local M    = {}

---@class GopathResolveOpts
---@field order string[]|nil
---@field timeout_ms integer|nil

--- Resolve the entity under cursor using configured providers and language resolvers.
---@param opts GopathResolveOpts|nil
---@return table|nil, string|nil  -- GopathResult|nil, error|nil
function M.resolve_at_cursor(opts)
	local cfg = C.get()
	local ft = vim.bo.filetype or "text"

	-- ALWAYS try help first (works for all filetypes)
	do
		local help = require("gopath.resolvers.common.help").resolve()
		if help then return help, nil end
	end

	-- ALWAYS try filetoken (works for all filetypes)
	do
		local ftok = require("gopath.resolvers.common.filetoken").resolve()
		if ftok then return ftok, nil end
	end

	-- Check if language-specific features are available AND enabled
	local lang = cfg.languages[ft]
	local lang_enabled = lang and lang.enable ~= false  -- nil or true = enabled

	-- If language explicitly disabled, stop here
	if lang == false or (lang and lang.enable == false) then
		return nil, "language-disabled"
	end

	-- Try language-specific resolvers if available
	if lang_enabled then
		local order
		if cfg.mode == "lsp" then
			order = { "lsp" }
		elseif cfg.mode == "treesitter" then
			order = { "treesitter" }
		elseif cfg.mode == "builtin" then
			order = { "builtin" }
		else
			order = (opts and opts.order) or cfg.order or { "lsp", "treesitter", "builtin" }
		end

		for _, provider in ipairs(order) do
			local ok, result_or_err = safe.call(function()
				return REG.run_language_pipeline(ft, provider, {
					timeout_ms = (opts and opts.timeout_ms) or cfg.lsp_timeout_ms,
				})
			end)
			if ok and result_or_err then
				return result_or_err, nil
			end
		end
	end

	-- Final fallback: try to extract <cfile> even if no language-specific resolver matched
	local cfile = vim.fn.expand("<cfile>")
	if cfile and cfile ~= "" then
		-- Return as minimal result for alternate/external handling
		return {
			language   = ft,
			kind       = "file",
			path       = cfile,
			range      = nil,
			chain      = nil,
			source     = "builtin-fallback",
			confidence = 0.5,
			exists     = false,  -- Flag for downstream handlers
		}, nil
	end

	return nil, "no-match"
end

return M
