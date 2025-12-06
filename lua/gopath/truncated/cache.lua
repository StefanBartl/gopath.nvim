---@module 'gopath.truncated.cache'
---@description Async filesystem cache for fast truncated path resolution.
---
---Features:
---  - Async, non-blocking filesystem scanning
---  - In-memory storage for fast lookups
---  - Periodic background refresh
---  - Smart exclusions (.git, node_modules, etc.)
---  - Configurable scan roots (drives, directories)
---
---Cache lifecycle:
---  1. Load from disk on startup (if exists)
---  2. Build async if cache is old/missing (background)
---  3. Refresh periodically (configurable interval)
---  4. Save to disk after each build

local M = {}

local safe = require("gopath.util.safe_notify")
local uv = vim.loop

---@class CacheConfig
---@field max_depth integer Maximum directory depth to scan
---@field excluded_dirs string[] Directories to skip during scan
---@field cache_file string Path to persistent cache file
---@field scan_roots string[] Directories/drives to scan

---Default cache configuration
---User can override via gopath.setup({ truncated = { cache_roots = {...} } })
---@type CacheConfig
local config = {
	max_depth = 6, -- Don't descend too deep (performance)

	-- Smart exclusions: common directories that bloat cache
	excluded_dirs = {
		".git",
		".github",
		".svn",
		".hg", -- VCS
		"node_modules",
		"target",
		"build",
		"dist", -- Build artifacts
		".cache",
		".venv",
		"venv",
		"__pycache__", -- Python
		".nuxt",
		".next",
		".turbo", -- JS frameworks
		"tmp",
		"temp",
		"vendor", -- Temp/deps
	},

	-- Persistent cache location
	cache_file = vim.fn.stdpath("cache") .. "/gopath_fs_cache.json",

	-- Default scan roots (will be set in M.setup())
	scan_roots = {},
}

---Cache state
---Stored in memory for fast access during Neovim session
---@type { paths: string[], last_built: integer|nil, building: boolean }
local state = {
	paths = {}, -- All indexed file paths
	last_built = nil, -- Unix timestamp of last cache build
	building = false, -- Flag to prevent concurrent builds
}

---Setup cache configuration from user options
---Called during gopath.setup()
---@param opts table|nil User configuration for truncated.cache_roots
function M.setup(opts)
	opts = opts or {}

	-- === Configure Scan Roots ===
	if opts.roots and #opts.roots > 0 then
		-- User explicitly specified roots
		config.scan_roots = opts.roots
	else
		-- === Auto-detect Default Roots ===
		config.scan_roots = {}

		-- Current working directory (always useful)
		table.insert(config.scan_roots, vim.fn.getcwd())

		-- Neovim config directory
		table.insert(config.scan_roots, vim.fn.stdpath("config"))

		-- Neovim data directory
		table.insert(config.scan_roots, vim.fn.stdpath("data"))

		-- Platform-specific additions
		if vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
			-- === Windows: Add System Drive ===
			-- Default to C:\ but check SYSTEMDRIVE env var
			local system_drive = vim.env.SYSTEMDRIVE or "C:"
			table.insert(config.scan_roots, system_drive .. "\\")

			-- Add user profile directory
			if vim.env.USERPROFILE then
				table.insert(config.scan_roots, vim.env.USERPROFILE)
			end
		else
			-- === Unix: Add Home Directory ===
			local home = vim.env.HOME or "~"
			table.insert(config.scan_roots, home)
		end

		-- Git repository root (if in one)
		local git_root = vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1]
		if git_root and git_root ~= "" and vim.fn.isdirectory(git_root) == 1 then
			table.insert(config.scan_roots, git_root)
		end
	end

	-- === Apply Other Config Options ===
	if opts.max_depth then
		config.max_depth = opts.max_depth
	end

	if opts.excluded_dirs then
		config.excluded_dirs = opts.excluded_dirs
	end
end

---Check if directory should be excluded from scan
---@param name string Directory name (basename only)
---@return boolean should_exclude True if directory should be skipped
local function is_excluded(name)
	return vim.tbl_contains(config.excluded_dirs, name)
end

