---@module 'gopath.resolvers.common.extractor.helpers'
---@brief Utilities for the whole-line path extractor: deduplication and boundary expansion.

local M = {}
local TERMINATORS = require("gopath.resolvers.common.extractor.terminators")

---Deduplicate candidates by `raw` string, preserving first-seen order.
---@param list table[]
---@return table[]
function M.uniq(list)
  local seen, out = {}, {}
  for _, c in ipairs(list or {}) do
    if c and c.raw and c.raw ~= "" and not seen[c.raw] then
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
