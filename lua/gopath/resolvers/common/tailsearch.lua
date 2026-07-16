---@module 'gopath.resolvers.common.tailsearch'
---@brief Resolve path tokens by suffix-searching the filesystem.
--- Works for partial, relative, and truncated paths (with or without "..." prefix)
--- by matching path tails against multiple search roots via vim.fs.find.
---
--- Modes:
---   resolve_cached(tail, opts) → GopathResult|nil  -- pipeline fast path, cache only (never blocks)
---   resolve_async(tail, opts, on_done, on_live_start) -- cache → async live walk (non-blocking)
---   resolve_sync(tail, opts) → GopathResult|nil    -- cache → blocking vim.fs.find (direct callers)
---   probe(raw, opts, on_done)                       -- for commands (async, with vim.ui.select)

local M = {}
local uv = vim.uv or vim.loop

-- ── Internal helpers ─────────────────────────────────────────────────────────

local function normalize(p)
  if type(p) ~= "string" then return "" end
  local ok, r = pcall(vim.fs.normalize, p)
  return (ok and r) or p
end

local function is_dir(p)
  if type(p) ~= "string" or p == "" then return false end
  local st = uv.fs_stat(p)
  return st ~= nil and st.type == "directory"
end

local function join(a, b)
  if vim.fs.joinpath then return vim.fs.joinpath(a, b) end
  return a:gsub("/+$", "") .. "/" .. b:gsub("^/+", "")
end

local function git_root(dir)
  if not is_dir(dir) then return nil end
  local ok, proc = pcall(vim.system, { "git", "-C", dir, "rev-parse", "--show-toplevel" }, { text = true })
  if not ok or not proc then return nil end
  local res = proc:wait()
  if not res or res.code ~= 0 or not res.stdout or res.stdout == "" then return nil end
  local root = res.stdout:gsub("%s+$", "")
  return is_dir(root) and root or nil
end

