---@module 'gopath.commands'
---@brief User-facing commands: resolve & open / copy / debug / probe.
---Handles routing to appropriate opener based on user's chosen mode (edit/split/vsplit/tab).

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

---Open a resolved result, applying the fuzzy-alternate and nearest-folder
---fallbacks when the file does not exist.
---@private
---@param res GopathResult
---@param kind string
local function finish_open(res, kind)
  local cfg = CONFIG.get()

  if res.exists == false and cfg.alternate and cfg.alternate.enable then
    -- Try fuzzy alternate resolution (Levenshtein similarity in same dir)
    local alternate = require("gopath.alternate")
    local handled = alternate.try_resolve(res.path, {
      similarity_threshold = cfg.alternate.similarity_threshold or 75,
      open_mode = kind or "edit",
    })
    if handled then return end

    -- Fuzzy alternate failed → try nearest existing ancestor directory
    if M.try_nearest_folder(res.path) then return end
  end

  open_for_kind(res, kind or "edit")
end

---Resolve and open with the specified window mode.
---
---The synchronous pipeline only consults instant sources (help, env, rtp, and
---the in-memory truncated-path cache). When it cannot find an existing file,
---the expensive filesystem search runs ASYNCHRONOUSLY so the UI never freezes:
---a "Dateisuche läuft…" message is shown and the buffer opens once a match is
---found.
---@param kind string  "edit"|"window"|"vsplit"|"tab"
function M.resolve_and_open(kind)
  kind = kind or "edit"
  local res, err = RESOLVE.resolve_at_cursor({})

  -- Fast path: an existing file was resolved instantly (help, env, rtp, cache…).
  if res and res.exists ~= false then
    return finish_open(res, kind)
  end

  -- Nothing concrete yet → try an async live filesystem search before giving up.
  local cfg    = CONFIG.get()
  local ts_cfg = cfg.tailsearch or {}
  if ts_cfg.enable == false then
    if res then return finish_open(res, kind) end
    LOG.warn("no match: " .. (err or "unknown"))
    return
  end

  local TS = require("gopath.resolvers.common.tailsearch")

  -- Derive a search tail (+ line/col) from the speculative result or <cfile>.
  local tail, line, col
  if res and res.path and res.path ~= "" then
    tail = TS.sanitize(res.path)
    line = res.range and res.range.line
    col  = res.range and res.range.col
  else
    local cfile = vim.fn.expand("<cfile>")
    if type(cfile) == "string" and cfile ~= "" then
      tail, line, col = TS.sanitize(cfile)
    end
  end

  if not tail or tail == "" then
    if res then return finish_open(res, kind) end
    LOG.warn("no match: " .. (err or "unknown"))
    return
  end

  TS.resolve_async(tail, {
    roots          = ts_cfg.roots,
    limit          = ts_cfg.limit or 100,
    max_components = ts_cfg.max_components or 6,
    line           = line,
    col            = col,
  }, function(found)
    vim.schedule(function()
      if found then
        return finish_open(found, kind)
      end
      -- Live search missed → fall back to whatever the sync pass produced
      -- (drives the alternate / nearest-folder fallbacks on the original path).
      if res then return finish_open(res, kind) end
      LOG.warn("no match for '" .. tail .. "'")
    end)
  end, function()
    -- on_live_start: only fires when the slow filesystem walk actually begins.
    vim.notify("[gopath] Dateisuche läuft…", vim.log.levels.INFO)
  end)
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

-- ── Visual selection helpers ─────────────────────────────────────────────────

---Read visual selection (single line) or nil if not in visual mode.
---@return string|nil
local function get_visual_selection()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\022" then return nil end
  ---@diagnostic disable-next-line: deprecated
  local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
  ---@diagnostic disable-next-line: deprecated
  local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
  if srow == 0 or erow == 0 then return nil end
  local line = vim.api.nvim_buf_get_lines(0, srow - 1, srow, false)[1] or ""
  if srow ~= erow then return line:match("%S") and line or nil end
  local i = math.min(scol + 1, #line + 1)
  local j = math.min(ecol + 1, #line + 1)
  if j < i then i, j = j, i end
  local slice = line:sub(i, j):gsub("^%s+", ""):gsub("%s+$", "")
  return slice ~= "" and slice or nil
end

---Get a path-ish token in normal mode (<cfile>, then <cword>).
---@return string|nil
local function get_normal_token()
  local tok = vim.fn.expand("<cfile>")
  if type(tok) == "string" and tok ~= "" then return tok end
  tok = vim.fn.expand("<cword>")
  return (type(tok) == "string" and tok ~= "") and tok or nil
end

-- ── Probe command (pathprobe strategy) ───────────────────────────────────────

---Probe: resolve the path under cursor / in visual selection using suffix-based
---filesystem search.  Falls back to vim.ui.select when multiple matches found.
---@param opts { open_cmd?: string, ask?: boolean, roots?: string[], max_components?: integer }|nil
function M.probe_selection(opts)
  opts = opts or {}
  local open_cmd = opts.open_cmd or "edit"

  local raw = get_visual_selection() or get_normal_token()
  if not raw then
    vim.notify("[gopath] No path-like token under cursor / in selection", vim.log.levels.WARN)
    return
  end

  local cfg    = CONFIG.get()
  local ts_cfg = cfg.tailsearch or {}
  local TS     = require("gopath.resolvers.common.tailsearch")

  TS.probe(raw, {
    roots          = opts.roots          or ts_cfg.roots,
    max_components = opts.max_components or ts_cfg.max_components or 6,
    limit          = ts_cfg.limit        or 100,
    ask            = opts.ask ~= false and ts_cfg.ask_on_ambiguous ~= false,
  }, function(res)
    if not res then
      vim.notify("[gopath] probe: no match found for '" .. raw .. "'", vim.log.levels.WARN)
      return
    end
    open_for_kind(res, open_cmd == "vsplit" and "vsplit"
                     or open_cmd == "split"  and "window"
                     or open_cmd == "tab"    and "tab"
                     or "edit")
  end)
end

-- ── Nearest-folder fallback ───────────────────────────────────────────────────

---When exact file resolution and fuzzy alternate both fail, try to open the
---nearest existing ancestor directory segment.
---@param path string  the unresolved path
---@return boolean  true if an existing dir was found and opened
function M.try_nearest_folder(path)
  if not path or path == "" then return false end
  local norm = (vim.fs.normalize and vim.fs.normalize(path)) or path
  local segs = {}
  for s in norm:gmatch("[^/\\]+") do segs[#segs + 1] = s end

  local uv = vim.uv or vim.loop
  for i = #segs, 1, -1 do
    local candidate = table.concat(segs, "/", 1, i)
    local cwd = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    local try_paths = { candidate, "/" .. candidate, cwd .. "/" .. candidate }

    for _, p in ipairs(try_paths) do
      local ok_norm, pn = pcall(vim.fs.normalize, p)
      if ok_norm then
        local st = uv.fs_stat(pn)
        if st and st.type == "directory" then
          vim.cmd.edit(vim.fn.fnameescape(pn))
          vim.notify("[gopath] Opened nearest dir: " .. pn, vim.log.levels.INFO)
          return true
        end
      end
    end
  end
  return false
end

-- ─── Debug command ────────────────────────────────────────────────────────────

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
