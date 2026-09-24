---@module 'gopath.resolve_selection'
---@brief Resolve a piece of TEXT directly -- e.g. a partial visual selection.
---@description
--- `gopath.commands.probe_selection` used to send a visual selection straight
--- to tailsearch (filesystem suffix search) -- fine for a plain file path,
--- but tailsearch has no idea what a `$VAR/rest` reference or a URL is, so
--- selecting only PART of one of those never resolved, even though the whole
--- point of a partial selection is "resolve just this much of a longer
--- line". This module tries the recognizers that already work on raw text --
--- `gopath.resolvers.common.url` and `gopath.resolvers.common.env_path`,
--- each exposing a `resolve_text(text)` entry point next to their existing
--- cursor-based `M.resolve()` -- before probe_selection falls back to
--- tailsearch, so a partially selected env-var path or URL resolves the same
--- way a fully-recognized one would.
---
--- Deliberately NOT included: the language-specific/LSP/treesitter pipeline
--- and linepath's whole-line extraction -- both need much more than a bare
--- substring (buffer context, cursor position) to mean anything, and
--- tailsearch's filesystem suffix search already covers "part of a plain
--- file path" well.
---
--- This module only orders the two recognizers; it does not re-implement
--- their matching or GopathResult-building logic.

local M = {}

---@internal
---@param text string
---@return GopathResult|nil
local function try_url(text)
  return require("gopath.resolvers.common.url").resolve_text(text)
end

---@internal
---@param text string
---@return GopathResult|nil
local function try_env(text)
  return require("gopath.resolvers.common.env_path").resolve_text(text)
end

---Try to resolve `text` (an exact substring the caller already knows about
----- typically a trimmed visual selection) directly. nil when none of the
---direct recognizers matched; the caller (`probe_selection`) falls back to
---tailsearch's filesystem suffix search.
---@param text string
---@return GopathResult|nil
function M.resolve_text(text)
  if type(text) ~= "string" or text == "" then return nil end
  return try_url(text) or try_env(text)
end

return M
