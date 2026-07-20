---@meta
---@module 'gopath.util.@types'
---@brief Type definitions for the util subsystem.

-- #####################################################################
-- location.lua

---@class ParsedLocation
--- Result of `location.parse_location`.
---@field path string       Raw path portion (may still contain the original ellipsis / quotes stripped by caller)
---@field line integer|nil  1-based line number, or nil if the string had no location suffix
---@field col  integer|nil  1-based column number, or nil if the string had no column suffix

-- #####################################################################
-- path.lua

---@class GopathRtpIndexEntry
--- One runtimepath entry, with the names present at its two search roots.
--- `root`/`lua` are nil when that directory does not exist or is unreadable,
--- which is distinct from an existing-but-empty directory.
---@field dir  string                  Absolute runtimepath entry
---@field root table<string, true>|nil Names directly inside `<dir>/`
---@field lua  table<string, true>|nil Names directly inside `<dir>/lua/`

-- #####################################################################
-- log.lua

---@alias LogLevel
---| "debug"  # Shown only when dev_mode = true
---| "info"   # Always shown
---| "warn"   # Always shown
---| "error"  # Always shown

return {}
