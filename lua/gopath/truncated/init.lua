---@module 'gopath.truncated'
---@brief Resolve truncated paths from error messages and logs.
---@description
--- Handles paths like: "...AppData\Local\nvim\init.lua:42" or "…/lua/config/init.lua".
---
--- Resolution flow:
---   1. Detect truncation (leading "..."/"…").
---   2. Split off an optional ":line[:col]" location suffix.
---   3. Search the in-memory cache (fast).
---   4. Fall back to a live filesystem search (slower).
---   5. Open directly (single match) or present an interactive selection.
---
--- Example:
---   Input:  "...nvim-data/lazy/gopath.nvim/lua/init.lua:42"
---   Output: Opens /full/path/.../lua/init.lua and jumps to line 42.

local LOC = require("gopath.util.location")
local LOG = require("gopath.util.log")

local M = {}

---Open commands keyed by gopath "kind". Truncated callers pass a real Ex command
---(e.g. "edit"), so this map is only used for normalization/safety.
---@type table<string, string>
local OPEN_CMD = {
  edit = "edit",
  split = "split",
  window = "split",
  vsplit = "vsplit",
  tab = "tabedit",
  tabedit = "tabedit",
}

---Check if a path looks truncated.
---Recognizes "..." (3+ dots) and the unicode ellipsis "…", optionally followed
---by a path separator.
---@param path string Path to check
---@return boolean is_truncated
function M.is_truncated(path)
  if type(path) ~= "string" or path == "" then return false end

  return path:match("^%.%.%.") ~= nil -- starts with ... (three or more)
    or path:match("^…") ~= nil -- unicode ellipsis
end

---Extract the meaningful tail from a truncated path.
---Strips the ellipsis prefix, normalizes separators and leading slashes.
---@param path string Truncated path with ellipsis prefix
---@return string tail Important part after the ellipsis
local function extract_tail(path)
  local tail = path:gsub("^%.%.%.+", "") -- remove leading dots (3 or more)
  tail = tail:gsub("^…", "") -- remove unicode ellipsis
  tail = tail:gsub("\\", "/") -- normalize separators
  tail = tail:gsub("^/+", "") -- drop leading slashes
  return tail
end

---Open a resolved file with an optional line/col jump.
---@param path string Absolute file path
---@param open_cmd string Ex command (edit/split/vsplit/tabedit)
---@param line integer|nil 1-based line
---@param col integer|nil 1-based column
---@return boolean ok
local function open_path(path, open_cmd, line, col)
  local cmd = OPEN_CMD[open_cmd] or "edit"

  local ok = pcall(vim.cmd, cmd .. " " .. vim.fn.fnameescape(path))
  if not ok then return false end

  if line and line > 0 then
    -- nvim_win_set_cursor uses 0-based columns
    local c = math.max(0, (col or 1) - 1)
    pcall(vim.api.nvim_win_set_cursor, 0, { line, c })
    pcall(vim.cmd, "normal! zz")
  end

  return true
end

---Attempt to resolve a truncated path and open the matching file.
---@param truncated_path string Path starting with "..." or "…"
---@param opts table|nil Options:
---  - use_cache: boolean (default true)
---  - open_cmd: string (default "edit")
---@return boolean handled True if a file was opened (or a selection shown)
function M.try_resolve(truncated_path, opts)
  if not M.is_truncated(truncated_path) then return false end

  opts = opts or {}
  local use_cache = opts.use_cache ~= false
  local open_cmd = opts.open_cmd or "edit"

  -- Separate the path from an optional :line[:col] suffix BEFORE searching,
  -- otherwise the location digits poison every filename comparison.
  local raw_tail = extract_tail(truncated_path)
  if raw_tail == "" then return false end

  local parsed = LOC.parse_location(raw_tail)
  local tail = parsed.path
  local line = parsed.line
  local col = parsed.col

  if not tail or tail == "" then return false end

  -- === Cache search (fast path) ===
  if use_cache then
    local ok, cache = pcall(require, "gopath.truncated.cache")
    if ok then
      local results = cache.search(tail)
      if results and #results > 0 then
        if #results == 1 then return open_path(results[1], open_cmd, line, col) end
        return M._show_selection(results, tail, "cache", open_cmd, line, col)
      end
    end
  end

  -- === Live filesystem search (fallback) ===
  local ok, finder = pcall(require, "gopath.truncated.finder")
  if not ok then return false end

  local live = finder.find(tail)
  if not live or #live == 0 then
    LOG.warn("Could not resolve truncated path: " .. tail)
    return false
  end

  if #live == 1 then return open_path(live[1], open_cmd, line, col) end

  return M._show_selection(live, tail, "live search", open_cmd, line, col)
end

---Show an interactive selection for multiple matches.
---Delegates to the alternate UI, which respects the user's UI backend.
---@param matches string[] Absolute file paths
---@param tail string Searched tail
---@param source string "cache" | "live search"
---@param open_cmd string Ex command used to open the selected file
---@param line integer|nil 1-based line to jump to after opening
---@param col integer|nil 1-based column to jump to after opening
---@return boolean handled
function M._show_selection(matches, tail, source, open_cmd, line, col)
  local matcher = require("gopath.alternate.helpers.matcher")
  local tail_filename = tail:match("([^/\\]+)$") or tail

  local formatted = {}
  for i = 1, #matches do
    local path = matches[i]
    local filename = vim.fn.fnamemodify(path, ":t")
    formatted[i] = {
      path = path,
      similarity = matcher.calculate_similarity(tail_filename, filename),
      filename = filename,
    }
  end

  table.sort(formatted, function(a, b)
    return a.similarity > b.similarity
  end)

  LOG.debug(string.format("Found %d matches via %s", #formatted, source))

  local alternate = require("gopath.alternate")
  return alternate.try_resolve_with_matches(formatted, tail, {
    open_cmd = OPEN_CMD[open_cmd] or "edit",
    line = line,
    col = col,
  })
end

return M
