---@module 'gopath.alternate.ui'
---@description Interactive selection UI for alternate file candidates.
---
--- This module only *picks*; it never opens anything. The caller decides what a
--- chosen candidate means and routes it through `gopath.open` — which is what
--- gives alternates the same window placement, OS-native paths, line/col jump
--- and external/PDF handling as every other result.
---
--- The result is reported through a callback, not a return value. It used to
--- return a boolean assigned inside the picker callback, which is only ever
--- correct for a *synchronous* picker: with telescope-ui-select / dressing /
--- fzf-lua / kit's own chooser that callback fires later, so the caller always
--- saw `false` and carried on as if nothing had been picked — opening the
--- missing file and (since create-on-missing landed) stacking a create dialog
--- on top of the still-open picker.

local M = {}

---Present similar files and report the chosen one via `opts.on_choice`.
---Respects the user's configured UI backend: `kit.select` with
---`respect_override` defers to `vim.ui.select` when something has replaced it,
---and otherwise uses kit's themed chooser. Falls back to plain `vim.ui.select`
---if lib.nvim is unavailable.
---
---@param matches AlternateMatch[]  candidates, best first
---@param original_path string      the path that failed to resolve
---@param opts AlternateSelectOpts  { on_choice }
---@return nil
function M.present_selection(matches, original_path, opts)
  local on_choice = (opts or {}).on_choice or function() end

  if not matches or #matches == 0 then
    on_choice(nil)
    return
  end

  local dir_helper = require("gopath.alternate.helpers.directory")

  -- Show: "filename (85%) — 2.3 KB, modified 5m ago"
  ---@param match AlternateMatch
  ---@return string
  local function format_item(match)
    local display = string.format("  %s (%.0f%%)", match.filename, match.similarity)
    local meta = dir_helper.file_meta(match.path)
    if meta then display = display .. " — " .. meta end
    return display
  end

  local title =
    string.format("File not found: %s - Select alternate:", vim.fn.fnamemodify(original_path, ":t"))

  local ok_kit, kit = pcall(require, "lib.nvim.ui.kit")
  if ok_kit and type(kit.select) == "function" then
    kit.select({
      items = matches,
      respect_override = true,
      title = title,
      format_item = format_item,
      on_select = function(item)
        on_choice(item)
      end,
      on_cancel = function()
        on_choice(nil)
      end,
    })
    return
  end

  vim.ui.select(matches, { prompt = title, format_item = format_item }, function(item)
    -- vim.ui.select signals cancellation with nil — same contract as on_choice.
    on_choice(item)
  end)
end

return M
