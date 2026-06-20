---@meta
---@module 'gopath.alternate.@types'
---@brief Type definitions for the alternate-resolution subsystem.

-- #####################################################################
-- init.lua / try_resolve

---@class AlternateMatch
--- One candidate returned by the similarity search.
---@field path       string   Absolute path to the candidate file
---@field filename   string   Basename of the candidate (e.g. "foo.lua")
---@field similarity number   0–100 similarity score against the target filename

---@class AlternateOpts
--- Options accepted by `alternate.try_resolve` and `alternate.try_resolve_with_matches`.
---@field open_cmd            string       Ex command used to open the file ("edit"|"split"|"vsplit"|"tabedit")
---@field line                integer|nil  1-based line to jump to after opening
---@field col                 integer|nil  1-based column to jump to after opening
---@field similarity_threshold number|nil  Minimum score to include a candidate (default 75)

-- #####################################################################
-- ui.lua

---@class AlternateSelectOpts
--- Options forwarded from `try_resolve` to `ui.present_selection`.
---@field open_cmd string      Ex command for opening ("edit"|"split"|"vsplit"|"tabedit")
---@field line     integer|nil 1-based line to jump to after opening
---@field col      integer|nil 1-based column to jump to after opening

return {}
