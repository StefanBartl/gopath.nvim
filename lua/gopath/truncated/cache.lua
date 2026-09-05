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
local LOG = require("gopath.util.log")
local uv = vim.loop

---@class CacheConfig
---@field max_depth? integer Maximum directory depth to scan
---@field max_concurrency? integer Max directories scanned concurrently (bounds open handles)
---@field excluded_dirs? string[] Directories to skip during scan
---@field cache_file? string Path to persistent cache file
---@field scan_roots? string[] Directories/drives to scan

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
---`norm[i]` is the lowercased, forward-slash form of `paths[i]`, precomputed
---once per index rather than per query. `M.search` used to derive it inline for
---every cached path on every lookup — two string allocations × 20k+ paths ×
---every keystroke-triggered resolve. Keep the two arrays index-aligned.
---@type { paths: string[], norm: string[], last_built: integer|nil, building: boolean }
local state = {
  paths = {}, -- All indexed file paths
  norm = {}, -- paths[i] lowercased with "/" separators
  last_built = nil, -- Unix timestamp of last cache build
  building = false, -- Flag to prevent concurrent builds
}

---Rebuild the `norm` mirror of `state.paths`.
---@internal
---@return nil
local function reindex()
  local norm = {}
  local paths = state.paths
  for i = 1, #paths do
    norm[i] = paths[i]:gsub("\\", "/"):lower()
  end
  state.norm = norm
