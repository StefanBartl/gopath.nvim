---@module 'gopath.resolvers.lua.binding_index'
---@brief Map identifiers to modules: `local id = require("mod")` and `id = require "mod"`.
---@description
--- The cache used to be `setmetatable({}, { __mode = "k" })` on the
--- assumption that a weak-keyed table would drop entries for deleted
--- buffers on its own. `bufnr` is a plain Lua number, though, and numbers
--- are not a collectible type -- `{__mode = "k"}` only ever applies to
--- table/function/userdata/thread keys, so that never actually happened:
--- every buffer this module ever saw stayed cached for the life of the
--- session. A `BufDelete`/`BufWipeout` autocmd now does the real cleanup.
--- Same fix as the sibling `alias_index.lua`.

local autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

---@class _BindingCache
---@field tick integer
---@field map table<string,string>

local cache = {} -- bufnr -> _BindingCache, cleared per-entry on BufDelete/BufWipeout below

---Current changedtick of `buf`, used to invalidate the binding cache.
---@internal
---@param buf integer
---@return integer
local function cur_tick(buf)
  return vim.api.nvim_buf_get_changedtick(buf)
end

---Scan every line of `buf` and rebuild the identifier -> module map.
---@internal
---@param buf integer
---@return table<string,string>
local function rebuild(buf)
  local n = vim.api.nvim_buf_line_count(buf)
  local map = {}
  for i = 1, n do
    local s = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""
    -- local id = require "mod"
    local id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
    if id and mod then
      map[id] = mod
      goto continue
    end
    id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
    if id and mod then
      map[id] = mod
      goto continue
    end
    -- id = require "mod" (non-local; allow it)
    id, mod = s:match("^%s*([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
    if id and mod then
      map[id] = mod
      goto continue
    end
    id, mod = s:match("^%s*([%w_]+)%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
    if id and mod then
      map[id] = mod
      goto continue
    end
    ::continue::
  end
  return map
end

--- Get identifier->module map for the current buffer with changedtick cache.
---@return table<string,string>
function M.get_map()
  local buf = vim.api.nvim_get_current_buf()
  local entry = cache[buf]
  local tick = cur_tick(buf)
  if entry and entry.tick == tick then return entry.map end
  local map = rebuild(buf)
  cache[buf] = { tick = tick, map = map }
  return map
end

autocmd.create(
  { "BufDelete", "BufWipeout" },
  function(args)
    cache[args.buf] = nil
  end,
  { desc = "gopath.resolvers.lua.binding_index: drop the cached binding map for a deleted buffer" }
)

return M
