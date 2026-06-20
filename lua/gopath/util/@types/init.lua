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
-- log.lua

---@alias LogLevel
---| "debug"  # Shown only when dev_mode = true
---| "info"   # Always shown
---| "warn"   # Always shown
---| "error"  # Always shown

return {}