end

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
    -- Git root is resolved by walking up for a `.git` marker (lib.nvim), NOT by
    -- shelling out to `git rev-parse`. The old call was a synchronous subprocess
    -- spawn on the main loop during setup() — expensive on Windows (AV scan on
    -- every spawn) — and its `2>/dev/null` redirect is POSIX shell syntax that
    -- cmd.exe does not understand, so on Windows it also polluted the result.
    local git_root
    do
      local ok, find_root = pcall(require, "lib.nvim.fs.find_root")
      if ok then
        local ok_find, root = pcall(function()
          return find_root({ markers = { ".git" } }).find(vim.fn.getcwd())
        end)
        if ok_find then git_root = root end
      end
    end

    local candidates = {
      vim.fn.getcwd(), -- project / working directory
      vim.fn.stdpath("config"), -- nvim config (init, lua/, …)
      vim.fn.stdpath("data"), -- plugins (lazy/, …)
      vim.fn.stdpath("cache"), -- runtime/cache files
      git_root, -- git repository root (if in one)
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
  if opts.max_depth then config.max_depth = opts.max_depth end

  if opts.excluded_dirs then config.excluded_dirs = opts.excluded_dirs end
end

---Check if directory should be excluded from scan
---@internal
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
---@internal
---@param roots string[] Root directories to scan
---@param on_done fun(paths: string[]) Called once with every discovered file path
local function scan_roots_bounded(roots, on_done)
  local queue = {} -- pending { dir=string, depth=integer } items
  local results = {} -- accumulated file paths
  local active = 0 -- in-flight fs_scandir operations
  local qhead = 1 -- queue read cursor (avoids table.remove shifts)

  for i = 1, #roots do
    queue[#queue + 1] = { dir = roots[i], depth = 0 }
  end

  local pump -- forward declaration

  ---Scan one directory; push child dirs back onto the queue, collect files.
  ---@internal
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
        elseif typ == "directory" and not is_excluded(name) and item.depth < config.max_depth then
          queue[#queue + 1] = { dir = full_path, depth = item.depth + 1 }
        end
      end

      active = active - 1
      pump()
    end)
  end

  ---Fill available concurrency slots from the queue; finish when fully drained.
  ---@internal
  pump = function()
    while active < config.max_concurrency and qhead <= #queue do
      local item = queue[qhead]
      qhead = qhead + 1
      active = active + 1
      scan_one(item)
    end

    if active == 0 and qhead > #queue then on_done(results) end
  end

  -- Empty input → complete immediately on next tick.
  if #queue == 0 then
    vim.schedule(function()
      on_done(results)
    end)
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
  state.norm = {}

  safe.safe_notify_defer(
    string.format("[gopath] Building cache from %d roots...", #config.scan_roots),
    vim.log.levels.INFO,
    nil,
    50
  )

  -- Keep only roots that actually exist on disk.
  local roots = {}
  for _, root in ipairs(config.scan_roots) do
    if vim.fn.isdirectory(root) == 1 then roots[#roots + 1] = root end
  end

  -- === Single bounded-concurrency scan across all roots ===
  scan_roots_bounded(roots, function(paths)
    state.paths = paths
    reindex()
    M._finalize_build(callback)
  end)
end

---Finalize cache build (save to disk, update state)
---
---Reached from `scan_roots_bounded`'s completion callback, which runs inside a
---libuv `fs_scandir` callback — a fast event context where most Vimscript
---functions are forbidden (`vim.fn.mkdir` raises E5560). Everything below
---therefore runs on the main loop via `vim.schedule`.
---@param callback fun(success: boolean)
---@private
function M._finalize_build(callback)
  vim.schedule(function()
    state.last_built = os.time()
    state.building = false

    -- === Save to Disk ===
    M._save_to_disk()

    -- Build completion is reported by the caller (setup / :GopathCacheBuild);
    -- keep this as a dev-only trace to avoid duplicate notifications.
    LOG.debug(string.format("Cache built: %d files indexed", #state.paths))

    callback(true)
  end)
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

  local ok, err = require("lib.nvim.fs.json").write(config.cache_file, data)
  if not ok then LOG.error("Failed to write cache file: " .. tostring(err)) end
end

---Load cache from disk
---Called on startup to restore previous session's cache
---@return boolean success True if cache was loaded
function M.load_from_disk()
  if not require("lib.nvim.fs.is_readable_file")(config.cache_file) then
    return false -- Cache file doesn't exist (first run)
  end

  local data, err = require("lib.nvim.fs.json").read(config.cache_file)
  if not data then
    LOG.warn("Failed to parse cache file: " .. tostring(err))
    return false
  end

  -- === Restore State ===
  -- This file is a persisted snapshot (our own, but possibly stale, from a
  -- crashed/interrupted write, or from an older/incompatible plugin version)
  -- — treat it as untrusted and revalidate every field rather than assigning
  -- it straight into live state. An unvalidated `data.paths` (wrong type, or
  -- containing non-string entries) would otherwise blow up later in
  -- `reindex`/`M.search`, which call `:gsub`/`:sub` on each entry assuming it
  -- is a string.
  local paths = {}
  if type(data.paths) == "table" then
    for _, p in ipairs(data.paths) do
      if type(p) == "string" then paths[#paths + 1] = p end
    end
  end
  state.paths = paths
  state.last_built = (type(data.last_built) == "number") and data.last_built or nil
  reindex()

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

  -- Self-heal if the mirror ever drifts out of sync with `paths`.
  if #state.norm ~= #state.paths then reindex() end

  -- === Normalize Tail ===
  -- Convert to lowercase and forward slashes for comparison
  local normalized_tail = tail:gsub("\\", "/"):lower()
  local tail_parts = vim.split(normalized_tail, "/", { trimempty = true })

  -- Strategy 1 is a plain suffix comparison, not a pattern match. It used to be
  -- `path:match(vim.pesc(tail) .. "$")` — but `vim.pesc` makes the tail a
  -- *literal*, so the anchored pattern was only ever asking "does this path end
  -- with this exact string". `sub(-n) == tail` answers that with a memcmp
  -- instead of starting the pattern engine 20k times per query. Identical
  -- semantics, measurably cheaper on the hot path.
  local tail_len = #normalized_tail
  -- Non-nil only for multi-segment tails; doubles as the Strategy-2 guard below.
  local last_part = (#tail_parts > 1) and tail_parts[#tail_parts] or nil

  local matches = {}
  local paths, norm = state.paths, state.norm

  -- === Search All Cached Paths ===
  for i = 1, #paths do
    local normalized_path = norm[i]

    -- === Strategy 1: Exact Tail Match ===
    -- Path ends with the exact tail
    if #normalized_path >= tail_len and normalized_path:sub(-tail_len) == normalized_tail then
      matches[#matches + 1] = paths[i]

    -- === Strategy 2: Sequential Part Match ===
    -- All tail parts appear in path in order.
    -- Guarded by a plain-substring pre-check on the tail's LAST segment: the
    -- sequential match requires every tail part to appear as a whole path
    -- segment, so a path that doesn't even contain that segment as a substring
    -- can never match. The check allocates nothing, while the split below
    -- allocates a table per path — this prunes nearly all of them.
    elseif last_part and normalized_path:find(last_part, 1, true) then
      local path_parts = vim.split(normalized_path, "/", { trimempty = true })
      local tail_idx = 1

      for _, part in ipairs(path_parts) do
        if tail_idx <= #tail_parts and part == tail_parts[tail_idx] then tail_idx = tail_idx + 1 end
      end

      -- All tail parts found in sequence
      if tail_idx > #tail_parts then matches[#matches + 1] = paths[i] end
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
  local timer = assert(uv.new_timer())

  -- Start timer: check every interval, refresh if needed.
  -- The timer callback is a fast event context, but `build_async` calls
  -- Vimscript functions (`vim.fn.isdirectory`, notifications), so hop onto the
  -- main loop first.
  -- Initial delay = one full interval, NOT 0. With a 0 delay the timer fired
  -- immediately on setup() and — since `needs_refresh(interval)` is true for any
  -- cache older than the interval, which at startup it almost always is —
  -- kicked off a full rebuild right away, on top of the deferred build that
  -- `gopath.init._setup_cache` already schedules. That meant two scans (and two
  -- 2 MB cache writes) during startup.
  timer:start(interval_seconds * 1000, interval_seconds * 1000, function()
    if M.needs_refresh(interval_seconds) and not state.building then
      -- Rebuild cache in background
      vim.schedule(function()
        if state.building then return end
        M.build_async(function() end)
      end)
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
  if rebuild then M.build_async(function() end) end
end

---Get cache state (for debugging)
---@return table state Current cache state
---@private
function M._get_state()
  return state
end

return M
