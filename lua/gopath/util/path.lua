---@module 'gopath.util.path'
---@brief Path helpers: join/exists and searches (rtp, &path, suffixesadd, package.path).

local M = {}

---@param ... string
---@return string
function M.join(...)
  local parts = { ... }
  for i = 1, #parts do
    local s = parts[i] or ""
    s = s:gsub("[/\\]+", "/")
    if s:sub(-1) == "/" and i < #parts then
      s = s:sub(1, -2)
    end
    parts[i] = s
  end
  return table.concat(parts, "/")
end

---@param p string
---@return boolean
function M.exists(p)
  if not p or p == "" then return false end
  local st = vim.loop.fs_stat(p)
  return st ~= nil and st.type == "file"
end

---@param candidates string[]
---@return string|nil
function M.search_in_rtp(candidates)
  if not candidates or #candidates == 0 then return nil end
  local rtp = vim.split(vim.o.runtimepath or "", ",", { trimempty = true })
  for i = 1, #rtp do
    local base = rtp[i]
    for j = 1, #candidates do
      local p = M.join(base, candidates[j])
      if M.exists(p) then return p end
    end
    for j = 1, #candidates do
      local p = M.join(base, "lua", candidates[j])
      if M.exists(p) then return p end
    end
  end
  local cwd = vim.loop.cwd()
  for j = 1, #candidates do
    local p = M.join(cwd, candidates[j])
    if M.exists(p) then return p end
  end
  return nil
end

---@param token string
---@return string|nil
function M.search_with_vim_path(token)
  if not token or token == "" then return nil end
  if M.exists(token) then
    return vim.fn.fnamemodify(token, ":p")
  end
  local found = vim.fn.findfile(token, vim.o.path)
  if type(found) == "string" and found ~= "" and M.exists(found) then
    return vim.fn.fnamemodify(found, ":p")
  end
  local suffixes = vim.split(vim.o.suffixesadd or "", ",", { trimempty = true })
  for i = 1, #suffixes do
    local cand = token .. suffixes[i]
    local f = vim.fn.findfile(cand, vim.o.path)
    if type(f) == "string" and f ~= "" and M.exists(f) then
      return vim.fn.fnamemodify(f, ":p")
    end
  end
  return nil
end

--- Resolve Lua module via package.path (useful for external/local require paths).
---@param module string  -- "a.b.c"
---@return string|nil
function M.search_with_package_path(module)
  if type(module) ~= "string" or module == "" then return nil end
  local pattern = package and package.path or nil
  if not pattern or pattern == "" then return nil end
  local path = package.searchpath(module, pattern)
  if type(path) == "string" and M.exists(path) then
    return vim.fn.fnamemodify(path, ":p")
  end
  return nil
end

return M
