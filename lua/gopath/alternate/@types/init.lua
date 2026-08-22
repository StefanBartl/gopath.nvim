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
---@field mode                 GopathOpenMode|nil  Window mode for the open ("edit"|"window"|"vsplit"|"tab"); default "edit"
---@field range                GopathRange|nil     Line/col to jump to after opening (truncated paths carry one)
---@field similarity_threshold number|nil          Minimum score to include a candidate (default 75)

-- #####################################################################
-- ui.lua

---@class AlternateSelectOpts
--- Options forwarded from `try_resolve` to `ui.present_selection`.
---@field on_choice fun(match: AlternateMatch|nil): nil
--- Called exactly once with the chosen candidate, or `nil` when the user
--- dismissed the picker. Callback-based because the picker may be asynchronous.

return {}
