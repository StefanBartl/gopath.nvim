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

  -- extract :line[:col] at the end (we keep numbers to return range)
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

  -- strip leading ".../" that shows up in error traces
  s = s:gsub("^%.%.%./", "")

  return s, line, col
end

---@return GopathResult|nil
function M.resolve()
  local raw = P.expand_cfile()
  if not raw then return nil end

  local token, line, col = clean_token(raw)
  if not token or token == "" then return nil end

  -- 1) direct: absolute/relative with &path and &suffixesadd
  local abs = U.search_with_vim_path(token)
  if not abs then
    -- 2) if token contains ".../lua/<tail>", try <tail> in &rtp (and lua/<tail> via helper)
    local tail = token:match("/lua/(.+)$")
    if tail then
      abs = U.search_in_rtp({ tail })
    end
  end
  if not abs then
    -- 3) generic tail: try last 2-3 segments on &rtp (useful for long trimmed paths)
    local segs = vim.split(token, "/", { trimempty = true, plain = true })
    for k = math.max(1, #segs - 2), math.max(1, #segs - 1) do
      local t = table.concat(segs, "/", k)
      abs = U.search_in_rtp({ t })
      if abs then break end
    end
  end
  if not abs then return nil end

  return {
    language   = vim.bo.filetype or "text",
    kind       = "module",
    path       = abs,
    range      = (line and { line = line, col = col or 1 }) or nil,
    chain      = nil,
    source     = "builtin",
    confidence = 0.75,
  }
end

return M
