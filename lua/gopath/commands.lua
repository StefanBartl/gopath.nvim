---@module 'gopath.commands'
---@brief User-facing commands: resolve & open / copy / debug.
---Handles routing to appropriate opener based on user's chosen mode (edit/split/vsplit/tab).

local RESOLVE = require("gopath.resolve")
local CONFIG = require("gopath.config")

local OP = {
  edit   = require("gopath.open.edit"),
  window = require("gopath.open.window"),
  vsplit = require("gopath.open.vsplit"),
  tab    = require("gopath.open.tab"),
  help   = require("gopath.open.help"),
}

local M = {}

---Open result with appropriate opener based on kind
---@param res GopathResult Resolution result
---@param kind string Opening mode ("edit"|"window"|"vsplit"|"tab")
local function open_for_kind(res, kind)
  -- Special handling for help results
  if res.kind == "help" then
    if kind == "tab" then
      return OP.help.open(res, { target = "tab" })
    elseif kind == "window" or kind == "vsplit" then
      return OP.help.open(res, { target = "window" })
    else
      return OP.help.open(res, { target = "edit" })
    end
  end

  -- Normal file opening
  return OP[kind or "edit"].open(res)
end

---Main command: Resolve and open with specified mode
---This is the primary entry point for all gP, g|, g\, g} mappings
---@param kind string Opening mode ("edit"|"window"|"vsplit"|"tab")
function M.resolve_and_open(kind)
  -- Step 1: Resolve path/symbol under cursor
  local res, err = RESOLVE.resolve_at_cursor({})

  if not res then
    vim.notify("[gopath] no match: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end

  -- Step 2: Check if file exists and try alternate resolution if needed
  local cfg = CONFIG.get()

  if res.exists == false and cfg.alternate and cfg.alternate.enable then
    -- File doesn't exist, try fuzzy alternate resolution
    local alternate = require("gopath.alternate")
    local handled = alternate.try_resolve(res.path, {
      similarity_threshold = cfg.alternate.similarity_threshold or 75,
      open_mode = kind or "edit",  -- Pass opening mode to alternate
    })

    if handled then
      return -- Alternate opened the file with correct mode
    end
  end

  -- Step 3: Open with appropriate opener
  open_for_kind(res, kind or "edit")
end

---Copy location to clipboard (path:line:col format)
function M.resolve_and_copy()
  local res, err = RESOLVE.resolve_at_cursor({})

  if not res then
    vim.notify("[gopath] no match to copy: " .. (err or "unknown"), vim.log.levels.WARN)
    return
  end

  -- Build location string
  local l = res.range and res.range.line or 1
  local c = res.range and res.range.col or 1

  local left
  if res.kind == "help" then
    local subj = res.subject or "?"
    left = ("<help:%s>"):format(subj)
  else
    left = tostring(res.path or "?")
  end

  -- Copy to system clipboard
  vim.fn.setreg("+", ("%s:%d:%d"):format(left, l, c))
  vim.notify("[gopath] copied to clipboard", vim.log.levels.INFO)
end

---Debug command: Show detailed resolution information
function M.debug_under_cursor()
  -- Gather context information
  local chain = nil
  pcall(function()
    chain = require("gopath.resolvers.lua.chain").get_chain_at_cursor()
  end)

  local bind_sz = 0
  local bind_map = {}
  pcall(function()
    bind_map = require("gopath.resolvers.lua.binding_index").get_map()
    for _ in pairs(bind_map) do bind_sz = bind_sz + 1 end
  end)

  local cfile = vim.fn.expand("<cfile>")

  -- Check identifier (for identifier_locator debugging)
  local identifier = nil
  pcall(function()
    local TS = require("gopath.providers.treesitter")
    local node = TS.node_at_cursor()
    if node and node:type() == "identifier" then
      identifier = vim.treesitter.get_node_text(node, 0)
    end
  end)

  -- Check cache status (for truncated paths)
  local cache_info = nil
  pcall(function()
    local cache = require("gopath.truncated.cache")
    cache.load_from_disk()
    local state = cache._get_state()
    cache_info = {
      files = #(state.paths or {}),
      last_built = state.last_built,
      needs_refresh = cache.needs_refresh(),
    }
  end)

  -- Perform resolution
  local res, err = RESOLVE.resolve_at_cursor({})

  -- Display debug information
  print("=== Gopath Debug ===")
  print("  Filetype:", vim.bo.filetype)
  print("  <cfile>:", cfile)
  print("  Identifier:", identifier or "nil")
  print("  Chain:", chain and (chain.base .. " -> " .. table.concat(chain.chain, ".")) or "nil")
  print("  Binding map size:", bind_sz)

  -- Show sample bindings
  if bind_sz > 0 then
    print("  Bindings (sample):")
    local count = 0
    for id, mod in pairs(bind_map) do
      print(string.format("    %s → %s", id, mod))
      count = count + 1
      if count >= 3 then break end
    end
  end

  -- Show cache status
  if cache_info then
    print("  Cache:")
    print("    Files indexed:", cache_info.files)
    print("    Last built:", cache_info.last_built and os.date("%Y-%m-%d %H:%M:%S", cache_info.last_built) or "never")
    print("    Needs refresh:", cache_info.needs_refresh and "yes" or "no")
  end

  -- Show resolution result
  if res then
    print("  Result:")
    print("    language:", res.language)
    print("    kind:", res.kind)
    print("    path:", res.path)
    print("    source:", res.source)
    print("    confidence:", res.confidence)
    print("    exists:", tostring(res.exists))

    if res.range then
      print("    range:")
      print("      line:", res.range.line)
      print("      col:", res.range.col)
    else
      print("    range: nil")
    end
  else
    print("  Result: nil")
    print("  Error:", err or "unknown")
  end
  print("====================")
end

return M
