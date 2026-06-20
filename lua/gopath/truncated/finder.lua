---@module 'gopath.truncated.finder'
---@brief Live filesystem search for truncated path tails.
---@description
--- Fallback used by `gopath.truncated` when the in-memory cache produces no hit.
--- Searches a bounded set of roots (cwd, git root, Neovim config/data, runtimepath)
--- downward for files whose path matches the truncated tail.
---
--- Design goals:
---   - Cross-platform: relies on `vim.fs.find` (pure Lua, no shell), with an optional
---     `fd` fast-path when available.
---   - Bounded: only searches source-relevant roots, never the whole drive.
---   - Pure matching logic: `M.matches_tail` is side-effect free and unit-testable.

local M = {}

local uv = vim.loop or vim.uv

---Normalize a path for comparison: forward slashes, lowercase, no trailing slash.
---@param p string
---@return string
local function normalize(p)
  local s = p:gsub("\\", "/"):lower()
  s = s:gsub("/+$", "")
  return s
end

---Check whether a candidate path matches a (path-only) truncated tail.
---Two strategies:
---  1. Suffix match: candidate ends with the tail.
---  2. Sequential segment match: all tail segments appear in order inside candidate.
---@param candidate string Absolute candidate path
---@param normalized_tail string Already normalized tail (lowercase, forward slashes)
---@param tail_parts string[] Pre-split tail segments
---@return boolean
function M.matches_tail(candidate, normalized_tail, tail_parts)
  local np = normalize(candidate)

  -- Strategy 1: exact suffix
  if np:sub(-#normalized_tail) == normalized_tail then
    return true
  end

  -- Strategy 2: sequential segments (only meaningful for multi-segment tails)
  if #tail_parts > 1 then
    local path_parts = vim.split(np, "/", { trimempty = true })
    local idx = 1
    for i = 1, #path_parts do
      if idx <= #tail_parts and path_parts[i] == tail_parts[idx] then
        idx = idx + 1
      end
    end
    return idx > #tail_parts
  end

  return false
end

---Collect the bounded set of roots to search.
---@return string[] roots Deduplicated list of existing directories
local function collect_roots()
  local seen, roots = {}, {}

  local function add(dir)
    if type(dir) ~= "string" or dir == "" then
      return
    end
    local abs = vim.fn.fnamemodify(dir, ":p"):gsub("[/\\]+$", "")
    if abs == "" or seen[abs] then
      return
    end
    if vim.fn.isdirectory(abs) == 1 then
      seen[abs] = true
      roots[#roots + 1] = abs
    end
  end

  add(vim.fn.getcwd())

  -- Git root (best effort, non-blocking failure)
  local ok, git_root = pcall(function()
    return vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
  end)
  if ok and git_root then
    add(git_root)
  end

  add(vim.fn.stdpath("config"))
  add(vim.fn.stdpath("data"))

  -- Runtimepath entries (covers installed plugins and config)
  for _, dir in ipairs(vim.api.nvim_list_runtime_paths()) do
    add(dir)
  end

  return roots
end

---Search a single root downward for files matching the basename, then filter by tail.
---@param root string Root directory
---@param basename string Filename to look for
---@param normalized_tail string
---@param tail_parts string[]
---@param limit integer Maximum candidates to inspect per root
---@param acc string[] Accumulator for matches (mutated)
---@param seen table<string, boolean> Dedup set (mutated)
local function search_root(root, basename, normalized_tail, tail_parts, limit, acc, seen)
  local ok, found = pcall(vim.fs.find, basename, {
    type = "file",
    limit = limit,
    path = root,
  })
  if not ok or type(found) ~= "table" then
    return
  end

  for i = 1, #found do
    local cand = found[i]
    if not seen[cand] and M.matches_tail(cand, normalized_tail, tail_parts) then
      seen[cand] = true
      acc[#acc + 1] = cand
    end
  end
end

---Find files on disk matching a truncated tail (path only, no line/col).
---@param tail string Tail of the truncated path (e.g. "config/neotree/commands/init.lua")
---@param opts table|nil { limit_per_root: integer (default 100), roots: string[]|nil }
---@return string[] matches Absolute, deduplicated file paths (possibly empty)
function M.find(tail, opts)
  if type(tail) ~= "string" or tail == "" then
    return {}
  end

  opts = opts or {}
  local limit_per_root = opts.limit_per_root or 100

  local normalized_tail = normalize(tail)
  local tail_parts = vim.split(normalized_tail, "/", { trimempty = true })
  if #tail_parts == 0 then
    return {}
  end

  -- Basename is the last segment; used as the cheap pre-filter for vim.fs.find.
  local basename = tail_parts[#tail_parts]

  local roots = opts.roots or collect_roots()
  local matches, seen = {}, {}

  for i = 1, #roots do
    search_root(roots[i], basename, normalized_tail, tail_parts, limit_per_root, matches, seen)
  end

  return matches
end

---Quick availability check for the libuv handle (used in tests/debug).
---@return boolean
function M.has_uv()
  return uv ~= nil
end

return M
