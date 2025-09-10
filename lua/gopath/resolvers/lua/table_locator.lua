---@module 'gopath.resolvers.lua.table_locator'
---@brief Locate a table (and optionally a key initializer) by a dotted base chain in a Lua file.

-- local PATH = require("gopath.util.path")

local M = {}

-- Split "M.cfg.highlight" -> { "M", "cfg", "highlight" }
local function split_chain(chain)
  local t = {}
  for p in chain:gmatch("[^%.]+") do t[#t+1] = p end
  return t
end

-- Brace-balanced region starting at a "{", returns end line index (1-based).
local function find_balanced_region(lines, start_line)
  local depth, i = 0, start_line
  while i <= #lines do
    local s = lines[i]
    for j = 1, #s do
      local ch = s:sub(j, j)
      if ch == "{" then depth = depth + 1
      elseif ch == "}" then depth = depth - 1; if depth == 0 then return i end
      end
    end
    i = i + 1
  end
  return nil
end

-- Find "^ <dotted> = {" and return region (start,end).
local function find_direct_table(lines, dotted)
  local pat = "^%s*" .. dotted:gsub("([%.%-%+%*%?%[%]%^%$%(%)])","%%%1") .. "%s*=%s*{"
  for i = 1, #lines do
    local s = lines[i]
    if s:match(pat) then
      local e = find_balanced_region(lines, i)
      if e then return i, e end
    end
  end
  return nil, nil
end

-- Inside region (s..e), find "key = {" nested table, return its region.
local function find_child_table(lines, s, e, key)
  local pat = "[%[{,]%s*" .. key:gsub("([%.%-%+%*%?%[%]%^%$%(%)])","%%%1") .. "%s*=%s*{"
  for i = s, e do
    local line = lines[i]
    if line:match(pat) then
      local e2 = find_balanced_region(lines, i)
      if e2 then return i, e2 end
    end
  end
  return nil, nil
end

-- Inside region (s..e), find "key =" (any value), return its location.
local function find_key_assignment(lines, s, e, key)
  local pat = "^%s*" .. key:gsub("([%.%-%+%*%?%[%]%^%$%(%)])","%%%1") .. "%s*="
  for i = s, e do
    local line = lines[i]
    local c = line:find(pat)
    if c then return i, c end
  end
  return nil, nil
end

--- Locate a table region and optionally a key initializer inside it.
--- @param abs_path string  Absolute file path to search in
--- @param base_chain string "M.cfg.highlight"
--- @param seek_key string|nil  e.g. "enable_insert_submode_colors"
--- @return { path:string, key_line:integer|nil, key_col:integer|nil, tbl_start:integer|nil, tbl_end:integer|nil }|nil
function M.locate(abs_path, base_chain, seek_key)
  if type(abs_path) ~= "string" or abs_path == "" then return nil end
  local lines = vim.fn.readfile(abs_path)
  if type(lines) ~= "table" or #lines == 0 then return nil end

  local segs = split_chain(base_chain)
  if #segs == 0 then return nil end

  -- strategy 1: direct full assignment  M.cfg.highlight = {
  local start_l, end_l = find_direct_table(lines, table.concat(segs, "."))
  if not start_l then
    -- strategy 2: progressively nested within earlier assignments/returns
    -- try to find "M.cfg = {" region, then look for ".highlight"
    start_l, end_l = find_direct_table(lines, table.concat({ segs[1], segs[2] or "" }, "."):gsub("%.%s*$",""))
    if start_l and end_l and #segs >= 2 then
      for i = 3, #segs do
        local s2, e2 = find_child_table(lines, start_l, end_l, segs[i])
        if not s2 then start_l, end_l = nil, nil; break end
        start_l, end_l = s2, e2
      end
    end
    -- strategy 3: return { cfg = { highlight = { ... } } }
    if not start_l then
      local s_ret
      for i = 1, #lines do
        local l = lines[i]
        if l:match("^%s*return%s*{") then s_ret = i; break end
      end
      if s_ret then
        local e_ret = find_balanced_region(lines, s_ret)
        if e_ret then
          start_l, end_l = s_ret, e_ret
          for i = 1, #segs do
            local s2, e2 = find_child_table(lines, start_l, end_l, segs[i])
            if not s2 then start_l, end_l = nil, nil; break end
            start_l, end_l = s2, e2
          end
        end
      end
    end
  end

  if not start_l then
    -- Last fallback: maybe a single-line field assignment like M.cfg.highlight.key = ...
    if seek_key then
      local pat = "^%s*" .. table.concat(segs, "%%.") .. "%%." .. seek_key:gsub("([%.%-%+%*%?%[%]%^%$%(%)])","%%%1") .. "%s*="
      for i = 1, #lines do
        local line = lines[i]
        local c = line:find(pat)
        if c then
          return { path = abs_path, key_line = i, key_col = c, tbl_start = nil, tbl_end = nil }
        end
      end
    end
    return nil
  end

  -- If a key is requested, try to find it inside the located table region.
  if seek_key then
    local kl, kc = find_key_assignment(lines, start_l, end_l, seek_key)
    if kl then
      return { path = abs_path, key_line = kl, key_col = kc, tbl_start = start_l, tbl_end = end_l }
    end
  end

  -- Return the table region (start of table is a good landing spot).
  return { path = abs_path, key_line = start_l, key_col = 1, tbl_start = start_l, tbl_end = end_l }
end

return M

