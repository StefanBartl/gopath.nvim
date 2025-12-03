---@module 'gopath.open.help'
--- Open a :help subject in current window / split / tab, trying fallbacks.

local M = {}

local function try_help(subject, target)
  local cmd = (target == "tab" and ("tab help %s"))
           or (target == "window" and ("belowright help %s"))
           or ("help %s")
  return pcall(function() return vim.cmd((cmd):format(vim.fn.escape(subject, " "))) end)
end

---@param res { kind:string, subject:string|nil, subjects:string[]|nil }
---@param opts { target?: "edit"|"window"|"tab" }|nil
function M.open(res, opts)
  if not (res and res.kind == "help") then return end
  local target = (opts and opts.target) or "edit"

  -- baue Kandidatenliste
  local cands = {}
  if type(res.subjects) == "table" then
    for _, s in ipairs(res.subjects) do cands[#cands+1] = s end
  elseif type(res.subject) == "string" then
    cands[1] = res.subject
  end

  -- Versuche direkt die Kandidaten
  for _, subj in ipairs(cands) do
    local ok = try_help(subj, target)
    if ok then return end
  end

  -- Fallback: Klammern-Variante togglen
  local extra = {}
  for _, s in ipairs(cands) do
    if s:sub(-2) == "()" then
      table.insert(extra, s:sub(1, -3)) -- ohne ()
    else
      table.insert(extra, s .. "()")    -- mit ()
    end
  end
  for _, subj in ipairs(extra) do
    local ok = try_help(subj, target)
    if ok then return end
  end

  -- Letzter Fallback: Hilfe-Index durchsuchen (ohne UI-Spam)
  local needle = cands[1] or "help"
  pcall(function() vim.cmd("silent! helpgrep " .. vim.fn.escape(needle, " ")) end)
  local qf = vim.fn.getqflist({ size = true })
  if qf and qf.size and qf.size > 0 then
    -- öffne erstes Match
    pcall(function() vim.cmd("cfirst") end)
    return
  end

  -- nichts gefunden? Dezent auf die API-Übersicht fallen AUDIT; ao lassen?
  pcall(function() vim.cmd("help vim.api") end)
end

return M
