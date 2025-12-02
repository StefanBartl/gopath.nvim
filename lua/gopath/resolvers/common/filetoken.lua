---@module 'gopath.resolvers.common.filetoken'
---@brief Resolve <cfile> from messages/Noice: strip ".../", :line[:col], and search rtp.

local P = require("gopath.providers.builtin")
local U = require("gopath.util.path")

local M = {}

local function clean_token(raw)
  if not raw or raw == "" then return nil end

  local s = raw
  -- trim
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  -- strip quotes
  s = s:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")

  -- extract :line[:col] at the end
  local line, col
  local l2, c2 = s:match(":(%d+):(%d+)$")
  local l1     = s:match(":(%d+)$")

  if l2 and c2 then
    line, col = tonumber(l2), tonumber(c2)
    s = s:gsub(":%d+:%d+$", "")
  elseif l1 then
    line, col = tonumber(l1), 1
    s = s:gsub(":%d+$", "")
  end

  -- strip leading ".../" from error traces
  s = s:gsub("^%.%.%./", "")

  return s, line, col
end

---@return GopathResult|nil
function M.resolve()
  local raw = P.expand_cfile()
  if not raw then return nil end

  local token, line, col = clean_token(raw)
  if not token or token == "" then return nil end

  -- Try to find file in various locations
  local abs = U.search_with_vim_path(token)

  if not abs then
    local tail = token:match("/lua/(.+)$")
    if tail then
      abs = U.search_in_rtp({ tail })
    end
  end

  if not abs then
    local segs = vim.split(token, "/", { trimempty = true, plain = true })
    for k = math.max(1, #segs - 2), math.max(1, #segs - 1) do
      local t = table.concat(segs, "/", k)
      abs = U.search_in_rtp({ t })
      if abs then break end
    end
  end

  -- NEW: Always return a result, even if file doesn't exist
  -- This allows alternate resolution and external opening to work
  if not abs then
    -- Build best-guess absolute path
    local cwd = vim.fn.expand("%:p:h")
    if token:match("^/") or token:match("^[A-Za-z]:") then
      abs = token  -- Already absolute
    else
      abs = vim.fn.fnamemodify(cwd .. "/" .. token, ":p")
    end
  end

  -- Check if file actually exists
  local exists = U.exists(abs)

  return {
    language   = vim.bo.filetype or "text",
    kind       = exists and "module" or "file",
    path       = abs,
    range      = (line and { line = line, col = col or 1 }) or nil,
    chain      = nil,
    source     = "builtin",
    confidence = exists and 0.75 or 0.3,  -- Lower confidence if file doesn't exist
    exists     = exists,  -- NEW: Flag for downstream handlers
  }
end

return M
