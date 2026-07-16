---@module 'gopath.resolvers.common.extractor.helpers'
---@brief Utilities for the whole-line path extractor: deduplication and boundary expansion.
---@description
--- uniq() delegates to lib.nvim.lua.tables.unique_table.unique_by (declared
--- dependency, same soft-fallback convention as `gopath.util.cross` /
--- `gopath.util.log`) when lib.nvim is available; falls back to the original
--- hand-rolled seen-table loop otherwise.

local M = {}
local TERMINATORS = require("gopath.resolvers.common.extractor.terminators")

---@type (fun(list: table[], key_fn: fun(item: table): any): table[])|nil
local unique_by
do
  local ok, mod = pcall(require, "lib.lua.tables.unique_table")
  if ok then
    unique_by = mod.unique_by
  else
    vim.schedule(function()
      require("gopath.util.log").warn(
        "optional dependency 'lib.nvim' not found — using a built-in "
          .. "dedup fallback for the path extractor."
      )
    end)
  end
end

---Filter out entries with no usable `raw` key (empty/missing candidates).
---@param list table[]
---@return table[]
local function with_raw_key(list)
  local out = {}
  for _, c in ipairs(list or {}) do
    if c and c.raw and c.raw ~= "" then
      out[#out + 1] = c
    end
  end
  return out
end

---Deduplicate candidates by `raw` string, preserving first-seen order.
---@param list table[]
---@return table[]
function M.uniq(list)
  local filtered = with_raw_key(list)

  if unique_by then
    return unique_by(filtered, function(c)
      return c.raw
    end)
  end

  local seen, out = {}, {}
  for _, c in ipairs(filtered) do
    if not seen[c.raw] then
      seen[c.raw] = true
      out[#out + 1] = c
    end
  end
  return out
end

---Move left from index `i` until hitting a terminator or string start.
---Returns the 1-based inclusive left boundary.
---@param s string
---@param i number  starting index (1-based)
---@return number
function M.expand_left(s, i)
  local j = i
  while j > 1 do
    if TERMINATORS[s:sub(j, j)] then break end
    j = j - 1
  end
  if j > 1 and TERMINATORS[s:sub(j, j)] then return j + 1 end
  return 1
end

---Move right from index `i` until hitting a terminator or string end.
---Returns the 1-based inclusive right boundary.
---@param s string
---@param i number  starting index (1-based)
---@return number
function M.expand_right(s, i)
  local n = #s
  local j = i
  while j < n do
    if TERMINATORS[s:sub(j, j)] then break end
    j = j + 1
  end
  return j
end

return M