local function path_ends_with(abs, tail)
  if type(abs) ~= "string" or type(tail) ~= "string" then return false end
  abs  = abs:gsub("\\", "/")
  tail = tail:gsub("\\", "/")
  if #tail > #abs then return false end
  if abs:sub(-#tail) ~= tail then return false end
  if #abs == #tail then return true end
  return abs:sub(#abs - #tail, #abs - #tail) == "/"
end

-- ── Public utilities ─────────────────────────────────────────────────────────

---Collect sensible search roots in priority order.
---bufdir → cwd → git root → stdpath config/data/cache → extra
---@param extra string[]|nil  additional roots from config
---@return string[]
function M.guess_roots(extra)
  local seen, out = {}, {}
  local function add(p)
    if type(p) ~= "string" or p == "" then return end
    local k = normalize(p)
    if not seen[k] and is_dir(p) then seen[k] = true; out[#out + 1] = p end
  end

  local cwd     = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  local bufname = vim.api.nvim_buf_get_name(0)
  if bufname and bufname ~= "" then add(vim.fs.dirname(bufname)) end
  add(cwd)
  local g = (bufname ~= "" and git_root(vim.fs.dirname(bufname))) or git_root(cwd)
  if g then add(g) end
  for _, sp in ipairs({ "config", "data", "cache" }) do
    local p = vim.fn.stdpath(sp)
    if type(p) == "string" then add(p) end
  end
  if extra then for _, p in ipairs(extra) do add(p) end end
  return out
end

---Build suffix candidates from `tail`, longest-first.
--- e.g. "a/b/c.lua" → { "a/b/c.lua", "b/c.lua", "c.lua" }
---@param tail string
---@param max_components integer
---@return string[]
function M.suffix_candidates(tail, max_components)
  local segs = {}
  for s in tail:gmatch("[^/]+") do if s ~= "" then segs[#segs + 1] = s end end
  local n = #segs
  if n == 0 then return {} end
  local maxc = math.max(1, math.min(max_components or 6, n))
  local out  = {}
  for k = maxc, 1, -1 do
    out[#out + 1] = table.concat(segs, "/", n - k + 1, n)
  end
  return out
end

---Search `roots` for files whose path ends with `tail`.
---@param tail   string
---@param roots  string[]
---@param limit  integer
---@return string[]  normalized absolute paths
function M.find_by_tail(tail, roots, limit)
  local results, total = {}, 0
  local max = math.max(1, limit or 100)
  for _, r in ipairs(roots) do
    local ok, hits = pcall(vim.fs.find, function(name, path)
      return path_ends_with(join(path, name), tail)
    end, { path = r, type = "file", limit = max })
    if ok and type(hits) == "table" then
      for _, p in ipairs(hits) do
        results[#results + 1] = normalize(p)
        total = total + 1
        if total >= max then return results end
      end
    end
  end
  return results
end

---Pick the shortest (= most specific) path.
---@param matches string[]
---@return string|nil
function M.pick_best(matches)
  local best, blen = nil, math.huge
  for _, m in ipairs(matches) do
    if #m < blen then best, blen = m, #m end
  end
  return best
end

---Look up `tail` in the in-memory truncated-path cache (instant, non-blocking).
---Tries path suffixes longest-first so a truncated leading segment (e.g. the
---"...a" fragment left of "AppData") is dropped until a match is found.
---Returns an empty list when the cache is disabled, empty, or still building.
---@param tail string
---@param max_components integer|nil  longest suffix to try (default 6)
---@return string[]  normalized absolute paths
function M.cache_lookup(tail, max_components)
  if type(tail) ~= "string" or tail == "" then return {} end
  local ok, cache = pcall(require, "gopath.truncated.cache")
  if not ok then return {} end

  -- Longest (most specific) suffix first; return on the first one that hits so
  -- we never fall through to an over-broad single-filename match.
  for _, suf in ipairs(M.suffix_candidates(tail, max_components or 6)) do
    local ok2, hits = pcall(cache.search, suf)
    if ok2 and type(hits) == "table" and #hits > 0 then
      local out = {}
      for _, p in ipairs(hits) do
        out[#out + 1] = normalize(p)
      end
      out = require("lib.lua.tables").dedup_list(out)
      if #out > 0 then return out end
    end
  end
  return {}
end

---Build a GopathResult for a resolved path.
---@param path string
---@param conf number
---@param rng  GopathRange|nil
---@return table
local function make_result(path, conf, rng)
  return { language = vim.bo.filetype or "text", kind = "file",
           path = path, range = rng,
           chain = nil, source = "tailsearch", confidence = conf, exists = true }
end

-- ── Token sanitization ───────────────────────────────────────────────────────

---Strip `:line:col` suffix and clean up a raw token into a path tail.
---@param raw string
---@return string tail, integer|nil line, integer|nil col
function M.sanitize(raw)
  if type(raw) ~= "string" then return "", nil, nil end
  raw = raw:gsub("[%)%]%.,;:]+$", "")  -- trailing punctuation

  local base, l, c = raw:match("^(.-):(%d+):(%d+)$")
  if base then
    base = base:gsub("\\", "/"):gsub('["\''.. "`]+", ""):gsub("^%.*%/*", "")
    return base, tonumber(l), tonumber(c)
  end

  base, l = raw:match("^(.-):(%d+)$")
  if base then
    base = base:gsub("\\", "/"):gsub('["\''.. "`]+", ""):gsub("^%.*%/*", "")
    return base, tonumber(l), nil
  end

  base = raw:gsub("^%u:/", "")       -- drop Windows drive letter
             :gsub("\\", "/")
             :gsub('["\''.. "`]+", "")
             :gsub("^%.*%/*", "")    -- strip leading ellipsis / ./
             :gsub("[^%w%._%-%/]+", "/")
             :gsub("/+", "/")
  return base, nil, nil
end

-- ── Sync resolution (pipeline) ───────────────────────────────────────────────

---Resolve `tail` without UI. Best-match is returned; ambiguous matches pick shortest.
---@param tail string  already sanitized path tail
---@param opts { roots?: string[], max_components?: integer, limit?: integer, line?: integer, col?: integer }
---@return table|nil  GopathResult
function M.resolve_sync(tail, opts)
  if not tail or tail == "" then return nil end
  opts = opts or {}
  local roots    = opts.roots          or M.guess_roots()
  local max_comp = opts.max_components or 6
  local limit    = opts.limit          or 100
  local rng      = (opts.line and opts.line > 0)
                   and { line = opts.line, col = opts.col or 1 } or nil

  -- Cache fast path (instant, in-memory). Avoids the blocking vim.fs.find walk
  -- whenever the truncated-path cache already indexed the target.
  local cached = M.cache_lookup(tail, max_comp)
  if #cached > 0 then
    return make_result(M.pick_best(cached), #cached == 1 and 0.85 or 0.72, rng)
  end

  local candidates = M.suffix_candidates(tail, max_comp)
  local all = {}

  for _, suf in ipairs(candidates) do
    local hits = M.find_by_tail(suf, roots, limit)
    for _, p in ipairs(hits) do
      all[#all + 1] = p
    end
    if #hits == 1 then
      -- unambiguous hit on this suffix → high confidence
      return make_result(hits[1], 0.85, rng)
    end
  end

  all = require("lib.lua.tables").dedup_list(all)
  if #all == 0 then return nil end
  return make_result(M.pick_best(all), 0.72, rng)
end

-- ── Cache-only resolution (pipeline fast path) ────────────────────────────────

---Resolve `tail` using ONLY the in-memory cache. Never touches the filesystem,
---so it is safe to call synchronously inside the resolve pipeline without the
---multi-second freeze that a live `vim.fs.find` walk would cause. Returns nil on
---a cache miss so the caller can fall back to `resolve_async`.
---@param tail string  already sanitized path tail
---@param opts { line?: integer, col?: integer, max_components?: integer }|nil
---@return table|nil  GopathResult
function M.resolve_cached(tail, opts)
  if not tail or tail == "" then return nil end
  opts = opts or {}
  local rng = (opts.line and opts.line > 0)
              and { line = opts.line, col = opts.col or 1 } or nil
  local cached = M.cache_lookup(tail, opts.max_components)
  if #cached == 0 then return nil end
  return make_result(M.pick_best(cached), #cached == 1 and 0.85 or 0.72, rng)
end

-- ── Async resolution (non-blocking live search) ───────────────────────────────

---Resolve `tail` without blocking the UI. Tries the cache first (instant); on a
---miss runs the async libuv filesystem walk. `on_live_start` (if given) fires
---exactly when the slow live search begins, so callers can show a progress
---message only when it is actually needed.
---@param tail string  already sanitized path tail
---@param opts { roots?: string[], limit?: integer, line?: integer, col?: integer, max_components?: integer }|nil
---@param on_done fun(result: table|nil)
---@param on_live_start fun()|nil
function M.resolve_async(tail, opts, on_done, on_live_start)
  if not tail or tail == "" then on_done(nil); return end
  opts = opts or {}
  local rng = (opts.line and opts.line > 0)
              and { line = opts.line, col = opts.col or 1 } or nil

  -- 1) Cache fast path.
  local cached = M.cache_lookup(tail, opts.max_components)
  if #cached > 0 then
    on_done(make_result(M.pick_best(cached), #cached == 1 and 0.9 or 0.8, rng))
    return
  end

  -- 2) Async live filesystem search.
  local ok, finder = pcall(require, "gopath.truncated.finder")
  if not ok then on_done(nil); return end
  if on_live_start then on_live_start() end

  finder.find_async(tail, { roots = opts.roots, limit = opts.limit or 100 }, function(hits)
    if not hits or #hits == 0 then on_done(nil); return end
    on_done(make_result(M.pick_best(hits), #hits == 1 and 0.9 or 0.8, rng))
  end)
end

-- ── Async probe (for commands) ───────────────────────────────────────────────

---Full probe flow: sanitize → search → disambiguate (vim.ui.select on ambiguity).
---Calls `on_done(GopathResult|nil)` when finished (may be async if user sees picker).
---@param raw     string  raw token from visual selection or <cfile>
---@param opts    { roots?: string[], max_components?: integer, limit?: integer, ask?: boolean }
---@param on_done fun(result: table|nil)
function M.probe(raw, opts, on_done)
  if not raw or raw == "" then on_done(nil); return end
  opts = opts or {}

  local tail, line_nr, col_nr = M.sanitize(raw)
  if tail == "" then on_done(nil); return end

  local roots    = opts.roots          or M.guess_roots()
  local max_comp = opts.max_components or 6
  local limit    = opts.limit          or 100
  local ask      = opts.ask ~= false
  local rng      = (line_nr and line_nr > 0)
                   and { line = line_nr, col = col_nr or 1 } or nil

  local _ = max_comp  -- suffix expansion handled by cache + tail-suffix match

  local function probe_result(path, conf)
    return { language = vim.bo.filetype or "text", kind = "file",
             path = path, range = rng,
             chain = nil, source = "tailsearch", confidence = conf, exists = true }
  end

  ---Disambiguate `matches` and report the chosen result.
  ---@param matches string[]
  ---@param base_conf number
  local function finish(matches, base_conf)
    if #matches == 0 then on_done(nil); return end
    if #matches == 1 or not ask then
      on_done(probe_result(M.pick_best(matches), base_conf))
      return
    end
    vim.ui.select(matches, {
      prompt = "gopath: multiple matches — pick one",
      format_item = function(item)
        local r0 = roots[1]
        if type(r0) == "string" and #r0 > 1 and item:sub(1, #r0) == r0 then
          return "./" .. item:sub(#r0 + 2)
        end
        return item
      end,
    }, function(choice)
      on_done(choice and probe_result(choice, 0.85) or nil)
    end)
  end

  -- 1) Cache fast path (instant).
  local cached = M.cache_lookup(tail, max_comp)
  if #cached > 0 then finish(cached, 0.85); return end

  -- 2) Async live search (non-blocking).
  local ok, finder = pcall(require, "gopath.truncated.finder")
  if not ok then on_done(nil); return end
  finder.find_async(tail, { roots = roots, limit = limit }, function(hits)
    finish(hits or {}, 0.85)
  end)
end

return M
