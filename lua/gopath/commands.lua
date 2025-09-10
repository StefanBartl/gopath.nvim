---@module 'gopath.commands'
---@brief User-facing commands: resolve & open / copy / debug.

local RESOLVE = require("gopath.resolve")
local OP = {
  edit   = require("gopath.open.edit"),
  window = require("gopath.open.window"),
  tab    = require("gopath.open.tab"),
}

local M = {}

--- Resolve and open using a specific target ("edit"|"window"|"tab").
---@param kind "edit"|"window"|"tab"|nil
function M.resolve_and_open(kind)
  local res, err = RESOLVE.resolve_at_cursor({})
  if not res then
    vim.notify("[gopath] no match: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end
  local target = kind or "edit"
  local opener = OP[target]
  if not opener then
    vim.notify("[gopath] invalid target: " .. tostring(kind), vim.log.levels.ERROR)
    return
  end
  opener.open(res)
end

--- Resolve and copy "path:line:col" to clipboard.
function M.resolve_and_copy()
  local res, err = RESOLVE.resolve_at_cursor({})
  if not res then
    vim.notify("[gopath] no match to copy: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end
  local l = res.range and res.range.line or 1
  local c = res.range and res.range.col or 1
  vim.fn.setreg("+", ("%s:%d:%d"):format(res.path, l, c))
  vim.notify("[gopath] copied: " .. res.path .. ":" .. l .. ":" .. c)
end

--- Debug helper: shows chain, binding map size, and a raw resolve.
function M.debug_under_cursor()
  local chain = nil
  local ok_c, chain_mod = pcall(require, "gopath.resolvers.lua.chain")
  if ok_c and chain_mod then
    pcall(function() chain = chain_mod.get_chain_at_cursor() end)
  end
  local bind_sz = 0
  local ok_b, bind_mod = pcall(require, "gopath.resolvers.lua.binding_index")
  if ok_b and bind_mod then
    local map = bind_mod.get_map()
    for _ in pairs(map) do bind_sz = bind_sz + 1 end
  end
  local res, err = RESOLVE.resolve_at_cursor({})
  print("gopath DEBUG:")
  print("  chain:", chain and (chain.base .. " -> " .. table.concat(chain.chain, ".")) or "nil")
  print("  binding_map_size:", bind_sz)
  if res then
    print("  result:", vim.inspect(res))
  else
    print("  result: nil, err: " .. (err or "unknown"))
  end
end

return M
