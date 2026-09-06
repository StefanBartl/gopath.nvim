---@module 'gopath.util.url'
---@brief URL detection, cursor extraction and normalization.
---@description
--- Pure string helpers shared by the URL resolver (`gopath.resolvers.common.url`)
--- and the external-file detector (`gopath.external.helpers.detector`).
---
--- Two detection strengths exist, because they carry very different risk:
---
---   • STRICT — an explicit scheme (`https://`, `ftp://`, `mailto:`) or a
---     `www.` prefix. Unambiguous: nothing on disk ever looks like this, so a
---     strict hit may pre-empt the whole file-resolution pipeline.
---
---   • LOOSE — a bare host with a known TLD (`github.com/neovim/neovim`) or an
---     scp-style git remote (`git@github.com:foo/bar.git`). These DO collide
---     with real filenames (`main.co`, `notes.info`), so the loose pass is only
---     ever run after every file resolver has already failed.
---
--- Extraction deliberately works on the raw buffer line rather than on
--- `<cfile>` / `gopath.providers.token`: both stop at `?`, `&` and `#`, which
--- would silently truncate every URL carrying a query string or fragment.

local M = {}

---Schemes recognised by the strict pass.
---@type string[]
M.DEFAULT_SCHEMES = {
  "http",
  "https",
  "ftp",
  "ftps",
  "sftp",
  "ssh",
  "file",
  "git",
  "irc",
  "ircs",
  "magnet",
  "news",
  "gopher",
  "rsync",
}

---Top-level domains accepted by the loose (scheme-less) pass.
---Deliberately conservative: TLDs that double as common source-file
---extensions (`sh`, `pl`, `rs`, `py`, `ts`, `so`, `md`) are omitted, otherwise
---`build.sh` or `main.rs` would be handed to a browser.
---@type string[]
M.DEFAULT_TLDS = {
  -- generic
  "com",
  "org",
  "net",
  "edu",
  "gov",
  "mil",
  "int",
  "info",
  "biz",
  "dev",
  "app",
  "io",
  "ai",
  "xyz",
  "cloud",
  "tech",
  "online",
  "site",
  "blog",
  "wiki",
  "news",
  "shop",
  "store",
  -- country
  "de",
  "at",
  "ch",
  "eu",
  "uk",
  "fr",
  "it",
  "es",
  "nl",
  "be",
  "dk",
  "se",
  "no",
  "fi",
  "cz",
  "hu",
  "ru",
  "jp",
  "cn",
  "kr",
  "us",
  "ca",
  "au",
  "nz",
  "br",
  "mx",
  "za",
  "tv",
}

--- Characters that may appear inside a URL (RFC 3986 unreserved + reserved +
--- percent-escapes). Whitespace, backtick and the angle/quote delimiters are
--- excluded so that `<https://x>` and `"https://x"` end at the right place.
local URL_BODY = "[%w%-%._~:/%?#%[%]@!%$&%(%)%*%+,;=%%]"

---@type table<string, string>  closing bracket → matching opener
local CLOSERS = { [")"] = "(", ["]"] = "[", ["}"] = "{", [">"] = "<" }

---@private
---@param list string[]
---@param extra string[]|nil
---@return table<string, true>
local function to_set(list, extra)
  local set = {}
  for _, v in ipairs(list) do
    set[v:lower()] = true
  end
  for _, v in ipairs(extra or {}) do
    set[tostring(v):lower()] = true
  end
  return set
end

---Strip sentence punctuation and unbalanced closing brackets from the tail.
---`(https://x)` → `https://x`, but `https://x/a_(b)` keeps its balanced pair.
---@private
---@param url string
---@return string
local function trim_trailing(url)
  while #url > 0 do
    local last = url:sub(-1)
    if last:match("[%.,;:!%?'\"]") then
      url = url:sub(1, -2)
    elseif CLOSERS[last] then
      local opener = CLOSERS[last]
      local n_open = select(2, url:gsub("%" .. opener, ""))
      local n_close = select(2, url:gsub("%" .. last, ""))
      if n_close > n_open then
        url = url:sub(1, -2)
      else
        break
      end
    else
      break
    end
  end
  return url
end

