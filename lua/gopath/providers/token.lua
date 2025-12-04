---@module 'gopath.providers.token'
---@brief Smart token extraction that preserves :line:col and other metadata.

local M = {}

---Extract token at cursor position with context awareness
---Preserves :line:col, (line), and other location formats
---@return string|nil token Full token including location info
function M.extract_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1

  -- Path characters: alphanumeric, /, \, -, _, ., :, (, ), +, ~, @
  local path_chars = "[%w/\\%.%-%_:%(%)%+~@]"

  -- Walk backwards to find start
  local start_col = col
  while start_col > 1 do
    local char = line:sub(start_col - 1, start_col - 1)
    if not char:match(path_chars) then
      break
    end
    start_col = start_col - 1
  end

  -- Walk forwards to find end
  local end_col = col
  while end_col <= #line do
    local char = line:sub(end_col, end_col)
    if not char:match(path_chars) then
      break
    end
    end_col = end_col + 1
  end
  end_col = end_col - 1

  if start_col > end_col then
    return nil
  end

  local token = line:sub(start_col, end_col)

  -- Clean token
  token = token:gsub("^%s+", ""):gsub("%s+$", "")  -- Trim whitespace
  token = token:gsub("^%.", "")  -- Strip leading dot (chain context)
  token = token:gsub("%)$", "")  -- Strip trailing paren (function calls)
  token = token:gsub("%($", "")  -- Strip trailing opening paren

  if token == "" then
    return nil
  end

  return token
end

---Fallback to vim's <cfile>
---@return string|nil
function M.expand_cfile()
  local cfile = vim.fn.expand("<cfile>")
  if type(cfile) == "string" and cfile ~= "" then
    return cfile
  end
  return nil
end

---Get token with smart extraction, fallback to <cfile>
---@return string|nil
function M.get_token()
  local custom = M.extract_at_cursor()
  if custom and custom ~= "" then
    return custom
  end
  return M.expand_cfile()
end

return M
