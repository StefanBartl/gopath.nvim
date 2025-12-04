---@module 'gopath.open.edit'
---@brief Open a resolved location in current window, with external file support.

local LOC = require("gopath.util.location")

local M = {}

---@param res GopathResult
function M.open(res)
  if not (res and res.path) then
    return
  end

  -- DEBUG: Show what we received
  if res.range then
    vim.notify(
      string.format("[gopath] Opening with range: line=%s, col=%s",
        tostring(res.range.line),
        tostring(res.range.col)),
      vim.log.levels.DEBUG
    )
  end

  -- Check if file should be opened externally FIRST
  local external = require("gopath.external")
  if external.should_open_externally(res.path) then
    external.open(res.path)
    return
  end

  -- Check if file exists
  if res.exists == false then
    vim.notify(
      string.format("[gopath] File not found: %s", res.path),
      vim.log.levels.ERROR
    )
    return
  end

  -- Open file in current window
  vim.cmd.edit(vim.fn.fnameescape(res.path))

  -- Jump to position if provided (with normalization)
  if res.range then
    local normalized = LOC.normalize_range(res.range)

    if normalized then
      vim.notify(
        string.format("[gopath] Normalized range: line=%d, col=%d",
          normalized.line,
          normalized.col),
        vim.log.levels.DEBUG
      )

      local l = normalized.line
      local c = math.max(0, normalized.col - 1) -- nvim_win_set_cursor uses 0-indexed columns

      local ok, err = pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
      if not ok then
        vim.notify(
          string.format("[gopath] Failed to set cursor: %s", err),
          vim.log.levels.ERROR
        )
      else
        -- Center line in window for visibility
        vim.cmd("normal! zz")

        vim.notify(
          string.format("[gopath] Jumped to line %d, col %d", l, c),
          vim.log.levels.INFO
        )
      end
    else
      vim.notify("[gopath] Could not normalize range", vim.log.levels.WARN)
    end
  else
    vim.notify("[gopath] No range provided in result", vim.log.levels.DEBUG)
  end
end

return M
