---@module 'gopath.commands'
---@brief User-facing commands: resolve & open / copy / debug.
---@description
--- Routes resolved results to the appropriate opener (edit/split/vsplit/tab).
--- Debug output is collected by `collect_debug_info`, formatted by
--- `format_debug_lines` and emitted via vim.notify — never via print().

local RESOLVE = require("gopath.resolve")
local CONFIG  = require("gopath.config")
local OPEN    = require("gopath.open")
local HELP    = require("gopath.open.help")
local LOG     = require("gopath.util.log")

local M = {}

---@type table<string, string>
local KIND_TO_CMD = {
  edit   = "edit",
  window = "split",
  vsplit = "vsplit",
  tab    = "tabedit",
}

---@private
---@param res GopathResult
---@param kind string
local function open_for_kind(res, kind)
  if res.kind == "help" then
    local target = (kind == "tab" and "tab")
        or ((kind == "window" or kind == "vsplit") and "window")
        or "edit"
    return HELP.open(res, { target = target })
  end
  return OPEN.open(res, kind or "edit")
end

---Resolve and open with the specified window mode.
---@param kind string  "edit"|"window"|"vsplit"|"tab"
function M.resolve_and_open(kind)
  local res, err = RESOLVE.resolve_at_cursor({})
  if not res then
    LOG.warn("no match: " .. (err or "unknown"))
    return
  end

  local cfg      = CONFIG.get()
  local open_cmd = KIND_TO_CMD[kind or "edit"] or "edit"

  if res.exists == false then
    -- Truncated path handling
    if cfg.truncated and cfg.truncated.enable then
      local ok_tok, token = pcall(function()
        return require("gopath.providers.token").get_token()
      end)
      if ok_tok and token then
        local truncated = require("gopath.truncated")
        if truncated.is_truncated(token) then
          local handled = truncated.try_resolve(token, {
            use_cache = cfg.truncated.use_cache ~= false,
            open_cmd  = open_cmd,
          })
          if handled then return end
        end
      end
    end

    -- Fuzzy alternate resolution
    if cfg.alternate and cfg.alternate.enable then
      local alternate = require("gopath.alternate")
      local handled   = alternate.try_resolve(res.path, {
        similarity_threshold = cfg.alternate.similarity_threshold or 75,
        open_cmd             = open_cmd,
        line                 = res.range and res.range.line or nil,
        col                  = res.range and res.range.col  or nil,
      })
      if handled then return end
    end
  end

  open_for_kind(res, kind or "edit")
end

---Copy the resolved location to the system clipboard as "path:line:col".
function M.resolve_and_copy()
  local res, err = RESOLVE.resolve_at_cursor({})
  if not res then
    LOG.warn("no match to copy: " .. (err or "unknown"))
    return
  end

  local l = res.range and res.range.line or 1
  local c = res.range and res.range.col  or 1

  local left
  if res.kind == "help" then
    left = ("<help:%s>"):format(res.subject or "?")
  else
    left = tostring(res.path or "?")
  end

  vim.fn.setreg("+", ("%s:%d:%d"):format(left, l, c))
  LOG.info("copied to clipboard")
end

-- ─── Debug command helpers ────────────────────────────────────────────────────

---@class GopathDebugInfo
---@field filetype   string
---@field cfile      string
---@field chain      LuaChainInfo|nil
---@field bind_sz    integer
---@field bind_map   LuaBindingMap
---@field identifier string|nil
---@field cache_info { files:integer, last_built:integer|nil, needs_refresh:boolean }|nil
---@field result     GopathResult|nil
---@field error      string|nil

---@private
---@return GopathDebugInfo
local function collect_debug_info()
  local info = {
    filetype   = vim.bo.filetype or "?",
    cfile      = vim.fn.expand("<cfile>"),
    chain      = nil,
    bind_sz    = 0,
    bind_map   = {},
    identifier = nil,
    cache_info = nil,
    result     = nil,
    error      = nil,
  }

  pcall(function()
    info.chain = require("gopath.resolvers.lua.chain").get_chain_at_cursor()
  end)

  pcall(function()
    info.bind_map = require("gopath.resolvers.lua.binding_index").get_map()
    for _ in pairs(info.bind_map) do info.bind_sz = info.bind_sz + 1 end
  end)

  pcall(function()
    local TS   = require("gopath.providers.treesitter")
    local node = TS.node_at_cursor()
    if node and node:type() == "identifier" then
      info.identifier = vim.treesitter.get_node_text(node, 0)
    end
  end)

  pcall(function()
    local cache = require("gopath.truncated.cache")
    cache.load_from_disk()
    local state = cache._get_state()
    info.cache_info = {
      files        = #(state.paths or {}),
      last_built   = state.last_built,
      needs_refresh = cache.needs_refresh(),
    }
  end)

  info.result, info.error = RESOLVE.resolve_at_cursor({})
  return info
end

---@private
---@param info GopathDebugInfo
---@return string[]
local function format_debug_lines(info)
  local t = {
    "=== Gopath Debug ===",
    "  Filetype:   " .. info.filetype,
    "  <cfile>:    " .. info.cfile,
    "  Identifier: " .. (info.identifier or "nil"),
  }

  if info.chain then
    t[#t+1] = "  Chain: " .. info.chain.base
        .. " -> " .. table.concat(info.chain.chain, ".")
  else
    t[#t+1] = "  Chain: nil"
  end

  t[#t+1] = "  Binding map size: " .. info.bind_sz
  if info.bind_sz > 0 then
    t[#t+1] = "  Bindings (sample):"
    local n = 0
    for id, mod in pairs(info.bind_map) do
      t[#t+1] = string.format("    %s -> %s", id, mod)
      n = n + 1
      if n >= 3 then break end
    end
  end

  if info.cache_info then
    local ci = info.cache_info
    t[#t+1] = "  Cache:"
    t[#t+1] = "    Files indexed:  " .. ci.files
    t[#t+1] = "    Last built:     "
        .. (ci.last_built and os.date("%Y-%m-%d %H:%M:%S", ci.last_built) or "never")
    t[#t+1] = "    Needs refresh:  " .. (ci.needs_refresh and "yes" or "no")
  end

  if info.result then
    local res = info.result
    t[#t+1] = "  Result:"
    t[#t+1] = "    language:   " .. (res.language or "?")
    t[#t+1] = "    kind:       " .. (res.kind     or "?")
    t[#t+1] = "    path:       " .. tostring(res.path)
    t[#t+1] = "    source:     " .. (res.source   or "?")
    t[#t+1] = "    confidence: " .. tostring(res.confidence)
    t[#t+1] = "    exists:     " .. tostring(res.exists)
    if res.range then
      t[#t+1] = "    range:      line=" .. tostring(res.range.line)
                   .. "  col=" .. tostring(res.range.col)
    else
      t[#t+1] = "    range:      nil"
    end
  else
    t[#t+1] = "  Result: nil"
    t[#t+1] = "  Error:  " .. (info.error or "unknown")
  end

  t[#t+1] = "===================="
  return t
end

---Show detailed resolution information via vim.notify.
function M.debug_under_cursor()
  local info  = collect_debug_info()
  local lines = format_debug_lines(info)
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

return M
