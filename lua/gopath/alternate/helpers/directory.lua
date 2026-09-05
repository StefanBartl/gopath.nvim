---@module 'gopath.alternate.helpers.directory'
---@description Directory manipulation utilities for alternate resolution.

local M = {}

-- DEP-01: matches the fallback pattern every other module in this repo
-- already uses, rather than the bare vim.loop this one had.
local uv = vim.uv or vim.loop

---Check if a path exists as a directory.
---@param path string
---@return boolean exists
function M.is_directory(path)
  if type(path) ~= "string" or path == "" then return false end

  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

---Extract directory path from a full file path.
---Handles both Unix and Windows path separators.
---@param filepath string
---@return string|nil dir_path
function M.extract_directory(filepath)
  if not filepath or filepath == "" then return nil end

  -- Normalize to absolute path first
  local abs = vim.fn.fnamemodify(filepath, ":p")

  -- Get directory component
  local dir = vim.fn.fnamemodify(abs, ":h")

  if dir and dir ~= "" and M.is_directory(dir) then return dir end

  return nil
end

---Extract filename from a full file path.
---@param filepath string
---@return string|nil filename
function M.extract_filename(filepath)
  if not filepath or filepath == "" then return nil end

  return vim.fn.fnamemodify(filepath, ":t")
end

---Human-readable byte size, e.g. 512 -> "512 B", 2048 -> "2.0 KB".
---@internal
---@param bytes integer
---@return string
local function human_size(bytes)
  if bytes < 1024 then return bytes .. " B" end
  if bytes < 1024 * 1024 then return string.format("%.1f KB", bytes / 1024) end
  return string.format("%.1f MB", bytes / (1024 * 1024))
end

---Human-readable "modified" recency, e.g. "just now", "5m ago", "3d ago".
---@internal
---@param mtime_sec integer
---@return string
local function human_age(mtime_sec)
  local delta = math.max(0, os.time() - mtime_sec)
  if delta < 60 then return "just now" end
  if delta < 3600 then return math.floor(delta / 60) .. "m ago" end
  if delta < 86400 then return math.floor(delta / 3600) .. "h ago" end
  return math.floor(delta / 86400) .. "d ago"
end

---Best-effort size/mtime summary for `path`, for display in a selection UI.
---Returns nil when the file cannot be stat'ed (e.g. vanished between scan
---and selection) rather than erroring — this is cosmetic, not load-bearing.
---@param path string
---@return string|nil summary  e.g. "2.3 KB, modified 5m ago"
function M.file_meta(path)
  local stat = uv.fs_stat(path)
  if not stat then return nil end
  return string.format("%s, modified %s", human_size(stat.size), human_age(stat.mtime.sec))
end

---Scan directory and return all regular files.
---@param dir_path string
---@return string[]|nil files List of absolute file paths, or nil on error
function M.scan_directory(dir_path)
  ---@diagnostic disable-next-line lib.uv
  local handle = (uv.fs_scandir(dir_path))
  if not handle then return nil end

  local files = {}
  while true do
    ---@diagnostic disable-next-line lib.uv
    local name, type = uv.fs_scandir_next(handle)
    if not name then break end

    -- Only include regular files
    if type == "file" then
      local full_path = dir_path .. "/" .. name
      table.insert(files, full_path)
    end
  end

  return files
end

return M
