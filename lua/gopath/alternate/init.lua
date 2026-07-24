---@module 'gopath.alternate'
---@description Fuzzy file resolution when exact path fails.
---Attempts to find similar files in the target directory and presents them via interactive selection.

local M = {}

---Attempt alternate file resolution when exact match fails.
---@param target_path string The path that failed to resolve
---@param opts table|nil Configuration options
---@return boolean handled True if alternate was found and user selected
function M.try_resolve(target_path, opts)
  if not target_path or target_path == "" then return false end

  local config = opts or {}
  local threshold = config.similarity_threshold or 75
  local open_cmd = config.open_cmd or "edit"

  -- Step 1: Extract directory from target path
  local dir_helper = require("gopath.alternate.helpers.directory")
  local dir_path = dir_helper.extract_directory(target_path)

  if not dir_path or not dir_helper.is_directory(dir_path) then return false end

  -- Step 2: Extract target filename
  local target_filename = dir_helper.extract_filename(target_path)
  if not target_filename then return false end

  -- Step 3: Find similar files
  local matcher = require("gopath.alternate.helpers.matcher")
  local matches = matcher.find_similar_files(dir_path, target_filename, threshold)

  if #matches == 0 then return false end

  -- Step 4: Present selection via UI
  local ui = require("gopath.alternate.ui")
  return ui.present_selection(matches, target_path, {
    open_cmd = open_cmd,
    line = config.line,
    col = config.col,
  })
end

---Attempt alternate resolution with pre-computed matches
---Used by truncated path resolution when multiple files found
---
---@param matches table[] Pre-formatted matches with similarity scores
---@param original_path string Original path that failed to resolve
---@param opts table|nil Options:
---  - open_cmd: string - Command to use for opening (edit/split/vsplit/tabedit)
---@return boolean handled True if user selected a file
function M.try_resolve_with_matches(matches, original_path, opts)
  opts = opts or {}
  local open_cmd = opts.open_cmd or "edit"

  if not matches or #matches == 0 then return false end

  -- === Show Selection UI ===
  local ui = require("gopath.alternate.ui")
  return ui.present_selection(matches, original_path, {
    open_cmd = open_cmd,
    line = opts.line,
    col = opts.col,
  })
end

return M
