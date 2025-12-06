---@module 'gopath.truncated'
---@description Resolve truncated paths from error messages and logs.
---Handles paths like: "...AppData\Local\nvim\init.lua"
---
---Architecture:
---  1. Detect truncated path (starts with ... or …)
---  2. Search in-memory cache (fast)
---  3. Fallback to live filesystem search (slower)
---  4. Present interactive selection if multiple matches
---
---Example:
---  Input:  "...nvim-data/lazy/gopath.nvim/lua/init.lua:42"
---  Output: Opens /full/path/to/.../lua/init.lua at line 42

local M = {}

-- local uv = vim.loop

---Check if a path looks truncated
---Recognizes common truncation indicators:
---  - "..." (three dots)
---  - ".../" or "...\" (with path separator)
---  - "…" (unicode ellipsis)
---@param path string Path to check
---@return boolean is_truncated True if path appears truncated
function M.is_truncated(path)
  if not path or path == "" then
    return false
  end

  -- Check for common truncation patterns
  return path:match("^%.%.%.")     -- Starts with ...
      or path:match("^%.%.%.[\\/]") -- .../  or ...\
      or path:match("^…")          -- Unicode ellipsis
end

---Extract meaningful tail from truncated path
---Strips the ellipsis prefix and normalizes separators
---
---Examples:
---  "...nvim/init.lua"    → "nvim/init.lua"
---  "…config\nvim\init"   → "config/nvim/init"
---  ".../lazy/gopath.lua" → "lazy/gopath.lua"
---
---@param path string Truncated path with ... prefix
---@return string tail The important part after ellipsis
local function extract_tail(path)
  -- Step 1: Strip various ellipsis formats
  local tail = path:gsub("^%.%.%.", "")  -- Remove ...
  tail = tail:gsub("^…", "")              -- Remove unicode ellipsis

  -- Step 2: Normalize path separators (Windows → Unix)
  tail = tail:gsub("\\", "/")

  -- Step 3: Remove leading slashes
  tail = tail:gsub("^/+", "")

  return tail
end

---Attempt to resolve a truncated path
---This is the main entry point for truncated path resolution.
---
---Resolution flow:
---  1. Validate truncation
---  2. Extract tail
---  3. Search in-memory cache (if enabled)
---  4. Fallback to live search (if enabled)
---  5. Open directly (single match) or show selection UI (multiple matches)
---
---@param truncated_path string Path starting with ... or …
---@param opts table|nil Options:
---  - use_cache: boolean (default: true) - Use in-memory cache
---  - similarity_threshold: number (default: 75) - For fuzzy matching
---  - open_cmd: string (default: "edit") - Command to open file (edit/split/vsplit/tabedit)
---@return boolean handled True if path was resolved and file opened
function M.try_resolve(truncated_path, opts)
  -- === STEP 1: Validate Input ===
  if not M.is_truncated(truncated_path) then
    return false  -- Not a truncated path, can't help
  end

  -- === STEP 2: Parse Options ===
  opts = opts or {}
  local use_cache = opts.use_cache ~= false  -- Default: true
  -- local threshold = opts.similarity_threshold or 75
  local open_cmd = opts.open_cmd or "edit"  -- NEW: Respect caller's open command

  -- === STEP 3: Extract Tail ===
  local tail = extract_tail(truncated_path)
  if not tail or tail == "" then
    -- Truncated path had no actual content after ellipsis
    return false
  end

  -- === STEP 4: Try Cache Search ===
  if use_cache then
    local cache = require("gopath.truncated.cache")

    -- Search in-memory cache (fast: <10ms)
    local cache_results = cache.search(tail)

    if cache_results and #cache_results > 0 then
      -- Cache hit! We found matching files

      if #cache_results == 1 then
        -- === Single Match: Open Directly ===
        local path = cache_results[1]

        -- Use the open command specified by caller
        -- This respects whether user pressed gP (edit), g| (split), g\ (vsplit), etc.
        vim.cmd(open_cmd .. " " .. vim.fn.fnameescape(path))

        vim.notify(
          string.format("[gopath] Opened from cache: %s", vim.fn.fnamemodify(path, ":t")),
          vim.log.levels.INFO
        )
        return true
      end

      -- === Multiple Matches: Show Selection UI ===
      return M._show_selection(cache_results, tail, "cache", open_cmd)
    end

    -- Cache miss, continue to live search
  end

  -- === STEP 5: Live Search Fallback ===
  local finder = require("gopath.truncated.finder")

  -- This is slower (~100-2000ms depending on tool and project size)
  local live_results = finder.find(tail)

  if not live_results or #live_results == 0 then
    -- No matches found anywhere
    vim.notify(
      string.format("[gopath] Could not resolve truncated path: %s", tail),
      vim.log.levels.WARN
    )
    return false
  end

  -- === STEP 6: Process Live Results ===
  if #live_results == 1 then
    -- Single match: open directly
    local path = live_results[1]
    vim.cmd(open_cmd .. " " .. vim.fn.fnameescape(path))

    vim.notify(
      string.format("[gopath] Opened: %s", vim.fn.fnamemodify(path, ":t")),
      vim.log.levels.INFO
    )
    return true
  end

  -- Multiple matches: show selection
  return M._show_selection(live_results, tail, "live search", open_cmd)
end

---Show interactive selection for multiple matches
---Uses the alternate UI system which respects user's UI backend preference
---(vim.ui.select, Telescope, fzf-lua, etc.)
---
---@param matches string[] List of absolute file paths
---@param tail string Original tail that was searched
---@param source string Source of matches ("cache" or "live search")
---@param open_cmd string Command to use when opening selected file
---@return boolean handled True if user selected a file
function M._show_selection(matches, tail, source, open_cmd)
  -- === STEP 1: Convert to Alternate Format ===
  -- The alternate system expects entries with similarity scores
  local matcher = require("gopath.alternate.helpers.matcher")
  local tail_filename = tail:match("([^/\\]+)$") or tail

  local formatted = {}
  for _, path in ipairs(matches) do
    local filename = vim.fn.fnamemodify(path, ":t")

    -- Calculate similarity between tail filename and candidate filename
    -- This helps sort results (most similar first)
    local similarity = matcher.calculate_similarity(tail_filename, filename)

    table.insert(formatted, {
      path = path,
      similarity = similarity,
      filename = filename,
    })
  end

  -- === STEP 2: Sort by Similarity ===
  -- Most relevant matches appear first
  table.sort(formatted, function(a, b)
    return a.similarity > b.similarity
  end)

  -- === STEP 3: Notify User ===
  vim.notify(
    string.format("[gopath] Found %d matches via %s", #formatted, source),
    vim.log.levels.INFO
  )

  -- === STEP 4: Show Selection UI ===
  -- This will use the user's configured UI backend (builtin/telescope/fzf)
  local alternate = require("gopath.alternate")

  -- Pass the open command so alternate can use it when opening
  return alternate.try_resolve_with_matches(formatted, tail, {
    open_cmd = open_cmd,
  })
end

return M
