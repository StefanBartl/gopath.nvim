---@meta
---@module 'gopath.truncated.@types'
---@brief Type definitions for the truncated-path resolution subsystem.

-- #####################################################################
-- init.lua

---@class TruncatedResolveOpts
--- Options accepted by `truncated.try_resolve`.
---@field use_cache boolean|nil  Whether to consult the in-memory cache first (default true)
---@field open_cmd  string|nil   Ex command for opening the resolved file (default "edit")

-- #####################################################################
-- cache.lua

---@class TruncatedCacheState
--- Internal state of the on-disk and in-memory path cache.
---@field paths      string[]     Absolute file paths indexed during the last build
---@field last_built integer|nil  `os.time()` value when the cache was last successfully built
---@field building   boolean      True while an async build is in progress

-- #####################################################################
-- finder.lua

---@class TruncatedFinderResult
--- Single result returned by the live filesystem search.
---@field path string  Absolute path to the matching file

return {}
