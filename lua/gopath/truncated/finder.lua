---@module 'gopath.truncated.finder'
---@brief Live filesystem search for truncated path tails.
--- Called by gopath.truncated when the in-memory cache misses.
--- Tries fd/fdfind first, falls back to rg.

local M = {}
local uv = vim.uv or vim.loop

---@return string|nil  "fd" | "fdfind" | "rg" | nil
local function detect_tool()
  for _, bin in ipairs({ "fd", "fdfind" }) do
    if vim.fn.executable(bin) == 1 then return bin end
  end
  if vim.fn.executable("rg") == 1 then return "rg" end
  return nil
end

---Whether `abs` ends with `tail` on a segment boundary.
---@param abs string
---@param tail string
---@return boolean
local function path_ends_with(abs, tail)
  abs  = (abs  or ""):gsub("\\", "/")
  tail = (tail or ""):gsub("\\", "/")
  if #tail > #abs then return false end
  if abs:sub(-#tail) ~= tail then return false end
  if #abs == #tail then return true end
  return abs:sub(#abs - #tail, #abs - #tail) == "/"
end

---Search one root directory for files whose basename matches the tail's filename.
---All results are filtered by path_ends_with.
---@param tail string  e.g. "neo-tree/ui/renderer.lua"
---@param root string  directory to search
---@param tool string  "fd" | "fdfind" | "rg"
---@return string[]
local function search_root(tail, root, tool)
  local basename = tail:match("([^/]+)$") or tail
  local cmd
  if tool == "fd" or tool == "fdfind" then
    cmd = { tool, "--type", "f", "--hidden", "--follow", "--no-ignore-vcs",
            basename, root }
  else
    cmd = { "rg", "--files", "--hidden", "-g", basename, root }
  end

  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok or not proc then return {} end
  local res = proc:wait()
  if not res or res.code ~= 0 or not res.stdout or res.stdout == "" then
    return {}
  end

  local out = {}
  for line in res.stdout:gmatch("[^\r\n]+") do
    if line ~= "" then
      local norm = vim.fs.normalize(line)
      if path_ends_with(norm, tail) then
        out[#out + 1] = norm
      end
    end
  end
  return out
end

---Find files whose absolute path ends with `tail`.
---@param tail string  cleaned tail (no :line:col, normalized slashes)
---@param opts table|nil  { roots?: string[], limit?: integer }
---@return string[]  absolute paths, sorted by root priority
function M.find(tail, opts)
  if not tail or tail == "" then return {} end
  opts = opts or {}

  local roots = opts.roots
  if not roots or #roots == 0 then
    local cwd = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
    roots = {}
    if cwd and cwd ~= "" then roots[#roots + 1] = cwd end
    for _, sp in ipairs({ "config", "data", "cache" }) do
      local p = vim.fn.stdpath(sp)
      if type(p) == "string" and p ~= "" then roots[#roots + 1] = p end
    end
  end

  local tool = detect_tool()
  if not tool then
    vim.notify("[gopath] truncated.finder: no external search tool (install fd or rg)",
      vim.log.levels.WARN)
    return {}
  end

  local limit   = opts.limit or 100
  local seen    = {}
  local results = {}

  for _, root in ipairs(roots) do
    for _, p in ipairs(search_root(tail, root, tool)) do
      if not seen[p] then
        seen[p] = true
        results[#results + 1] = p
        if #results >= limit then return results end
      end
    end
  end

  return results
end

return M
