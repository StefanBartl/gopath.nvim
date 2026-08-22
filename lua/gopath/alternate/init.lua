---@module 'gopath.alternate'
---@description Fuzzy file resolution when exact path fails.
---Attempts to find similar files in the target directory and presents them via
---interactive selection.
---
--- Both entry points are **callback-based**: the picker may be asynchronous
--- (telescope-ui-select, dressing, kit's chooser), so "did the user pick
--- something?" cannot be answered by a return value. `on_done(handled)` fires
--- exactly once; while it is still pending the caller must not fall through to
--- its own not-found handling, or a second dialog lands on top of the picker.
---
--- Opening goes through `gopath.open`, not a raw `vim.cmd(<cmd> .. path)`. That
--- keeps window placement, OS-native separators, the line/col jump and
--- external/PDF routing identical to every other result — and removes the old
--- foot-gun of concatenating a gopath *mode* ("window", "tab") into an Ex
--- command line, where it is not a valid command at all (E492).

local M = {}

---Build a GopathResult for a chosen candidate.
---`exists = true` is safe: candidates come from a real directory listing / the
---filesystem cache, and it keeps `gopath.open` from offering to create them.
---@internal
---@param path string
---@param range GopathRange|nil
---@return GopathResult
local function result_for(path, range)
  return {
    language = vim.bo.filetype or "text",
    kind = "file",
    path = path,
    range = range,
    chain = nil,
    source = "alternate",
    confidence = 0.7,
    exists = true,
  }
end

---Present candidates and open whichever one the user picks.
---@internal
---@param matches AlternateMatch[]
---@param original_path string
---@param opts AlternateOpts
---@param on_done fun(handled: boolean)
---@return nil
local function present(matches, original_path, opts, on_done)
  require("gopath.alternate.ui").present_selection(matches, original_path, {
    on_choice = function(match)
      -- Cancelling means "none of these". Report it as handled so the caller
      -- aborts instead of falling through to the create-offer — chaining a
      -- second dialog onto a dismissed one is exactly what the user said no to.
      if not (match and match.path) then
        on_done(true)
        return
      end

      require("gopath.open").open(result_for(match.path, opts.range), opts.mode or "edit")
      on_done(true)
    end,
  })
end

---Attempt alternate file resolution when exact match fails.
---@param target_path string The path that failed to resolve
---@param opts AlternateOpts|nil
---@param on_done fun(handled: boolean)|nil  called once; false = nothing shown
---@return nil
function M.try_resolve(target_path, opts, on_done)
  on_done = on_done or function() end
  opts = opts or {}

  if not target_path or target_path == "" then return on_done(false) end

  local threshold = opts.similarity_threshold or 75

  -- Step 1: Extract directory from target path
  local dir_helper = require("gopath.alternate.helpers.directory")
  local dir_path = dir_helper.extract_directory(target_path)

  if not dir_path or not dir_helper.is_directory(dir_path) then return on_done(false) end

  -- Step 2: Extract target filename
  local target_filename = dir_helper.extract_filename(target_path)
  if not target_filename then return on_done(false) end

  -- Step 3: Find similar files
  local matcher = require("gopath.alternate.helpers.matcher")
  local matches = matcher.find_similar_files(dir_path, target_filename, threshold)

  if #matches == 0 then return on_done(false) end

  -- Step 4: Present selection via UI
  present(matches, target_path, opts, on_done)
end

---Attempt alternate resolution with pre-computed matches.
---Used by truncated path resolution when multiple files were found.
---@param matches AlternateMatch[] Pre-formatted matches with similarity scores
---@param original_path string Original path that failed to resolve
---@param opts AlternateOpts|nil
---@param on_done fun(handled: boolean)|nil  called once; false = nothing shown
---@return nil
function M.try_resolve_with_matches(matches, original_path, opts, on_done)
  on_done = on_done or function() end
  opts = opts or {}

  if not matches or #matches == 0 then return on_done(false) end

  present(matches, original_path, opts, on_done)
end

return M
