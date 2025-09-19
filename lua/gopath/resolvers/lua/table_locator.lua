---@module 'gopath.resolvers.lua.table_locator'
---@brief Locate a table (and optionally a key initializer) by a dotted base chain in a Lua file.
---@desc Robust against newlines after "=", bracketed keys, return-blocks and tables nested in function calls.

local M = {}

-- ========= helpers =========

  local function esc(str) return (str:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])","%%%1")) end

local function split_chain(chain)
  local t = {}
  for p in chain:gmatch("[^%.]+") do t[#t+1] = p end
  return t
end

-- Find "balanced" table region starting at a line whose FIRST "{" starts the table.
-- Returns end line (1-based). Tolerates nested braces.
local function find_balanced_region(lines, start_line)
  local depth, i = 0, start_line
  while i <= #lines do
    local s = lines[i]
    -- strip line comments to avoid counting braces in comments
    s = s:gsub("%-%-.*$", "")
    for j = 1, #s do
      local ch = s:sub(j, j)
      if ch == "{" then
        depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then return i end
      end
    end
    i = i + 1
  end
  return nil
end

-- Find table opening after an equals sign for a given "dotted" LHS (on same or next lines, also inside function calls).
-- Accepts inline "{", or "=" then later "{" (skipping blanks/comments), or "=" followed by function call text until first "{"
local function find_direct_table_loose(lines, dotted)
  local pat_inline = "^%s*" .. esc(dotted) .. "%s*=%s*{"
  local pat_eq     = "^%s*" .. esc(dotted) .. "%s*=%s*(.*)$"

  for i = 1, #lines do
    local s = lines[i]
    if s:match(pat_inline) then
      local e = find_balanced_region(lines, i)
      if e then return i, e end
    end
    local rhs = s:match(pat_eq)
    if rhs then
      -- same line: look for first "{"
      local c = rhs:find("{")
      if c then
        local e = find_balanced_region(lines, i)
        if e then return i, e end
      else
        -- next non-empty/non-comment line that starts a "{"
        local j = i + 1
        while j <= #lines do
          local ln = lines[j]
          if ln:match("^%s*$") or ln:match("^%s*%-%-") then
            j = j + 1
          elseif ln:match("^%s*{") or ln:find("{") then
            local e = find_balanced_region(lines, j)
            if e then return j, e end
            break
          else
            break
          end
        end
      end
    end
  end
  return nil, nil
end

-- "ROOT.chain = { ... }" → region
local function find_direct_table(lines, dotted)
  local s1, e1 = find_direct_table_loose(lines, dotted)
  if s1 then return s1, e1 end
  return nil, nil
end

-- Any-root direct assignment: <ROOT>.<chain_wo_root> = { ... }
local function find_anyroot_direct_table(lines, chain_wo_root)
  local pi = "^%s*([%w_]+)%s*%." .. esc(chain_wo_root) .. "%s*=%s*{"
  local pe = "^%s*([%w_]+)%s*%." .. esc(chain_wo_root) .. "%s*=%s*(.*)$"
  for i = 1, #lines do
    local s = lines[i]
    local root_inline = s:match(pi)
    if root_inline then
      local e = find_balanced_region(lines, i)
      if e then return root_inline, i, e end
    end
    local rhs = s:match(pe)
    if rhs then
      local c = rhs:find("{")
      if c then
        local e = find_balanced_region(lines, i)
        if e then return s:match(pe), i, e end
      else
        local j = i + 1
        while j <= #lines do
          local ln = lines[j]
          if ln:match("^%s*$") or ln:match("^%s*%-%-") then
            j = j + 1
          elseif ln:match("^%s*{") or ln:find("{") then
            local e = find_balanced_region(lines, j)
            if e then
              local r = s:match(pe)
              return r, j, e
            end
            break
          else
            break
          end
        end
      end
    end
  end
  return nil, nil, nil
end

-- return { ... } region (outermost)
local function find_return_table_region(lines)
  for i = 1, #lines do
    local s = lines[i]
    if s:match("^%s*return%s*{") then
      local e = find_balanced_region(lines, i)
      if e then return i, e end
    end
  end
  return nil, nil
end

-- Strip line comments and string contents to avoid counting braces inside them.
local function scrub_for_braces(s)
  -- drop line comments
  s = s:gsub("%-%-.*$", "")
  -- drop simple balanced string bodies (keeps quotes to not break patterns)
  s = s:gsub('%b""', '""')
  s = s:gsub("%b''", "''")
  return s
end

-- Inside region s..e, find "key = {" nested table at depth 1 and return its region.
-- Supports bare and bracketed keys. Depth-aware (so wir nicht in tieferen Subtables hängenbleiben).
local function find_child_table(lines, s, e, key)
  local ke = esc(key)
  local heads = {
    "^%s*" .. ke .. "%s*=%s*{",                 -- key = {
    '^%s*%["' .. ke .. '"%]%s*=%s*{',          -- ["key"] = {
    "^%s*%['" .. ke .. "'%]%s*=%s*{",          -- ['key'] = {
    "[%[{,]%s*" .. ke .. "%s*=%s*{",           -- , key = {  (auch nach Komma/Blockstart)
    '%[{"%s*%["' .. ke .. '"%]%s*=%s*{',       -- , ["key"] = {
    "[%[{,]%s*%['" .. ke .. "'%]%s*=%s*{",     -- , ['key'] = {
  }

  local depth = 0
  -- initial depth scan (wie oben)
  do
    local line = scrub_for_braces(lines[s] or "")
    for j = 1, #line do
      local ch = line:sub(j, j)
      if ch == "{" then depth = depth + 1
      elseif ch == "}" then depth = math.max(0, depth - 1) end
    end
  end

  for i = s, e do
    local raw = lines[i] or ""
    local line = scrub_for_braces(raw)

    if depth == 1 then
      for _, pat in ipairs(heads) do
        if line:match(pat) then
          local end_line = find_balanced_region(lines, i)
          if end_line then return i, end_line end
        end
      end
    end

    for j = 1, #line do
      local ch = line:sub(j, j)
      if ch == "{" then depth = depth + 1
      elseif ch == "}" then depth = math.max(0, depth - 1) end
    end
  end

  return nil, nil
end
-- Inside region s..e, find "key =" (any value). Returns position of the key.
local function find_key_assignment(lines, s, e, key)
  local ke = esc(key)
  local patterns = {
    "^%s*" .. ke .. "%s*=",                 -- key =
    "^%s*%[\"" .. ke .. "\"%]%s*=",        -- ["key"] =
    "^%s*%['" .. ke .. "'%]%s*=",          -- ['key'] =
  }
  for i = s, e do
    local line = lines[i]
    for _, pat in ipairs(patterns) do
      local c = line:find(pat)
      if c then return i, c end
    end
  end
  return nil, nil
end

-- Global search: find first "key = { ... }" anywhere (useful for nested-in-call tables).
local function find_global_table(lines, key)
  local k = esc(key)
  local pat_inline = "%f[%w_]" .. k .. "%f[^%w_]%s*=%s*{"
  local pat_eq     = "%f[%w_]" .. k .. "%f[^%w_]%s*=%s*$"

  for i = 1, #lines do
    local s = lines[i]
    if s:match(pat_inline) then
      local e = find_balanced_region(lines, i)
      if e then return i, e end
    end
    if s:match(pat_eq) then
      local j = i + 1
      while j <= #lines do
        local ln = lines[j]
        if ln:match("^%s*$") or ln:match("^%s*%-%-") then
          j = j + 1
        elseif ln:match("^%s*{") or ln:find("{") then
          local e = find_balanced_region(lines, j)
          if e then return j, e end
          break
        else
          break
        end
      end
    end
  end
  return nil, nil
end

-- ========= main locate =========

--- Locate a table region and optionally a key initializer inside it.
--- @param abs_path string  Absolute file path to search in
--- @param base_chain string "M.cfg.highlight" (root.var1.var2)
--- @param seek_key string|nil  e.g. "enable_insert_submode_colors"
--- @return { path:string, key_line:integer|nil, key_col:integer|nil, tbl_start:integer|nil, tbl_end:integer|nil }|nil
function M.locate(abs_path, base_chain, seek_key)
  if type(abs_path) ~= "string" or abs_path == "" then return nil end
  local lines = vim.fn.readfile(abs_path)
  if type(lines) ~= "table" or #lines == 0 then return nil end

  local segs = split_chain(base_chain)  -- { ROOT, cfg, highlight, ... }
  if #segs == 0 then return nil end

  -- final found region
  local found = false
  local fs, fe -- integers (table start/end)

  -- 1) direct: ROOT.cfg.highlight = { ... }
  do
    local s1, e1 = find_direct_table(lines, table.concat(segs, "."))
    if s1 and e1 then
      fs, fe, found = s1, e1, true
    end
  end

  -- 2) progressive: ROOT.cfg = { ... } -> child "highlight" -> ...
  if (not found) and (#segs >= 2) then
    local top = table.concat({ segs[1], segs[2] or "" }, "."):gsub("%.%s*$","")
    if top ~= "" then
      local t_s, t_e = find_direct_table(lines, top)
      if t_s and t_e then
        local s, e = t_s, t_e
        local ok = true
        for i = 3, #segs do
          local s2, e2 = find_child_table(lines, s, e, segs[i])
          if not s2 or not e2 then ok = false; break end
          s, e = s2, e2
        end
        if ok then fs, fe, found = s, e, true end
      end
    end
  end

  -- 3) any-root: <ROOT>.(cfg.highlight) = { ... }
  if (not found) and (#segs >= 2) then
    local chain_wo_root = table.concat(segs, ".", 2)
    local _, s2, e2 = find_anyroot_direct_table(lines, chain_wo_root)
    if s2 and e2 then
      fs, fe, found = s2, e2, true
    end
  end

  -- 4) return { cfg = { highlight = ... } } : descend inside outer return table
  if not found then
    local r_s, r_e = find_return_table_region(lines)
    if r_s and r_e then
      local s, e = r_s, r_e
      local ok = true
      for i = 1, #segs do
        local s2, e2 = find_child_table(lines, s, e, segs[i])
        if not s2 or not e2 then ok = false; break end
        s, e = s2, e2
      end
      if ok then fs, fe, found = s, e, true end
    end
  end

  -- 5) global fallback: start from segs[2] inside any table, then descend
  if (not found) and (#segs >= 2) then
    local g_s, g_e = find_global_table(lines, segs[2])
    if g_s and g_e then
      local s, e = g_s, g_e
      local ok = true
      for i = 3, #segs do
        local s2, e2 = find_child_table(lines, s, e, segs[i])
        if not s2 or not e2 then ok = false; break end
        s, e = s2, e2
      end
      if ok then fs, fe, found = s, e, true end
    end
  end

  -- 6) nothing found: final single-line field assignment fallback: ROOT.cfg.highlight.key = ...
  if not found then
    if seek_key then
      local dotted = table.concat(segs, "%.")
      local ke = esc(seek_key)
      local patterns = {
        "^%s*" .. dotted .. "%." .. ke .. "%s*=",
        '^%s*' .. dotted .. '%["' .. ke .. '"%]%s*=',
        "^%s*" .. dotted .. "%['" .. ke .. "'%]%s*=",
      }
      for i = 1, #lines do
        local line = lines[i]
        for _, pat in ipairs(patterns) do
          local c = line:find(pat)
          if c then
            return { path = abs_path, key_line = i, key_col = c, tbl_start = nil, tbl_end = nil }
          end
        end
      end
    end
    return nil
  end

  -- 7) If a key is requested, locate it inside the found table region.
  if seek_key then
    local kl, kc = find_key_assignment(lines, fs, fe, seek_key)
    if kl then
      return { path = abs_path, key_line = kl, key_col = kc, tbl_start = fs, tbl_end = fe }
    end
  end

  -- 8) No key given or key not found: land at table start.
  return { path = abs_path, key_line = fs, key_col = 1, tbl_start = fs, tbl_end = fe }
end

return M
