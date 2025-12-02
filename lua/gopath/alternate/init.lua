---@module 'gopath.alternate'
---@description Fuzzy file resolution when exact path fails.
---Attempts to find similar files in the target directory and presents them via interactive selection.

local M = {}

---Attempt alternate file resolution when exact match fails.
---@param target_path string The path that failed to resolve
---@param opts table|nil Configuration options
---@return boolean handled True if alternate was found and user selected
function M.try_resolve(target_path, opts)
  if not target_path or target_path == "" then
    return false
  end

  local config = opts or {}
  local threshold = config.similarity_threshold or 75

  -- Step 1: Extract directory from target path
  local dir_helper = require("gopath.alternate.helpers.directory")
  local dir_path = dir_helper.extract_directory(target_path)

  if not dir_path or not dir_helper.is_directory(dir_path) then
    return false
  end

  -- Step 2: Extract target filename
  local target_filename = dir_helper.extract_filename(target_path)
  if not target_filename then
    return false
  end

  -- Step 3: Find similar files
  local matcher = require("gopath.alternate.helpers.matcher")
  local matches = matcher.find_similar_files(dir_path, target_filename, threshold)

  if #matches == 0 then
    return false
  end

  -- Step 4: Present selection via UI
  local ui = require("gopath.alternate.ui")
  return ui.present_selection(matches, target_path)
end

return M
