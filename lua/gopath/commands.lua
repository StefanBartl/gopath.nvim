---@module 'gopath.commands'
--- User-facing commands: resolve & open / copy / debug.

local RESOLVE = require("gopath.resolve")
local CONFIG = require("gopath.config")

local OP = {
  edit   = require("gopath.open.edit"),
  window = require("gopath.open.window"),
  vsplit = require("gopath.open.vsplit"), -- NEW
  tab    = require("gopath.open.tab"),
  help   = require("gopath.open.help"),
}

local M = {}

local function open_for_kind(res, kind)
  if res.kind == "help" then
    if kind == "tab" then
      return OP.help.open(res, { target = "tab" })
    elseif kind == "window" or kind == "vsplit" then
      return OP.help.open(res, { target = "window" })
    else
      return OP.help.open(res, { target = "edit" })
    end
  end

  return OP[kind or "edit"].open(res)
end

function M.resolve_and_open(kind)
  local res, err = RESOLVE.resolve_at_cursor({})

  if not res then
    vim.notify("[gopath] no match: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end

  -- Check if file exists and try alternate resolution if needed
  local cfg = CONFIG.get()

  if res.exists == false and cfg.alternate and cfg.alternate.enable then
    local alternate = require("gopath.alternate")
    local handled = alternate.try_resolve(res.path, {
      similarity_threshold = cfg.alternate.similarity_threshold or 75,
    })

    if handled then
      return -- Alternate opened the file
    end
  end

  open_for_kind(res, kind or "edit")
end

function M.resolve_and_copy()
  local res, err = RESOLVE.resolve_at_cursor({})

  if not res then
    vim.notify("[gopath] no match to copy: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end

  local l = res.range and res.range.line or 1
  local c = res.range and res.range.col or 1

  local left
  if res.kind == "help" then
    local subj = res.subject or "?"
    left = ("<help:%s>"):format(subj)
  else
    left = tostring(res.path or "?")
  end

  vim.fn.setreg("+", ("%s:%d:%d"):format(left, l, c))
  vim.notify("[gopath] copied to clipboard", vim.log.levels.INFO)
end

function M.debug_under_cursor()
  local chain = nil
  pcall(function()
    chain = require("gopath.resolvers.lua.chain").get_chain_at_cursor()
  end)

  local bind_sz = 0
  pcall(function()
    local map = require("gopath.resolvers.lua.binding_index").get_map()
    for _ in pairs(map) do bind_sz = bind_sz + 1 end
  end)

  local res, err = RESOLVE.resolve_at_cursor({})

  print("=== Gopath Debug ===")
  print("  Filetype:", vim.bo.filetype)
  print("  Chain:", chain and (chain.base .. " -> " .. table.concat(chain.chain, ".")) or "nil")
  print("  Binding map size:", bind_sz)

  if res then
    print("  Result:", vim.inspect(res))
  else
    print("  Result: nil")
    print("  Error:", err or "unknown")
  end
  print("====================")
end

return M
