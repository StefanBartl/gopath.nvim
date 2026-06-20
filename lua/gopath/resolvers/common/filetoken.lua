---@module 'gopath.resolvers.common.filetoken'
---@brief Resolve the token under the cursor as a plain file path.
---@description
--- Language-agnostic resolver that operates on vim's `<cfile>` expansion.
--- It is intentionally conservative: it only hands back a result when the
--- raw token looks like an actual path on disk (has path separators, a known
--- file extension, a location suffix, etc.). Dotted identifiers without
--- separators — such as Lua module names like "a.b.c.d" — are rejected here
--- so that language-specific resolvers (require_path, …) can handle them.

local P   = require("gopath.providers.builtin")
local U   = require("gopath.util.path")
local LOC = require("gopath.util.location")

local M = {}

---Heuristic: decide whether `str` is plausibly a file path rather than a
---language construct (a Lua module name, a method chain, …).
---
--- REJECT rules (applied first, short-circuit):
---   • Dotted identifiers with no path separator → treated as module/symbol
---     names UNLESS the final segment is a well-known file extension.
---
--- ACCEPT rules (any one is sufficient):
---   • Has a file extension   → "foo/bar.lua", "README.md"
---   • Has a path separator   → "src/utils", "C:\foo\bar"
---   • Starts with ~/ or ./   → home-relative or CWD-relative
---   • Has a location suffix  → "file:42" or "file(10)"
---   • Starts with ...        → truncated path from error output
---
---@param str string
---@return boolean
local function looks_like_path(str)
  if not str or str == "" then return false end

  -- REJECT: dotted identifier without path separators (covers both two-segment
  -- "a.b" and multi-segment "a.b.c.d" module names).
  -- Exception: the last segment is a recognised file extension, which means
  -- something like "README.md" should still be accepted.
  if str:match("^[%w_][%w_%.]+") and not str:match("[/\\]") then
    local common_exts = {
      lua=1, txt=1, md=1, vim=1, json=1, toml=1,
      yaml=1, py=1, js=1, ts=1, html=1, css=1,
    }
    local ext = str:match("%.([^%.]+)$")
    if not (ext and common_exts[ext]) then
      return false  -- looks like a module/symbol, not a path
    end
  end

  -- ACCEPT: has any common file extension at the end
  if str:match("%.[a-zA-Z][a-zA-Z0-9]*$") then return true end

  -- ACCEPT: contains a path separator
  if str:match("[/\\]") then return true end

  -- ACCEPT: home-relative or CWD-relative prefix
  if str:match("^[~%.][\\/]") then return true end

  -- ACCEPT: carries a location suffix (:42, (10), …)
  if str:match(":%d+") or str:match("%(%d+%)") then return true end

  -- ACCEPT: truncated path from error output / terminal
  if str:match("^%.%.%.") then return true end

  return false
end

---Strip noise prefixes and parse an optional :line[:col] suffix.
---@param raw string
---@return { path:string, line:integer|nil, col:integer|nil }|nil
local function parse_token(raw)
  if not raw or raw == "" then return nil end

  local cleaned = raw
  for _, prefix in ipairs({ "^Error%s+in%s+", "^%s*at%s+", "^%s*in%s+", "^%s*from%s+" }) do
    cleaned = cleaned:gsub(prefix, "")
  end

  local parsed = LOC.parse_location(cleaned)
  if not parsed.path or parsed.path == "" then return nil end

  local path = parsed.path
  path = path:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")  -- strip quotes
  path = path:gsub("^%.%.%./", "")                            -- strip leading .../
  path = path:gsub("^%s+", ""):gsub("%s+$", "")               -- trim

  if not looks_like_path(path) then return nil end

  return { path = path, line = parsed.line, col = parsed.col }
end

---@return GopathResult|nil
function M.resolve()
  local raw = P.expand_cfile()
  if not raw then return nil end

  local parsed = parse_token(raw)
  if not parsed then return nil end

  local token = parsed.path

  -- Search 1: vim &path
  local abs = U.search_with_vim_path(token)

  -- Search 2: rtp tail strip (handles ".../lua/foo/bar.lua")
  if not abs then
    local tail = token:match("/lua/(.+)$")
    if tail then abs = U.search_in_rtp({ tail }) end
  end

  -- Search 3: partial rtp match on last 2–3 segments
  if not abs then
    local segs = vim.split(token, "/", { trimempty = true, plain = true })
    for k = math.max(1, #segs - 2), math.max(1, #segs - 1) do
      local t = table.concat(segs, "/", k)
      abs = U.search_in_rtp({ t })
      if abs then break end
    end
  end

  -- Fallback: build absolute path relative to current file's directory
  if not abs then
    if token:match("^[/\\]") or token:match("^[A-Za-z]:") then
      abs = token
    else
      local cwd = vim.fn.expand("%:p:h")
      abs = vim.fn.fnamemodify(cwd .. "/" .. token, ":p")
    end
  end

  local exists = U.exists(abs)

  return {
    language   = vim.bo.filetype or "text",
    kind       = exists and "module" or "file",
    path       = abs,
    range      = LOC.create_range(parsed.line, parsed.col),
    chain      = nil,
    source     = "builtin",
    confidence = exists and 0.75 or 0.3,
    exists     = exists,
  }
end

return M
