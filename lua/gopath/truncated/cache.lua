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
local LOG  = require("gopath.util.log")
local uv = vim.loop

---@class CacheConfig
---@field max_depth integer Maximum directory depth to scan
---@field max_concurrency integer Max directories scanned concurrently (bounds open handles)
---@field excluded_dirs string[] Directories to skip during scan
---@field cache_file string Path to persistent cache file
---@field scan_roots string[] Directories/drives to scan

---Default cache configuration
---User can override via gopath.setup({ truncated = { cache_roots = {...} } })
---@type CacheConfig
local config = {
	max_depth = 6, -- Don't descend too deep (performance)

	-- Maximum number of directories scanned concurrently. Bounding this prevents
	-- libuv threadpool / open-file-handle exhaustion (EMFILE) on huge trees.
	max_concurrency = 16,

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
		-- Deliberately conservative: indexing a whole drive (C:\) or the entire
		-- user profile to max_depth on startup produces a huge, slow cache. We
		-- stick to the directories that actually hold openable files for this
		-- editor. Users who need more can pass `truncated.cache_roots`.
		local candidates = {
			vim.fn.getcwd(),                                                       -- project / working directory
			vim.fn.stdpath("config"),                                              -- nvim config (init, lua/, …)
			vim.fn.stdpath("data"),                                                -- plugins (lazy/, …)
			vim.fn.stdpath("cache"),                                               -- runtime/cache files
			vim.fn.systemlist("git rev-parse --show-toplevel 2>/dev/null")[1],     -- git repository root (if in one)
		}
		config.scan_roots = {}
		for _, p in ipairs(candidates) do
			if type(p) == "string" and p ~= "" and vim.fn.isdirectory(p) == 1 then
				table.insert(config.scan_roots, p)
			end
		end
		config.scan_roots = require("lib.lua.tables").dedup_list(config.scan_roots)
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

---Scan a set of roots with bounded concurrency (async, non-blocking).
---
--- A work queue of `{ dir, depth }` items is processed by at most
--- `config.max_concurrency` in-flight `fs_scandir` operations. Subdirectories
--- are pushed back onto the queue instead of recursing immediately, so the
--- number of simultaneously open directory handles stays bounded regardless of
--- tree size. This avoids EMFILE / threadpool starvation on very large trees
--- while still keeping the whole scan off the main loop.
---
---@param roots string[] Root directories to scan
---@param on_done fun(paths: string[]) Called once with every discovered file path
local function scan_roots_bounded(roots, on_done)
	local queue   = {}   -- pending { dir=string, depth=integer } items
	local results = {}   -- accumulated file paths
	local active  = 0    -- in-flight fs_scandir operations
	local qhead   = 1    -- queue read cursor (avoids table.remove shifts)

	for i = 1, #roots do
		queue[#queue + 1] = { dir = roots[i], depth = 0 }
	end

	local pump  -- forward declaration

	---Scan one directory; push child dirs back onto the queue, collect files.
	---@param item { dir:string, depth:integer }
	local function scan_one(item)
		---@diagnostic disable-next-line lib.uv
		uv.fs_scandir(item.dir, function(err, handle)
			if err or not handle then
				active = active - 1
				pump()
				return
			end

			while true do
				---@diagnostic disable-next-line lib.uv
				local name, typ = uv.fs_scandir_next(handle)
				if not name then break end

				local full_path = item.dir .. "/" .. name
				if typ == "file" then
					results[#results + 1] = full_path
				elseif typ == "directory"
					and not is_excluded(name)
					and item.depth < config.max_depth
				then
					queue[#queue + 1] = { dir = full_path, depth = item.depth + 1 }
				end
			end

			active = active - 1
			pump()
		end)
	end

	---Fill available concurrency slots from the queue; finish when fully drained.
	pump = function()
		while active < config.max_concurrency and qhead <= #queue do
			local item = queue[qhead]
			qhead = qhead + 1
			active = active + 1
			scan_one(item)
		end

		if active == 0 and qhead > #queue then
			on_done(results)
		end
	end

	-- Empty input → complete immediately on next tick.
	if #queue == 0 then
		vim.schedule(function() on_done(results) end)
	else
		pump()
	end
end

---Build cache from configured scan roots.
---Non-blocking: runs entirely in the background with bounded concurrency.
---@param callback fun(success: boolean) Called when build completes
function M.build_async(callback)
	-- === Prevent Concurrent Builds ===
	if state.building then
		callback(false)
		return
	end

	-- === Initialize Build ===
	state.building = true
	state.paths = {} -- Clear existing paths

	safe.safe_notify_defer(
		string.format("[gopath] Building cache from %d roots...", #config.scan_roots),
		vim.log.levels.INFO, nil, 50
	)

	-- Keep only roots that actually exist on disk.
	local roots = {}
	for _, root in ipairs(config.scan_roots) do
		if vim.fn.isdirectory(root) == 1 then
			roots[#roots + 1] = root
		end
	end

	-- === Single bounded-concurrency scan across all roots ===
	scan_roots_bounded(roots, function(paths)
		state.paths = paths
		M._finalize_build(callback)
	end)
end

---Finalize cache build (save to disk, update state)
---@param callback fun(success: boolean)
---@private
function M._finalize_build(callback)
	state.last_built = os.time()
	state.building = false

	-- === Save to Disk ===
	M._save_to_disk()

	-- Build completion is reported by the caller (setup / :GopathCacheBuild);
	-- keep this as a dev-only trace to avoid duplicate notifications.
	vim.schedule(function()
		LOG.debug(string.format("Cache built: %d files indexed", #state.paths))
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
		LOG.error("Failed to encode cache data")
		return
	end

	local file = io.open(config.cache_file, "w")
	if not file then
		LOG.error("Failed to open cache file for writing")
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
		LOG.warn("Failed to parse cache file")
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
		LOG.error("Directory does not exist: " .. dir)
		return
	end

	-- Check if already in roots
	if vim.tbl_contains(config.scan_roots, dir) then
		LOG.warn("Directory already in cache roots: " .. dir)
		return
	end

	-- Add to roots
	table.insert(config.scan_roots, dir)

	LOG.info("Added to cache roots: " .. dir)

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
