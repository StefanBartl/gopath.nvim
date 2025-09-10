---@module 'gopath.resolvers.common.help'
---@brief Build :help subjects for vim, vim.api, vim.fn, vim.loop.

local M = {}

local function token_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local col1 = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1-based
  local left  = line:sub(1, col1):match("([%w_%.%[%]\"']+)%s*$")
  local right = line:sub(col1 + 1):match("^([%w_%.%[%]\"'%(%)]*)")
  local tok = (left or "") .. (right or "")
  if tok == "" then tok = vim.fn.expand("<cword>") or "" end

  -- normalize bracket notation: vim.api["foo"] -> vim.api.foo
  tok = tok
    :gsub('%["([%w_]+)"%]', '.%1')
    :gsub("%['([%w_]+)'%]", ".%1")

  -- strip call parens for matching: foo(  -> foo
  tok = (tok:match("^[^%(]+") or tok):gsub("%s+$", "")

  return tok
end

local function build_subjects(tok)
  -- Simple namespaces
  if tok == "vim"       then return { "vim" } end
  if tok == "vim.api"   then return { "vim.api" } end
  if tok == "vim.fn"    then return { "vim.fn" } end
  if tok == "vim.loop"  then return { "vim.loop", "luv" } end -- fallback zu luv

  -- vim.api.<fn>  → :h <fn>()
  local api_fn = tok:match("^vim%.api%.([%w_]+)$")
  if api_fn then
    return { api_fn .. "()", "vim.api" }
  end

  -- bare nvim_*     → :h nvim_*()
  if tok:match("^nvim_[%w_]+$") then
    return { tok .. "()", "vim.api" }
  end

  -- vim.fn.<fn>     → :h <fn>()
  local fn_name = tok:match("^vim%.fn%.([%w_]+)$")
  if fn_name then
    return { fn_name .. "()", "vim.fn" }
  end

  -- vim.loop.<something> → keine einzelnen Tags; auf Übersicht fallen
  if tok:match("^vim%.loop%.") then
    return { "vim.loop", "luv" }
  end

  return nil
end

---@return {language:string, kind:string, subject:string} | nil
function M.resolve()
  local tok = token_under_cursor()
  if tok == "" then return nil end

  local subjects = build_subjects(tok)
  if not subjects then return nil end

  -- wir liefern nur Daten; das Öffnen entscheidet der Opener
  return {
    language   = "help",
    kind       = "help",
    subject    = subjects[1],    -- Primärkandidat
    -- kleine Erweiterung: wir übergeben die gesamte Kandidatenliste via Zusatzfeld
    subjects   = subjects,       -- (Opener kann versuchen: first match wins)
    source     = "builtin",
    confidence = 1.0,
  }
end

return M
