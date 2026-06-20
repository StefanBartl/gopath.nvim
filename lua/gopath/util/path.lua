---@module 'gopath.util.path'
---@brief Path helpers: join/exists and multi-strategy file searches.
---@description
--- Provides three distinct search strategies used by resolvers:
---   1. `search_in_rtp`        — walks Neovim's runtimepath (with a module-level
---                               cache invalidated when the rtp string changes).
---   2. `search_with_vim_path` — consults &path / suffixesadd (vim's built-in
---                               file-search, good for languages that honour it).
---   3. `search_with_package_path` — uses Lua's own package.searchpath for
---                               resolving standard `require`-style module names.

local M = {}

-- Module-level runtimepath cache.
-- Invalidated whenever vim.o.runtimepath changes (detected by string identity).
local _rtp_str  = nil   ---@type string|nil
local _rtp_list = nil   ---@type string[]|nil

---Return the current runtimepath as a list, rebuilding only when it changed.
---@return string[]
local function get_rtp_list()
  local s = vim.o.runtimepath
  if s ~= _rtp_str then
    _rtp_str  = s
    _rtp_list = vim.split(s, ",", { trimempty = true })
  end
  return _rtp_list
end

---Join path segments, normalising separators to forward-slash.
---@param ... string
---@return string
function M.join(...)
  local parts = { ... }
  for i = 1, #parts do
    local s = parts[i] or ""
    s = s:gsub("[/\\]+", "/")
    if s:sub(-1) == "/" and i < #parts then
      s = s:sub(1, -2)
    end
    parts[i] = s
  end
  return table.concat(parts, "/")
end

---Return true when `p` exists and is a regular file.
---@param p string
---@return boolean
function M.exists(p)
  if not p or p == "" then return false end
  local st = vim.loop.fs_stat(p)
  return st ~= nil and st.type == "file"
end

---Strategy 1: search for `candidates` under every runtimepath entry.
--- For each rtp dir the search order is:
---   <rtp>/<candidate>
---   <rtp>/lua/<candidate>
--- Then falls back to cwd/<candidate> as a last resort.
---@param candidates string[]
---@return string|nil  absolute path of first match
function M.search_in_rtp(candidates)
  if not candidates or #candidates == 0 then return nil end
  local rtp = get_rtp_list()
  for i = 1, #rtp do
    local base = rtp[i]
    for j = 1, #candidates do
      local p = M.join(base, candidates[j])
      if M.exists(p) then return p end
    end
    for j = 1, #candidates do
      local p = M.join(base, "lua", candidates[j])
      if M.exists(p) then return p end
    end
  end
  local cwd = vim.loop.cwd()
  for j = 1, #candidates do
    local p = M.join(cwd, candidates[j])
    if M.exists(p) then return p end
  end
  return nil
end

---Strategy 2: resolve `token` via vim's &path / suffixesadd mechanism.
--- Equivalent to what gf does for plain file paths.
---@param token string
---@return string|nil  absolute path
function M.search_with_vim_path(token)
  if not token or token == "" then return nil end
  if M.exists(token) then
    return vim.fn.fnamemodify(token, ":p")
  end
  local found = vim.fn.findfile(token, vim.o.path)
  if type(found) == "string" and found ~= "" and M.exists(found) then
    return vim.fn.fnamemodify(found, ":p")
  end
  local suffixes = vim.split(vim.o.suffixesadd or "", ",", { trimempty = true })
  for i = 1, #suffixes do
    local cand = token .. suffixes[i]
    local f = vim.fn.findfile(cand, vim.o.path)
    if type(f) == "string" and f ~= "" and M.exists(f) then
      return vim.fn.fnamemodify(f, ":p")
    end
  end
  return nil
end

---Strategy 3: resolve a dotted Lua module name via `package.searchpath`.
--- Useful for modules outside the Neovim runtimepath (e.g. luarocks packages).
---@param module string  Dotted module name, e.g. "a.b.c"
---@return string|nil  absolute path
function M.search_with_package_path(module)
  if type(module) ~= "string" or module == "" then return nil end
  local pattern = package and package.path or nil
  if not pattern or pattern == "" then return nil end
  local path = package.searchpath(module, pattern)
  if type(path) == "string" and M.exists(path) then
    return vim.fn.fnamemodify(path, ":p")
  end
  return nil
end

return M
