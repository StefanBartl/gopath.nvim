---@module 'gopath.open.help'
--- Open a :help subject in current window / split / tab, trying fallbacks.

local M = {}

---Attempt `:help subject`, placing it via `target` ("tab"/"window"/current).
---@internal
---@param subject string
---@param target "edit"|"window"|"tab"|nil
---@return boolean ok
local function try_help(subject, target)
  local cmd = (target == "tab" and "tab help %s")
    or (target == "window" and "belowright help %s")
    or "help %s"
  return pcall(function()
    return vim.cmd((cmd):format(vim.fn.escape(subject, " ")))
  end)
end

---Open a `:help` result, trying each candidate subject, then a paren-toggled
---variant of each, then falling back to `:helpgrep` and finally `:help vim.api`.
---@param res { kind:string, subject:string|nil, subjects:string[]|nil }
---@param opts { target?: "edit"|"window"|"tab" }|nil
---@return nil
function M.open(res, opts)
  if not (res and res.kind == "help") then return end
  local target = (opts and opts.target) or "edit"

  -- Build candidate list
  local cands = {}
  if type(res.subjects) == "table" then
    for _, s in ipairs(res.subjects) do
      cands[#cands + 1] = s
    end
  elseif type(res.subject) == "string" then
    cands[1] = res.subject
  end

  -- Try the candidates directly
  for _, subj in ipairs(cands) do
    local ok = try_help(subj, target)
    if ok then return end
  end

  -- Fallback: toggle the trailing-parens variant
  local extra = {}
  for _, s in ipairs(cands) do
    if s:sub(-2) == "()" then
      table.insert(extra, s:sub(1, -3)) -- without ()
    else
      table.insert(extra, s .. "()") -- with ()
    end
  end
  for _, subj in ipairs(extra) do
    local ok = try_help(subj, target)
    if ok then return end
  end

  -- Last resort: search the help index (without UI spam)
  local needle = cands[1] or "help"
  pcall(function()
    vim.cmd("silent! helpgrep " .. vim.fn.escape(needle, " "))
  end)
  local qf = vim.fn.getqflist({ size = true })
  if qf and qf.size and qf.size > 0 then
    -- Open the first match
    pcall(function()
      vim.cmd("cfirst")
    end)
    return
  end

  --- CDX: nothing found, falls back to `:help vim.api` as a generic landing
  --- page; unclear if this silent fallback is desired or should notify instead
  pcall(function()
    vim.cmd("help vim.api")
  end)
end

return M
