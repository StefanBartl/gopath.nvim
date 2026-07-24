---@module 'gopath.resolvers.common.extractor.find'
---@brief Three algorithms to extract path-like candidates from a text line.

local M = {}
local helpers = require("gopath.resolvers.common.extractor.helpers")
local COMMON_EXTS = require("gopath.resolvers.common.extractor.common_extensions")

local function strip_wrappers(raw)
  if not raw or raw == "" then return raw end
  local first, last = raw:sub(1, 1), raw:sub(-1, -1)
  if (first == '"' and last == '"') or (first == "'" and last == "'") then return raw:sub(2, -2) end
  if (first == "(" and last == ")") or (first == "<" and last == ">") then return raw:sub(2, -2) end
  return raw
end

---Extract stacktrace-style candidates: `path:line:col` and `path:line`.
---@param line string
---@return table[]  { raw, path, lineno, col }[]
function M.stack_patterns(line)
  local out = {}
  if not line or line == "" then return out end

  -- path:line:col
  for raw, ln, col in line:gmatch("([%w%p]+[%/\\][%w%p%%+~@:_%-%.,]+):(%d+):(%d+)") do
    raw = strip_wrappers(raw)
    out[#out + 1] = {
      raw = raw .. ":" .. ln .. ":" .. col,
      path = raw,
      lineno = tonumber(ln),
      col = tonumber(col),
    }
  end

  -- path:line (skip duplicates already caught above)
  for raw, ln in line:gmatch("([%w%p]+[%/\\][%w%p%%+~@:_%-%.,]+):(%d+)") do
    raw = strip_wrappers(raw)
    local dup = false
    for _, v in ipairs(out) do
      if v.path == raw and v.lineno == tonumber(ln) then
        dup = true
        break
      end
    end
    if not dup then
      out[#out + 1] = { raw = raw .. ":" .. ln, path = raw, lineno = tonumber(ln), col = nil }
    end
  end

  return out
end

---Expand around a known file extension to extract path-like substrings.
---@param line string
---@return table[]
function M.by_extension(line)
  local out = {}
  if not line or line == "" then return out end

  for _, ext in ipairs(COMMON_EXTS) do
    local pos = 1
    while true do
      local found = line:find(ext, pos, true)
      if not found then break end
      local ext_end = found + #ext - 1
      local left = helpers.expand_left(line, found)
      local right = helpers.expand_right(line, ext_end + 1)
      local raw = strip_wrappers(line:sub(left, right))
      -- Only keep if it looks path-like
      if
        raw:match("[/\\]")
        or raw:match("^~")
        or raw:match("^[A-Za-z]:\\")
        or raw:match("^%.%.")
      then
        out[#out + 1] = { raw = raw, path = raw, lineno = nil, col = nil }
      end
      pos = ext_end + 1
    end
  end

  return out
end

---Extract unix absolute (`/…`), Windows (`C:\…`), and UNC (`\\…`) paths.
---@param line string
---@return table[]
function M.absolute_paths(line)
  local out = {}
  if not line or line == "" then return out end

  for raw in line:gmatch("(/[%w%p%%+~@:_%-%.,]+)") do
    raw = strip_wrappers(raw)
    out[#out + 1] = { raw = raw, path = raw, lineno = nil, col = nil }
  end
  for raw in line:gmatch("([A-Za-z]:\\[%w%p%%+~@:_%-%.,\\]+)") do
    raw = strip_wrappers(raw)
    out[#out + 1] = { raw = raw, path = raw, lineno = nil, col = nil }
  end
  for raw in line:gmatch("(\\\\[%w%p%%+~@:_%-%.,\\]+)") do
    raw = strip_wrappers(raw)
    out[#out + 1] = { raw = raw, path = raw, lineno = nil, col = nil }
  end

  return out
end

return M
