---@module 'gopath.config'
--- User options merge + sane defaults with default keymaps and commands.

local M = {}

---@type GopathOptions
local defaults = {
    dev_mode = false,
	mode = "hybrid",
	order = { "lsp", "treesitter", "builtin" },
	lsp_timeout_ms = 200,

	languages = {
		lua = {
			enable = true,
			resolvers = nil,
			custom_resolvers = nil,
		},
	},

	alternate = {
		enable = true,
		similarity_threshold = 75,
	},

	external = {
		enable = true,
		extensions = nil,
	},

	-- Truncated path resolution configuration
	truncated = {
		enable = true,
		use_cache = true, -- Enable in-memory cache
		cache_refresh_interval = 600, -- Refresh every 10 minutes
		max_cache_age = 3600, -- Consider cache stale after 1 hour
		live_search_fallback = true, -- Use fd/rg/find if cache misses
		similarity_threshold = 75, -- For multiple match selection

		-- === Cache Roots Configuration ===
		-- Directories/drives to scan and cache
		-- nil = auto-detect (recommended for most users)
		-- Explicit list examples:
		--   Windows: { "C:\\", "D:\\", "C:\\Users\\YourName" }
		--   Unix:    { "/home/user", "/usr/local", "/opt" }
		cache_roots = nil,

		-- === Cache Behavior ===
		max_depth = 6, -- Maximum directory depth to scan
		excluded_dirs = { -- Directories to skip
			".git",
			".github",
			"node_modules",
			"target",
			"build",
			".cache",
			"venv",
		},
		watch_patterns = nil,
		auto_rebuild_on_save = false,
	},

	mappings = {
		open_here = "gP", -- or { "gP", "<2-LeftMouse>" }
		open_split = "g|",
		open_vsplit = "g\\",
		open_tab = "g}",
		copy_location = "gY",
		debug = "g?",
	},

	commands = {
		resolve = true,
		open = true,
		copy = true,
		debug = true,
	},
}

---@param dst table
---@param src table
local function deep_merge_into(dst, src)
	for k, v in pairs(src or {}) do
		if type(v) == "table" and type(dst[k]) == "table" then
			deep_merge_into(dst[k], v)
		else
			dst[k] = v
		end
	end
end

---@type GopathOptions
local state = vim.deepcopy(defaults)

---@param opts GopathOptions|nil
function M.setup(opts)
	if opts and type(opts) == "table" then
		deep_merge_into(state, opts)
	end
end

---@return GopathOptions
function M.get()
	return state
end

return M
