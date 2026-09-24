---@module 'gopath.util.selection'
---@brief Shared single-line visual-selection span helper.
---@description
--- The `'<`/`'>` marks persist long after Visual mode ends, so a caller must
--- already know -- via its own `opts.selection` flag, e.g. from a
--- range-aware usercmd (`ctx.range.range > 0`) -- that this invocation
--- genuinely follows a selection before trusting them. This module doesn't
--- guess that; it only turns already-trustworthy marks into a span.
---
--- Deliberately narrower than `gopath.commands`' own private
--- `get_visual_selection()` (which folds a linewise/multi-line selection
--- back to "the whole first line" for probing): callers here need to
--- replace an exact span in place, and a whole-line fallback would silently
--- replace text outside what the user actually selected. Multi-line is
--- reported as "no span" instead; callers fall back to their own
--- whole-line/whole-buffer behavior.

local M = {}

---@class GopathSelectionSpan
---@field row integer  1-indexed buffer line
---@field start_col integer  1-indexed, inclusive
---@field end_col integer  1-indexed, inclusive
---@field line string  the full line text at `row`

---The current single-line visual selection, or nil for an empty selection,
---a multi-line one, or one that resolves to only whitespace.
---@return GopathSelectionSpan|nil
function M.span()
  ---@diagnostic disable-next-line: deprecated
  local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
  ---@diagnostic disable-next-line: deprecated
  local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
  if srow == 0 or erow == 0 then return nil end
  if srow ~= erow then return nil end

  local line = vim.api.nvim_buf_get_lines(0, srow - 1, srow, false)[1] or ""
  -- ecol is MAXCOL for a linewise selection; clamping keeps sub() in range.
  local i = math.min(scol + 1, #line + 1)
  local j = math.min(ecol + 1, #line + 1)
  if j < i then
    i, j = j, i
  end
  if line:sub(i, j):match("^%s*$") then return nil end

  return { row = srow, start_col = i, end_col = j, line = line }
end

return M
