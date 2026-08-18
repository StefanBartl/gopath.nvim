---@module 'gopath.resolvers.common.url'
---@brief Resolve the URL under the cursor into an openable GopathResult.
---@description
--- Language-agnostic resolver with two entry points that sit at different
--- places in `gopath.resolve`:
---
---   • `M.resolve_strict()` runs near the top of the pipeline. It only fires on
---     an explicit scheme or a `www.` prefix — forms no filesystem path can be
---     confused with — so pre-empting the file resolvers is safe.
---
---   • `M.resolve_loose()` runs just before the filetoken fallback, after every
---     file resolver has already failed. It accepts bare hosts with a known TLD
---     (`github.com/neovim/neovim`) and scp-style git remotes
---     (`git@github.com:foo/bar.git`), which genuinely can collide with
---     filenames — hence the late position: a real file always wins.
---
--- The returned result carries `kind = "url"` and `exists = true`, which keeps
--- it out of the create-on-missing flow (`gopath.create`) and routes it to
--- `gopath.external` in `gopath.open`.

local URL = require("gopath.util.url")

local M = {}

---Effective `config.url` options, with the plugin defaults applied.
---@private
---@return { enable: boolean, bare_hosts: boolean, schemes: string[]|nil, tlds: string[]|nil }
local function options()
  local ok, C = pcall(require, "gopath.config")
  local cfg = ok and C.get().url or nil
  return {
    enable = not cfg or cfg.enable ~= false,
    bare_hosts = not cfg or cfg.bare_hosts ~= false,
    schemes = cfg and cfg.schemes or nil,
    tlds = cfg and cfg.tlds or nil,
  }
end

---@private
---@param raw string
---@param opts GopathUrlOpts
---@param source GopathSource
---@param confidence number
---@return GopathResult
local function result(raw, opts, source, confidence)
  return {
    language = vim.bo.filetype or "text",
    kind = "url",
    path = URL.normalize(raw, opts),
    range = nil,
    chain = nil,
    source = source,
    confidence = confidence,
    exists = true,
  }
end

---Explicit-scheme / `www.` URLs. Safe to run before the file resolvers.
---@return GopathResult|nil
function M.resolve_strict()
  local opts = options()
  if not opts.enable then return nil end

  local raw = URL.extract_at_cursor("strict", opts)
  if not raw then return nil end
  return result(raw, opts, "url", 0.95)
end

---Scheme-less hosts and scp-style git remotes. Must run only after the file
---resolvers have failed, so that `notes.info` on disk still opens as a file.
---@return GopathResult|nil
function M.resolve_loose()
  local opts = options()
  if not opts.enable or not opts.bare_hosts then return nil end

  local raw = URL.extract_at_cursor("loose", opts)
  if not raw then return nil end
  return result(raw, opts, "url", 0.7)
end

---Resolver-interface entry point (strict pass).
---@return GopathResult|nil
function M.resolve()
  return M.resolve_strict()
end

return M
