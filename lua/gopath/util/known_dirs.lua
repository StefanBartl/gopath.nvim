---@module 'gopath.util.known_dirs'
---@brief Resolve `env_variable_resolution.shorten_known_dirs` through lib.nvim's root registry.
---@description
--- A "known dir" is a directory gopath can locate on its own at runtime
--- without requiring a real environment variable to be set for it -- e.g.
--- `vim.fn.stdpath("config")` for the running Neovim's own config directory.
--- An entry is either a path string, or a zero-arg function computing one
--- (needed for anything only knowable once Neovim is running, like stdpath()).
--- Shared by the forward resolver (`env_path`, expanding `$VAR` while
--- navigating) and the reverse one (`env_shorten`, rewriting an absolute path
--- on the current line back to `$VAR`).
---
--- The entries are gopath's own roots: they go into `lib.nvim.fs.roots` per
--- call (`opts.extra`), so nobody else sees them, and the registry decides
--- what an entry's value means -- a leading `~` / `$VAR` is expanded, a
--- relative value, the filesystem root or a bare drive is refused, separators
--- become `/` and a trailing one is dropped. A root the user configured in the
--- registry's `setup({ extra = ... })` under the same name wins.

local roots = require("lib.nvim.fs.roots")
local is_windows = require("lib.nvim.cross.platform.is_windows")

local M = {}

---Comparison key of a root name: environment names are case-insensitive on Windows.
---@param name string
---@return string
local function key(name)
  return is_windows() and name:upper() or name
end

---Every entry of `known` that resolves to a usable root, as `{ var, dir }`.
---`dir` is absolute, `/`-separated and without a trailing slash. An entry that
---raises, returns nothing, or is refused by the registry is left out.
---@param known table<string, string|(fun(): string?)>|nil
---@return { var: string, dir: string }[]
function M.pairs(known)
  if type(known) ~= "table" or next(known) == nil then return {} end
  local wanted = {}
  for name in pairs(known) do
    if type(name) == "string" then wanted[key(name)] = true end
  end
  local out = {}
  for _, r in ipairs(roots.roots({ extra = known })) do
    if wanted[key(r.name)] then out[#out + 1] = { var = r.name, dir = r.root } end
  end
  return out
end

---The root the entry `name` of `known` resolves to, or nil.
---@param known table<string, string|(fun(): string?)>|nil
---@param name string
---@return string|nil
function M.lookup(known, name)
  if type(known) ~= "table" or known[name] == nil then return nil end
  local hit = M.pairs({ [name] = known[name] })[1]
  return hit and hit.dir or nil
end

return M
