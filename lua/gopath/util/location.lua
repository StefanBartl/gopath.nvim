---@module 'gopath.util.location'
---@brief Parse and merge file locations with line/column information.
---@description
--- Handles the common formats that appear in Lua error messages, stack traces
--- and terminal output: `path:line:col`, `path:line`, `path(line:col)`,
--- `path(line)` and `path +line`. Returns a `ParsedLocation` table that
--- callers can use to jump to the exact position after opening a file.

local M = {}

---Parse a string that may contain path with line/column information.
---Delegates the actual format matching to lib.lua.strings.location (same 5
---formats), adapted back to this module's own contract: always returns a
---table (never nil), and a matched line with no explicit column defaults to
---col = 1 (lib.nvim's version leaves col nil in that case).
---@param str string Input string (e.g., "path/to/file.lua:42:15")
---@return table location { path: string, line: integer|nil, col: integer|nil }
function M.parse_location(str)
  if not str or str == "" then
    return { path = "", line = nil, col = nil }
  end

  -- Strip leading/trailing whitespace
  str = str:gsub("^%s+", ""):gsub("%s+$", "")

  local result = require("lib.lua.strings.location").parse_location(str)
  if not result then
    return { path = str, line = nil, col = nil }
  end
  result.col = result.col or (result.line and 1 or nil)
  return result
end

---Merge parsed location with existing range, preferring parsed values
---@param parsed table From parse_location { path, line, col }
---@param existing table|nil Existing range { line: integer, col: integer }
---@return table|nil range Merged range or nil if no line info available
function M.merge_ranges(parsed, existing)
  -- If parsed has line info, prefer it
  if parsed and parsed.line then
    return {
      line = parsed.line,
      col = parsed.col or 1,
    }
  end

  -- Otherwise use existing
  if existing and existing.line then
    return {
      line = existing.line,
      col = existing.col or 1,
    }
  end

  -- No line info available
  return nil
end

---Create a GopathResult range from line and column
---@param line integer|nil Line number (1-indexed)
---@param col integer|nil Column number (1-indexed)
---@return table|nil range Range table or nil
function M.create_range(line, col)
  if not line or line == 0 then
    return nil
  end

  return {
    line = math.max(1, line),
    col = math.max(1, col or 1),
  }
end

---Normalize a range to ensure valid values
---@param range table|nil Range table { line: integer, col: integer }
---@return table|nil normalized Normalized range or nil
function M.normalize_range(range)
  if not range then
    return nil
  end

  if not range.line or range.line == 0 then
    return nil
  end

  return {
    line = math.max(1, range.line),
    col = math.max(1, range.col or 1),
  }
end

return M
