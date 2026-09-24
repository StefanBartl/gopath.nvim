---@module 'gopath.resolve_selection'
---@brief Resolve a piece of TEXT directly -- e.g. a partial visual selection.
---@description
--- `gopath.commands.probe_selection` used to send a visual selection straight
--- to tailsearch (filesystem suffix search) -- fine for a plain file path,
--- but tailsearch has no idea what a `$VAR/rest` reference or a URL is, so
--- selecting only PART of one of those never resolved, even though the whole
--- point of a partial selection is "resolve just this much of a longer
--- line". This module tries the recognizers that already work on raw text
--- (`gopath.util.url`'s pure `is_strict_url`/`is_loose_url`/`normalize`, and
--- `gopath.resolvers.common.env_path`'s `resolve_text`) before probe_selection
--- falls back to tailsearch, so a partially selected env-var path or URL
--- resolves the same way a fully-recognized one would.
---
--- Deliberately NOT included: the language-specific/LSP/treesitter pipeline
--- and linepath's whole-line extraction -- both need much more than a bare
--- substring (buffer context, cursor position) to mean anything, and
--- tailsearch's filesystem suffix search already covers "part of a plain
--- file path" well.

local URL = require("gopath.util.url")

local M = {}

---@internal
---@return { enable: boolean, bare_hosts: boolean, schemes: string[]|nil, tlds: string[]|nil }
local function url_options()
  local ok, C = pcall(require, "gopath.config")
  local cfg = ok and C.get().url or nil
  return {
    enable = not cfg or cfg.enable ~= false,
    bare_hosts = not cfg or cfg.bare_hosts ~= false,
    schemes = cfg and cfg.schemes or nil,
    tlds = cfg and cfg.tlds or nil,
  }
end

---@internal
---@param text string
---@return GopathResult|nil
local function try_url(text)
  local opts = url_options()
  if not opts.enable then return nil end

  local strict = URL.is_strict_url(text, opts)
  if not strict and not opts.bare_hosts then return nil end
  if not (strict or URL.is_loose_url(text, opts)) then return nil end

  return {
    language = vim.bo.filetype or "text",
    kind = "url",
    path = URL.normalize(text, opts),
    range = nil,
    chain = nil,
    source = "url",
    confidence = strict and 0.95 or 0.7,
    exists = true,
  }
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
