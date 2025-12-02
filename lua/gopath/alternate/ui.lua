---@module 'gopath.alternate.ui'
---@description Interactive selection UI for alternate file candidates.

local M = {}

---Present similar files in an interactive selection window.
---Uses vim.ui.select for native Neovim UI integration.
---@param matches table[] List of {path, similarity, filename}
---@param original_path string The original path that failed
---@return boolean handled True if user selected a file
function M.present_selection(matches, original_path)
  if not matches or #matches == 0 then
    return false
  end

  -- Format items for display: "filename (85%)"
  local items = {}
  for _, match in ipairs(matches) do
    local display = string.format("%s (%.0f%%)", match.filename, match.similarity)
    table.insert(items, display)
  end

  -- Track if user made a selection
  local selected = false

  vim.ui.select(items, {
    prompt = string.format("File not found: %s - Select alternate:", vim.fn.fnamemodify(original_path, ":t")),
    format_item = function(item)
      return "  " .. item
    end,
  }, function(_, index)
    if not index then
      return -- User cancelled
    end

    local match = matches[index]
    if match and match.path then
      -- Open selected file
      vim.cmd("edit " .. vim.fn.fnameescape(match.path))
      selected = true
    end
  end)

  return selected
end

return M
