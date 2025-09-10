---@module 'gopath.resolvers.common.help'
---@brief Build :help subjects for vim, vim.api, vim.fn, vim.loop.

local M = {}

-- Extract token around cursor (best-effort, avoids heavy deps).
local function token_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col1 = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-based
  local left  = line:sub(1, col1):match("([%w_%.]+)%s*$")
  local right = line:sub(col1 + 1):match("^([%w_%.%(%)]*)")
  local tok = (left or "") .. (right or "")
  if tok == "" then
    tok = vim.fn.expand("<cword>")
  end
  return tok or ""
end

-- Map token to :help subject.
local function build_subject(tok)
  if tok == "vim" then return "vim" end
  if tok == "vim.api" or tok:find("^vim%.api$") then return "vim.api" end
  if tok == "vim.fn"  or tok:find("^vim%.fn$")  then return "vim.fn" end

  -- vim.api.<fn>
  local api_fn = tok:match("^vim%.api%.([%w_]+)$")
  if api_fn then
    return "vim.api." .. api_fn
  end

  -- Bare nvim_* symbol under cursor → assume vim.api.<symbol>
  if tok:match("^nvim_[%w_]+$") then
    return "vim.api." .. tok
  end

  -- vim.fn.<fn> → help `fn()` (without "vim.fn.")
  local fn_name = tok:match("^vim%.fn%.([%w_]+)$")
  if fn_name then
    return fn_name .. "()"
  end

  -- vim.loop → configurable later; default to "vim.loop"
  if tok == "vim.loop" or tok:match("^vim%.loop%.?") then
    return "vim.loop"
  end

  return nil
end

---@return GopathResult|nil
function M.resolve()
  -- No aggressive scanning: quick check only when token looks like vim.*
  local tok = token_under_cursor()
  if tok == "" then return nil end
  if not (tok:find("^vim") or tok:match("^nvim_[%w_]+$")) then
    return nil
  end

  local subject = build_subject(tok)
  if not subject then return nil end

  return {
    language   = "help",
    kind       = "help",
    path       = nil,
    subject    = subject,
    range      = nil,
    chain      = nil,
    source     = "builtin",
    confidence = 1.0,
  }
end

return M

