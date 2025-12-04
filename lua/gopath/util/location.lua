---@module 'gopath.util.location'
---@brief Parse and merge file locations with line/column information.

local M = {}

---Parse a string that may contain path with line/column information
---@param str string Input string (e.g., "path/to/file.lua:42:15")
---@return table location { path: string, line: integer|nil, col: integer|nil }
function M.parse_location(str)
  if not str or str == "" then
    return { path = "", line = nil, col = nil }
  end

  -- Strip leading/trailing whitespace
  str = str:gsub("^%s+", ""):gsub("%s+$", "")

  -- Format 1: path:line:col (most specific)
  local path, line, col = str:match("^(.+):(%d+):(%d+)$")
  if path and line and col then
    return {
      path = path,
      line = tonumber(line),
      col = tonumber(col),
    }
  end

  -- Format 2: path:line (very common)
  path, line = str:match("^(.+):(%d+)$")
  if path and line then
    return {
      path = path,
      line = tonumber(line),
      col = 1,
    }
  end

  -- Format 3: path(line:col) (some error formats)
  path, line, col = str:match("^(.+)%((%d+):(%d+)%)$")
  if path and line and col then
    return {
      path = path,
      line = tonumber(line),
      col = tonumber(col),
    }
  end

  -- Format 4: path(line) (error message style)
  path, line = str:match("^(.+)%((%d+)%)$")
  if path and line then
    return {
      path = path,
      line = tonumber(line),
      col = 1,
    }
  end

  -- Format 5: path +line (vim-style, with space before +)
  path, line = str:match("^(.+)%s+%+(%d+)$")
  if path and line then
    return {
      path = path,
      line = tonumber(line),
      col = 1,
    }
  end

  -- No location info found
  return {
    path = str,
    line = nil,
    col = nil,
  }
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
