local M = {}

---@param res GopathResult
---@param opts { target?: "edit"|"window"|"tab" }|nil
function M.open(res, opts)
  if not res or res.kind ~= "help" then return end
  local subject = res.subject
  if type(subject) ~= "string" or subject == "" then
    return  -- nothing to open
  end

  local target = (opts and opts.target) or "edit"
  local esc = vim.fn.escape(subject, " ")

  if target == "tab" then
    vim.cmd(("tab help %s"):format(esc))
    return
  end
  if target == "window" then
    vim.cmd(("belowright help %s"):format(esc))
    return
  end
  vim.cmd(("help %s"):format(esc))
end

return M
