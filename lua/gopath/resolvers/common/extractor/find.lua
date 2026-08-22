---@module 'gopath.resolvers.common.extractor.find'
---@brief Three algorithms to extract path-like candidates from a text line.

local M = {}
local helpers = require("gopath.resolvers.common.extractor.helpers")
local COMMON_EXTS = require("gopath.resolvers.common.extractor.common_extensions")

---@type string[]|nil  memoized merge of COMMON_EXTS + externally-openable extensions
local _exts = nil
---@type string[]|nil  the `external.extensions` table `_exts` was built for
local _exts_extras = nil

---Extensions the line extractor scans for: the editable/source list plus every
---externally-openable one (pdf, png, docx, zip, …) from `gopath.external`.
---
---`common_extensions` deliberately lists only files you'd open *in a buffer*,
---so a `[report](docs/report.pdf)` link used to be invisible to `by_extension`
---— the candidate was never extracted, and the link only ever resolved when the
---cursor happened to sit on the path itself (where `filetoken`/`<cfile>` takes
---over). Merging the external list in fixes that, and picks up the user's own
---`external.extensions` for free.
---@internal
---@return string[]
local function extensions()
  local extras
  local ok, ext_cfg = pcall(function()
    return require("gopath.config").get().external
  end)
  if ok and type(ext_cfg) == "table" then extras = ext_cfg.extensions end

  -- Rebuilt only when the configured extras table itself changes (setup()).
  if _exts and _exts_extras == extras then return _exts end

  local seen, out = {}, {}
  for _, ext in ipairs(COMMON_EXTS) do
    if not seen[ext] then
      seen[ext] = true
      out[#out + 1] = ext
    end
  end

  local ok_det, detector = pcall(require, "gopath.external.helpers.detector")
  if ok_det then
    for _, ext in ipairs(detector.extensions(extras)) do
      local dotted = "." .. ext
      if not seen[dotted] then
        seen[dotted] = true
        out[#out + 1] = dotted
      end
    end
  end

  _exts, _exts_extras = out, extras
  return out
end

---@type table<string, string>  closing bracket → its opener
local CLOSERS = { [")"] = "(", ["]"] = "[", ["}"] = "{", [">"] = "<" }

---Strip a single layer of matching wrapper characters (quotes/brackets) from
---`raw`, plus any unbalanced trailing closer.
---@internal
---@param raw string
---@return string
local function strip_wrappers(raw)
  if not raw or raw == "" then return raw end
  local first, last = raw:sub(1, 1), raw:sub(-1, -1)
  if (first == '"' and last == '"') or (first == "'" and last == "'") then return raw:sub(2, -2) end
  if (first == "(" and last == ")") or (first == "<" and last == ">") then return raw:sub(2, -2) end

  -- Drop unbalanced trailing closers. In a Markdown link `[label](docs/x.pdf)`
  -- the left expansion stops at "(", so the ")" survives on the right with no
  -- opener to match it and would otherwise become part of the path.
  -- Only unbalanced ones go: when the matching opener IS present the bracket is
  -- part of the name (`C:/Program Files (x86)/x.pdf`) and must be kept.
  while true do
    local tail = raw:sub(-1, -1)
    local opener = CLOSERS[tail]
    if not opener or raw:find(opener, 1, true) then break end
    raw = raw:sub(1, -2)
  end

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

  for _, ext in ipairs(extensions()) do
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
