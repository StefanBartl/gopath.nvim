---@module 'gopath.alternate.ui'
---@description Interactive selection UI for alternate file candidates.

local M = {}

---Present similar files in an interactive selection window.
---Respects user's configured UI backend (builtin/telescope/fzf-lua)
---
---@param matches table[] List of {path, similarity, filename}
---@param original_path string The original path that failed
---@param opts table|nil Options:
---  - open_cmd: string - Command for opening selected file
---  - line: integer|nil - 1-based line to jump to after opening
---  - col: integer|nil - 1-based column to jump to after opening
---@return boolean handled True if user selected a file
function M.present_selection(matches, original_path, opts)
  opts = opts or {}
  local open_cmd = opts.open_cmd or "edit"
  local line = opts.line
  local col = opts.col

  if not matches or #matches == 0 then
    return false
  end

  -- === Format Items for Display ===
  -- Show: "filename (85%)"
  local items = {}
  for _, match in ipairs(matches) do
    local display = string.format("%s (%.0f%%)", match.filename, match.similarity)
    table.insert(items, display)
  end

  -- === Track Selection ===
  local selected = false

  -- === Use Native vim.ui.select ===
  -- This respects user's UI backend configuration
  -- (e.g., if they have telescope-ui-select or dressing.nvim installed)
  vim.ui.select(items, {
    prompt = string.format("File not found: %s - Select alternate:", vim.fn.fnamemodify(original_path, ":t")),
    format_item = function(item)
      return "  " .. item
    end,
  }, function(_, index)
    if not index then
      return  -- User cancelled
    end

    local match = matches[index]
    if match and match.path then
      -- === Open Selected File ===
      -- Use the command specified by caller (respects split/vsplit/etc.)
      local ok = pcall(vim.cmd, open_cmd .. " " .. vim.fn.fnameescape(match.path))
      if ok then
        selected = true

        -- Jump to location if the caller provided one (truncated paths carry :line:col)
        if line and line > 0 then
          local c = math.max(0, (col or 1) - 1)
          pcall(vim.api.nvim_win_set_cursor, 0, { line, c })
          pcall(vim.cmd, "normal! zz")
        end
      end
    end
  end)

  return selected
end

return M
