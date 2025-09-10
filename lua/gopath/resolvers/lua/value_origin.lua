---@module 'gopath.resolvers.lua.value_origin'
---@brief From a cursor chain like `cfg.foo` resolve to initializer location in module/current file.

local CHN  = require("gopath.resolvers.lua.chain")
local BIX  = require("gopath.resolvers.lua.binding_index")
local ALX  = require("gopath.resolvers.lua.alias_index")
local TLOC = require("gopath.resolvers.lua.table_locator")
local PATH = require("gopath.util.path")

local M = {}

local function split_by_dot(s)
  local t = {}
  for p in s:gmatch("[^%.]+") do t[#t+1] = p end
  return t
end

-- Resolve base identifier to either:
--  a) { kind="module", module="x.y", extra_chain="cfg.highlight" }
--  b) { kind="current", base="M",   extra_chain="cfg.highlight" }
local function resolve_base(base_id, initial_chain, bind_map, alias_map)
  local chain_suffix = initial_chain and table.concat(initial_chain, ".") or ""
  local current = base_id
  local suffix = chain_suffix

  -- First check direct binding "local id = require 'mod'"
  local be = bind_map[current]
  if be then
    return { kind = "module", module = be, extra_chain = suffix }
  end

  local guard = 0
  while guard < 32 and alias_map[current] do
    guard = guard + 1
    local entry = alias_map[current]
    if entry.kind == "require" and entry.module then
      return { kind = "module", module = entry.module, extra_chain = suffix }
    elseif entry.kind == "chain" and entry.chain then
      -- entry.chain might be "C.cfg.highlight" or "M"
      local parts = split_by_dot(entry.chain)
      if #parts == 0 then break end
      local head = parts[1]
      if #parts > 1 then
        -- prepend remaining chain before our suffix
        local rest = {}
        for i = 2, #parts do rest[#rest+1] = parts[i] end
        suffix = table.concat(rest, ".") .. (suffix ~= "" and "." .. suffix or "")
      end
      current = head
    elseif entry.kind == "id" and entry.id then
      current = entry.id
    else
      break
    end
  end

  -- If base resolves to M (same file table), we treat it as current file.
  if current == "M" then
    return { kind = "current", base = "M", extra_chain = suffix }
  end

  -- As a last resort: if `current` is another id bound to require via bind_map.
  local be2 = bind_map[current]
  if be2 then
    return { kind = "module", module = be2, extra_chain = suffix }
  end

  return nil
end

---@return GopathResult|nil
function M.resolve()
  local chain = CHN.get_chain_at_cursor()
  if not chain then return nil end

  local bind_map  = BIX.get_map()
  local alias_map = ALX.get_map()
  local base_res  = resolve_base(chain.base, chain.chain, bind_map, alias_map)
  if not base_res then return nil end

  -- Last segment we try to land on (initializer key)
  local last_key = (#chain.chain > 0) and chain.chain[#chain.chain] or nil

  if base_res.kind == "module" then
    local rel = base_res.module:gsub("%.", "/")
    local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" }) or PATH.search_with_package_path(base_res.module)
    if not abs then return nil end
    local full_chain = "M" .. (base_res.extra_chain ~= "" and "." .. base_res.extra_chain or "")
    local hit = TLOC.locate(abs, full_chain, last_key)  -- We assume module returns/exports M
    if hit then
      return {
        language   = "lua",
        kind       = last_key and "field" or "table",
        path       = hit.path,
        range      = { line = hit.key_line or hit.tbl_start or 1, col = (hit.key_col or 1) },
        chain      = chain.chain,
        source     = "treesitter",
        confidence = last_key and 0.85 or 0.75,
      }
    end
    return {
      language   = "lua",
      kind       = "module",
      path       = abs,
      range      = nil,
      chain      = chain.chain,
      source     = "treesitter",
      confidence = 0.5,
    }
  end

  if base_res.kind == "current" then
    local abs = vim.api.nvim_buf_get_name(0)
    if type(abs) ~= "string" or abs == "" then return nil end
    local full_chain = "M" .. (base_res.extra_chain ~= "" and "." .. base_res.extra_chain or "")
    local hit = TLOC.locate(abs, full_chain, last_key)
    if hit then
      return {
        language   = "lua",
        kind       = last_key and "field" or "table",
        path       = hit.path,
        range      = { line = hit.key_line or hit.tbl_start or 1, col = (hit.key_col or 1) },
        chain      = chain.chain,
        source     = "treesitter",
        confidence = last_key and 0.9 or 0.8,
      }
    end
  end

  return nil
end

return M

