---@module 'gopath.truncated.finder'
---@brief Live filesystem search for truncated path tails.
--- Called by gopath.truncated when the in-memory cache misses.
--- Tries fd/fdfind first, falls back to rg.

local LOG = require("gopath.util.log")

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
  abs = (abs or ""):gsub("\\", "/")
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
    cmd = { tool, "--type", "f", "--hidden", "--follow", "--no-ignore-vcs", basename, root }
  else
    cmd = { "rg", "--files", "--hidden", "-g", basename, root }
  end

  local ok, proc = pcall(vim.system, cmd, { text = true })
  if not ok or not proc then return {} end
  local res = proc:wait()
  if not res or res.code ~= 0 or not res.stdout or res.stdout == "" then return {} end

  local out = {}
  for line in res.stdout:gmatch("[^\r\n]+") do
    if line ~= "" then
      local norm = vim.fs.normalize(line)
      if path_ends_with(norm, tail) then out[#out + 1] = norm end
    end
  end
  return out
end

---Default roots when none are supplied: cwd + nvim config/data/cache.
---@return string[]
local function default_roots()
  local cwd = (uv.cwd and uv.cwd()) or vim.fn.getcwd()
  local roots = {}
  if cwd and cwd ~= "" then roots[#roots + 1] = cwd end
  for _, sp in ipairs({ "config", "data", "cache" }) do
    local p = vim.fn.stdpath(sp)
    if type(p) == "string" and p ~= "" then roots[#roots + 1] = p end
  end
  return roots
end

---Find files whose absolute path ends with `tail`.
---@param tail string  cleaned tail (no :line:col, normalized slashes)
---@param opts table|nil  { roots?: string[], limit?: integer }
---@return string[]  absolute paths, sorted by root priority
function M.find(tail, opts)
  if not tail or tail == "" then return {} end
  opts = opts or {}

  local roots = opts.roots
  if not roots or #roots == 0 then roots = default_roots() end

  local tool = detect_tool()
  if not tool then
    LOG.warn("truncated.finder: no external search tool (install fd or rg)")
    return {}
  end

  local limit = opts.limit or 100
  local seen = {}
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

-- ── Async live search (non-blocking) ─────────────────────────────────────────

---Pull excluded-dir / max-depth settings from the truncated config (with
---sensible fallbacks) so the async walk matches the cache's scan behaviour.
---@return table<string, boolean> excluded, integer max_depth
local function walk_settings()
  local excluded = {
    [".git"] = true,
    [".github"] = true,
    [".svn"] = true,
    [".hg"] = true,
    ["node_modules"] = true,
    ["target"] = true,
    ["build"] = true,
    ["dist"] = true,
    [".cache"] = true,
    [".venv"] = true,
    ["venv"] = true,
    ["__pycache__"] = true,
    [".nuxt"] = true,
    [".next"] = true,
    [".turbo"] = true,
    ["tmp"] = true,
    ["temp"] = true,
    ["vendor"] = true,
  }
  local max_depth = 8
  local ok, cfg = pcall(function()
    return require("gopath.config").get()
  end)
  if ok and cfg and cfg.truncated then
    if type(cfg.truncated.excluded_dirs) == "table" then
      excluded = {}
      for _, d in ipairs(cfg.truncated.excluded_dirs) do
        excluded[d] = true
      end
    end
    if type(cfg.truncated.max_depth) == "number" then
      -- allow a couple of extra levels for tail matches that sit deeper than
      -- the cache index would normally reach
      max_depth = cfg.truncated.max_depth + 2
    end
  end
  return excluded, max_depth
end

---Non-blocking variant of `find`. Walks `roots` with bounded concurrency via
---libuv `fs_scandir` (no external tool required) and collects files whose path
---ends with `tail`. Stops early once `limit` matches are found.
---@param tail string  cleaned tail (no :line:col, normalized slashes)
---@param opts table|nil  { roots?: string[], limit?: integer, max_concurrency?: integer }
---@param on_done fun(matches: string[])  called once with all matches (may be async)
function M.find_async(tail, opts, on_done)
  if not tail or tail == "" then
    on_done({})
    return
  end
  opts = opts or {}

  local roots = opts.roots
  if not roots or #roots == 0 then roots = default_roots() end

  local limit = opts.limit or 100
  local concurrency = opts.max_concurrency or 16
  local excluded, max_depth = walk_settings()

  local queue = {} -- pending { dir, depth }
  local seen = {} -- de-dupe matches
  local results = {}
  local active = 0
  local qhead = 1
  local done = false

  for i = 1, #roots do
    if type(roots[i]) == "string" and roots[i] ~= "" then
      queue[#queue + 1] = { dir = roots[i], depth = 0 }
    end
  end

  local function finish()
    if done then return end
    done = true
    -- Always hand control back on the main loop: callers touch vim.* APIs
    -- (vim.bo, vim.cmd, …) that are unsafe in a libuv fast-event context.
    vim.schedule(function()
      on_done(results)
    end)
  end

  local pump -- forward declaration

  local function scan_one(item)
    ---@diagnostic disable-next-line lib.uv
    uv.fs_scandir(item.dir, function(err, handle)
      if done then return end
      if err or not handle then
        active = active - 1
        pump()
        return
      end

      while true do
        ---@diagnostic disable-next-line lib.uv
        local name, typ = uv.fs_scandir_next(handle)
        if not name then break end

        local full = item.dir .. "/" .. name
        if typ == "file" then
          local norm = vim.fs.normalize(full)
          if path_ends_with(norm, tail) and not seen[norm] then
            seen[norm] = true
            results[#results + 1] = norm
            if #results >= limit then
              active = active - 1
              finish()
              return
            end
          end
        elseif typ == "directory" and not excluded[name] and item.depth < max_depth then
          queue[#queue + 1] = { dir = full, depth = item.depth + 1 }
        end
      end

      active = active - 1
      pump()
    end)
  end

  pump = function()
    if done then return end
    while active < concurrency and qhead <= #queue do
      local item = queue[qhead]
      qhead = qhead + 1
      active = active + 1
      scan_one(item)
    end
    if active == 0 and qhead > #queue then finish() end
  end

  if #queue == 0 then
    vim.schedule(finish)
  else
    pump()
  end
end

return M
