---@module 'gopath.alternate.frecency'
---@description Order alternate candidates by what you actually chose before.
---
--- The candidate list is ranked by filename similarity, which is the right
--- primary signal and a poor tiebreaker: `config.lua`, `configs.lua` and
--- `config.local.lua` sit within a few points of each other, and which one you
--- meant is not a property of the string. It is a property of your history —
--- and after the first time, this module knows it.
---
--- **A bonus, never an override.** The bonus saturates: `score / (score + K)`
--- scaled by `max_bonus`, so it approaches a ceiling instead of growing with
--- the visit count. That ceiling is the whole design. Similarity runs 0–100
--- and the default threshold admits everything from 75 up, so a bonus capped
--- at 10 can reorder candidates *within* a similarity band and can never push
--- a 95% match below a 76% one. Without the cap, a single visit would score
--- `log(2) × 100 ≈ 69` and bury the similarity signal entirely — which is not
--- a hypothetical, it is what the raw score does.
---
--- `K` is one fresh first visit's worth of score, so choosing a candidate once
--- buys roughly *half* the ceiling and everything after that is diminishing.
--- One choice should be visible; the tenth should not be ten times louder.
---
--- The store is `lib.nvim.frecency`, on its own namespace. It is the same
--- implementation `pickers.nvim` ranks files with, which is why it lives there
--- and not here — but not the same *store*: the two rank different kinds of
--- thing, and a path visited often in the picker says nothing about which
--- alternate you meant.

require("gopath.alternate.@types")

local M = {}

--- Score of a single fresh visit, and therefore the point at which the
--- saturation curve reaches half the ceiling.
---@internal
local HALF_AT = 100

--- Default ceiling, in similarity points. Ten on a 0–100 scale whose
--- threshold is 75: enough to reorder near-ties, never enough to invert a
--- clear winner.
---@internal
local DEFAULT_MAX_BONUS = 10

---Whether the feature is on, and how it is configured. Off means nothing is
---read, written or reordered.
---@internal
---@return boolean enabled
---@return number max_bonus
---@return string|nil dir
local function settings()
  local ok, config = pcall(require, "gopath.config")
  local alt = (ok and type(config.get) == "function" and (config.get().alternate or {})) or {}
  local frecency = alt.frecency
  if frecency == nil then return true, DEFAULT_MAX_BONUS, nil end
  if frecency == false or frecency.enable == false then return false, DEFAULT_MAX_BONUS, nil end
  local dir = (type(frecency.dir) == "string" and frecency.dir ~= "") and frecency.dir or nil
  return true, tonumber(frecency.max_bonus) or DEFAULT_MAX_BONUS, dir
end

---@internal
---@param dir string|nil
---@return Lib.Frecency.Store
local function store(dir)
  return require("lib.nvim.frecency").store({
    namespace = "gopath-alternates",
    dir = dir,
    -- Flushed immediately after a choice instead: an alternate dialog is
    -- rare enough that the write costs nothing, and the alternative is
    -- losing the one thing this module learns to a crash.
    autoflush = false,
  })
end

---Record that the user chose `path` out of an alternate list, and persist it
---right away.
---@param path string|nil
---@return nil
function M.record(path)
  if type(path) ~= "string" or path == "" then return end
  local enabled, _, dir = settings()
  if not enabled then return end
  -- A ranking aid must never break the thing it ranks. An unwritable store
  -- means an unsorted list next time, not a failed jump now, and it is not
  -- worth a message: the user asked to open a file, and they got one.
  pcall(function()
    local s = store(dir)
    s:record(path)
    s:flush()
  end)
end

---Reorder `matches` so that candidates you have chosen before rise within
---their similarity band. Returns the same table, sorted in place.
---@param matches AlternateMatch[]
---@return AlternateMatch[] matches
function M.rerank(matches)
  if type(matches) ~= "table" or #matches < 2 then return matches end

  local enabled, max_bonus, dir = settings()
  if not enabled or max_bonus <= 0 then return matches end

  local paths, order = {}, {}
  for i, match in ipairs(matches) do
    paths[#paths + 1] = match.path
    -- The incoming order is the similarity order the matcher produced. Kept
    -- as the tiebreak so the sort is deterministic: Lua's `table.sort` is not
    -- stable, and two candidates with equal similarity and no history would
    -- otherwise swap between runs for no reason a reader could explain.
    order[match.path] = i
  end

  local ok, bonus = pcall(function()
    return store(dir):lookup(paths)
  end)
  if not ok or not bonus or next(bonus) == nil then return matches end

  ---@param match AlternateMatch
  ---@return number
  local function ranked(match)
    local raw = bonus[match.path]
    if not raw or raw <= 0 then return match.similarity end
    return match.similarity + max_bonus * (raw / (raw + HALF_AT))
  end

  table.sort(matches, function(a, b)
    local ra, rb = ranked(a), ranked(b)
    if ra ~= rb then return ra > rb end
    return (order[a.path] or 0) < (order[b.path] or 0)
  end)

  return matches
end

return M