---Recursively scan directory (async, non-blocking)
---This function uses libuv's async filesystem APIs to avoid blocking Neovim
---
---@param dir string Directory path to scan
---@param depth integer Current recursion depth (starts at 0)
---@param callback fun(paths: string[]) Called with all found file paths
local function scan_dir_async(dir, depth, callback)
	-- === Depth Limit Check ===
	-- Prevent excessive recursion that could cause performance issues
	if depth > config.max_depth then
		callback({})
		return
	end

	local results = {}

	-- === Start Async Directory Scan ===
	---@diagnostic disable-next-line lib.uv
	uv.fs_scandir(dir, function(err, handle)
		if err or not handle then
			-- Directory not accessible (permissions, doesn't exist, etc.)
			callback(results)
			return
		end

		-- === Process Each Entry ===
		local function scan_next()
			---@diagnostic disable-next-line lib.uv
			uv.fs_scandir_next(handle, function(err2, name, type)
				if err2 or not name then
					-- End of directory entries
					callback(results)
					return
				end

				local full_path = dir .. "/" .. name

				if type == "file" then
					-- === File Found: Add to Results ===
					table.insert(results, full_path)
					scan_next() -- Continue with next entry
				elseif type == "directory" and not is_excluded(name) then
					-- === Directory Found: Recurse ===
					scan_dir_async(full_path, depth + 1, function(sub_results)
						-- Merge subdirectory results
						vim.list_extend(results, sub_results)
						scan_next() -- Continue with next entry
					end)
				else
					-- Excluded directory or other type (symlink, etc.)
					scan_next()
				end
			end)
		end

		scan_next() -- Start processing entries
	end)
end

---Build cache from configured scan roots
---This is non-blocking and runs entirely in the background
---
---@param callback fun(success: boolean) Called when build completes
function M.build_async(callback)
	-- === Prevent Concurrent Builds ===
	if state.building then
		-- vim.notify("[gopath] Cache build already in progress", vim.log.levels.WARN)
		callback(false)
		return
	end

	-- === Initialize Build ===
	state.building = true
	state.paths = {} -- Clear existing paths

    safe.safe_notify_defer(string.format("[gopath] Building cache from %d roots...", #config.scan_roots), vim.log.levels.INFO, nil, 50)

	-- === Scan All Roots ===
	local completed = 0
	local total = #config.scan_roots

	for _, root in ipairs(config.scan_roots) do
		-- Verify root exists before scanning
		if vim.fn.isdirectory(root) ~= 1 then
			completed = completed + 1
			if completed == total then
				M._finalize_build(callback)
			end
			goto continue
		end

		-- === Start Async Scan ===
		scan_dir_async(root, 0, function(paths)
			-- === Scan Complete for This Root ===
			vim.list_extend(state.paths, paths)
			completed = completed + 1

			if completed == total then
				-- === All Scans Complete ===
				M._finalize_build(callback)
			end
		end)

		::continue::
	end
end

---Finalize cache build (save to disk, update state)
---@param callback fun(success: boolean)
---@private
function M._finalize_build(callback)
	state.last_built = os.time()
	state.building = false

	-- === Save to Disk ===
	M._save_to_disk()

	-- === Notify User (on main thread) ===
	vim.schedule(function()
		vim.notify(string.format("[gopath] Cache built: %d files indexed", #state.paths), vim.log.levels.INFO)
	end)

	callback(true)
end

---Save cache to disk for persistence across sessions
---@private
function M._save_to_disk()
	local data = {
		paths = state.paths,
		last_built = state.last_built,
		scan_roots = config.scan_roots,
		version = 1,
	}

	-- Use pcall to handle JSON encoding errors gracefully
	local ok, json = pcall(vim.json.encode, data)
	if not ok then
		vim.notify("[gopath] Failed to encode cache data", vim.log.levels.ERROR)
		return
	end

	local file = io.open(config.cache_file, "w")
	if not file then
		vim.notify("[gopath] Failed to open cache file for writing", vim.log.levels.ERROR)
		return
	end

	file:write(json)
	file:close()
end

---Load cache from disk
---Called on startup to restore previous session's cache
---@return boolean success True if cache was loaded
function M.load_from_disk()
	local file = io.open(config.cache_file, "r")
	if not file then
		return false -- Cache file doesn't exist (first run)
	end

	local content = file:read("*a")
	file:close()

	-- === Parse JSON ===
	local ok, data = pcall(vim.json.decode, content)
	if not ok or not data then
		vim.notify("[gopath] Failed to parse cache file", vim.log.levels.WARN)
		return false
	end

	-- === Restore State ===
	state.paths = data.paths or {}
	state.last_built = data.last_built

	return true
end

---Search in-memory cache for matching paths
---This is the fast path (< 10ms for 10,000 entries)
---
---Matching strategy:
---  1. Exact tail match (path ends with tail)
---  2. Sequential part match (all tail parts appear in order)
---
---@param tail string Tail of truncated path to search for
---@return string[] matches List of matching absolute paths
function M.search(tail)
	-- === Ensure Cache is Loaded ===
	if #state.paths == 0 and not state.building then
		-- Try to load from disk (might be from previous session)
		M.load_from_disk()
	end

	if #state.paths == 0 then
		return {} -- Cache is empty
	end

	-- === Normalize Tail ===
	-- Convert to lowercase and forward slashes for comparison
	local normalized_tail = tail:gsub("\\", "/"):lower()
	local tail_parts = vim.split(normalized_tail, "/", { trimempty = true })

	local matches = {}

	-- === Search All Cached Paths ===
	for _, path in ipairs(state.paths) do
		local normalized_path = path:gsub("\\", "/"):lower()

		-- === Strategy 1: Exact Tail Match ===
		-- Path ends with the exact tail
		if normalized_path:match(vim.pesc(normalized_tail) .. "$") then
			table.insert(matches, path)

		-- === Strategy 2: Sequential Part Match ===
		-- All tail parts appear in path in order
		elseif #tail_parts > 1 then
			local path_parts = vim.split(normalized_path, "/", { trimempty = true })
			local tail_idx = 1

			for _, part in ipairs(path_parts) do
				if tail_idx <= #tail_parts and part == tail_parts[tail_idx] then
					tail_idx = tail_idx + 1
				end
			end

			-- All tail parts found in sequence
			if tail_idx > #tail_parts then
				table.insert(matches, path)
			end
		end
	end

	return matches
end

---Check if cache needs refresh
---@param max_age_seconds integer|nil Maximum age before refresh (default: 3600)
---@return boolean needs_refresh True if cache is stale
function M.needs_refresh(max_age_seconds)
	max_age_seconds = max_age_seconds or 3600 -- Default: 1 hour

	if not state.last_built then
		return true -- Never built
	end

	local age = os.time() - state.last_built
	return age > max_age_seconds
end

---Start periodic cache refresh in background
---This ensures cache stays reasonably up-to-date during long Neovim sessions
---
---@param interval_seconds integer Refresh interval (default: 600 = 10 minutes)
function M.start_periodic_refresh(interval_seconds)
	interval_seconds = interval_seconds or 600

	---@diagnostic disable-next-line lib.uv
	local timer = uv.new_timer()

	-- Start timer: check every interval, refresh if needed
	timer:start(0, interval_seconds * 1000, function()
		if M.needs_refresh(interval_seconds) and not state.building then
			-- Rebuild cache in background
			M.build_async(function() end)
		end
	end)
end

---Add a directory to scan roots and rebuild cache
---Useful for adding project-specific directories on the fly
---
---@param dir string Directory path to add
---@param rebuild boolean|nil Whether to rebuild cache immediately (default: true)
function M.add_root(dir, rebuild)
	rebuild = rebuild ~= false -- Default: true

	-- Validate directory exists
	if vim.fn.isdirectory(dir) ~= 1 then
		vim.notify(string.format("[gopath] Directory does not exist: %s", dir), vim.log.levels.ERROR)
		return
	end

	-- Check if already in roots
	if vim.tbl_contains(config.scan_roots, dir) then
		vim.notify(string.format("[gopath] Directory already in cache roots: %s", dir), vim.log.levels.WARN)
		return
	end

	-- Add to roots
	table.insert(config.scan_roots, dir)

	vim.notify(string.format("[gopath] Added to cache roots: %s", dir), vim.log.levels.INFO)

	-- Rebuild cache to include new directory
	if rebuild then
		M.build_async(function() end)
	end
end

---Get cache state (for debugging)
---@return table state Current cache state
---@private
function M._get_state()
	return state
end

return M