---Widen from `col` over URL-legal characters to get the surrounding span.
---@private
---@param line string
---@param col integer 1-based
---@return integer|nil s, integer|nil e
local function span_at(line, col)
  if not line or line == "" then return nil end
  col = math.max(1, math.min(col, #line))
  if not line:sub(col, col):match(URL_BODY) then return nil end

  local s = col
  while s > 1 and line:sub(s - 1, s - 1):match(URL_BODY) do
    s = s - 1
  end
  local e = col
  while e < #line and line:sub(e + 1, e + 1):match(URL_BODY) do
    e = e + 1
  end
  return s, e
end

---Check whether `host` is a plausible bare hostname with a known TLD.
---@private
---@param host string
---@param tld_set table<string, true>
---@return boolean
local function is_known_host(host, tld_set)
  if not host or host == "" then return false end
  local labels = vim.split(host, ".", { plain = true })
  if #labels < 2 then return false end
  for _, label in ipairs(labels) do
    if label == "" or not label:match("^[%w][%w%-]*$") then return false end
  end
  return tld_set[labels[#labels]:lower()] == true
end

---@class GopathUrlOpts
---@field schemes string[]|nil extra schemes, extends DEFAULT_SCHEMES
---@field tlds string[]|nil extra TLDs, extends DEFAULT_TLDS

---Test a complete string for an explicit scheme or a `www.` prefix.
---@param str string
---@param opts GopathUrlOpts|nil
---@return boolean
function M.is_strict_url(str, opts)
  if type(str) ~= "string" or str == "" then return false end
  if str:match("^www%.") then return true end

  local scheme = str:match("^(%a[%w+%-%.]*)://")
  if not scheme then scheme = str:match("^(%a[%w+%-%.]*):[^/\\]") end
  if not scheme then return false end

  -- "C:/tmp" / "C:\tmp" are drive letters, not schemes.
  if #scheme == 1 then return false end

  if scheme:lower() == "mailto" then return true end
  return to_set(M.DEFAULT_SCHEMES, opts and opts.schemes)[scheme:lower()] == true
end

---Test a complete string for a scheme-less host (`github.com/x`) or an
---scp-style git remote (`git@github.com:foo/bar.git`).
---@param str string
---@param opts GopathUrlOpts|nil
---@return boolean
function M.is_loose_url(str, opts)
  if type(str) ~= "string" or str == "" then return false end
  if M.is_strict_url(str, opts) then return false end

  local tld_set = to_set(M.DEFAULT_TLDS, opts and opts.tlds)

  -- scp-style: user@host:path
  local scp_host, scp_path = str:match("^[%w%._%-]+@([%w%.%-]+):([^%s:]+)$")
  if scp_host and scp_path and not scp_path:match("^%d+$") then
    return is_known_host(scp_host, tld_set)
  end

  -- bare host, optionally followed by :port and /path?query#fragment
  local host, rest = str:match("^([%w%.%-]+)(.*)$")
  if not host then return false end
  if rest ~= "" and not rest:match("^[:/%?#]") then return false end
  if rest:match("^:") and not rest:match("^:%d") then return false end
  return is_known_host(host, tld_set)
end

---Turn a recognised URL into something a browser accepts: adds the implicit
---`https://`, and rewrites scp-style git remotes to their web equivalent.
---@param url string
---@param opts GopathUrlOpts|nil
---@return string
function M.normalize(url, opts)
  if type(url) ~= "string" or url == "" then return url end
  -- "www.google.com" is a URL to a human but a relative filename to every
  -- system opener, so it needs the scheme just like a bare host does.
  if url:match("^www%.") then return "https://" .. url end
  if M.is_strict_url(url, opts) then return url end

  local scp_host, scp_path = url:match("^[%w%._%-]+@([%w%.%-]+):([^%s:]+)$")
  if scp_host and scp_path then
    return ("https://%s/%s"):format(scp_host, (scp_path:gsub("%.git$", "")))
  end

  return "https://" .. url
end

---Extract the URL under the cursor from the current buffer line.
---@param mode "strict"|"loose"
---@param opts GopathUrlOpts|nil
---@return string|nil url raw (un-normalized) URL text, or nil
function M.extract_at_cursor(mode, opts)
  local ok, line = pcall(vim.api.nvim_get_current_line)
  if not ok or not line or line == "" then return nil end
  local pos_ok, pos = pcall(vim.api.nvim_win_get_cursor, 0)
  if not pos_ok then return nil end

  local s, e = span_at(line, pos[2] + 1)
  if not s or not e then return nil end
  local span = line:sub(s, e)
  local cursor_in_span = pos[2] + 2 - s

  if mode == "strict" then
    -- Take the last scheme / www. start at or before the cursor, then cut the
    -- candidate before the next one so that "a.com,https://b.com" does not
    -- swallow both halves into one target.
    local start_idx
    local init = 1
    while init <= #span do
      local hit = span:find("%f[%a]%a[%w+%-%.]*://", init)
      for _, alt_pat in ipairs({ "%f[%w]www%.", "%f[%a]mailto:" }) do
        local alt = span:find(alt_pat, init)
        if alt and (not hit or alt < hit) then hit = alt end
      end
      if not hit or hit > cursor_in_span then break end
      start_idx = hit
      init = hit + 1
    end
    if not start_idx then return nil end

    local candidate = span:sub(start_idx)
    local next_scheme = candidate:find("%f[%a]%a[%w+%-%.]*://", 2)
    if next_scheme then candidate = candidate:sub(1, next_scheme - 1) end

    candidate = trim_trailing(candidate)
    if M.is_strict_url(candidate, opts) then return candidate end
    return nil
  end

  -- Loose: the span itself is the candidate; only strip leading delimiters
  -- that the widening pulled in ("(github.com/x" → "github.com/x").
  local candidate = trim_trailing(span):gsub("^[%(%[{<'\"]+", "")
  if M.is_loose_url(candidate, opts) then return candidate end
  return nil
end

return M
