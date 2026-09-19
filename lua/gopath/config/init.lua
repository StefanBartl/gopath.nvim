---@module 'gopath.config'
---@brief User-options merge and sane defaults.
---@description
--- Owns a single module-level state table that is populated once by `setup()`
--- and read-only afterwards via `get()`. Deep-merges user options on top of
--- the built-in defaults (see `gopath.config.DEFAULTS`) so that callers can
--- override only what they need.

local M = {}

local defaults = require("gopath.config.DEFAULTS")

---True when `t` is a plain array: keys are exactly `1..n` with no holes and
---no string keys. An empty table counts as a list.
---@private
---@param t table
---@return boolean
local function is_list(t)
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

---Top-level keys `setup()` recognizes and, for the fixed-schema tables among
---them, their own direct keys (one level, not recursive).
---
---  * `"list"` — a curated array (see `deep_merge_into`'s docstring); a
---    non-list value is a type error, not an override.
---  * `"open"` — a table whose own keys are not a closed set (`languages` is
---    keyed by filetype, including ones gopath has no built-in resolver for)
---    and are therefore never flagged as unknown.
---  * a nested table — validated one level deep the same way as the top
---    level, but only for unknown *keys*; leaf value types are polymorphic
---    enough (`string|string[]|false` keymaps, `boolean` command toggles)
---    that checking them here would duplicate what each consumer already
---    guards for itself. `mappings`/`commands` additionally accept a bare
---    `false` in place of the table (see `ALLOW_FALSE`) — the documented way
---    to disable the whole preset (docs/configuration.md).
---  * `true` — any value goes unchecked (scalars, and `languages`' sibling
---    `dev_mode`/`mode`/`lsp_timeout_ms`/`which_key`/`deps_popup`).
---@type table<string, true|"list"|"open"|table<string, true>>
local KNOWN = {
  dev_mode = true,
  mode = true,
  order = "list",
  lsp_timeout_ms = true,
  languages = "open",
  alternate = {
    enable = true,
    similarity_threshold = true,
    frecency = true,
  },
  external = {
    enable = true,
    extensions = true,
    pdf = true,
  },
  url = {
    enable = true,
    bare_hosts = true,
    schemes = true,
    tlds = true,
  },
  env_variable_resolution = {
    enable = true,
    shorten_dirs = true,
  },
  create_on_missing = {
    enable = true,
    confirm = true,
  },
  truncated = {
    enable = true,
    use_cache = true,
    cache_refresh_interval = true,
    rtp_index_ttl_ms = true,
    max_cache_age = true,
    live_search_fallback = true,
    similarity_threshold = true,
    cache_roots = true,
    max_depth = true,
    excluded_dirs = true,
    watch_patterns = true,
    auto_rebuild_on_save = true,
  },
  linepath = {
    enable = true,
    cascade = true,
  },
  tailsearch = {
    enable = true,
    max_components = true,
    ask_on_ambiguous = true,
    roots = true,
    limit = true,
  },
  mappings = {
    open_here = true,
    open_split = true,
    open_vsplit = true,
    open_tab = true,
    open_explorer = true,
    copy_location = true,
    debug = true,
    probe = true,
    check = true,
  },
  commands = {
    resolve = true,
    open = true,
    copy = true,
    debug = true,
    check = true,
    to_repos_dir = true,
  },
  which_key = true,
  deps_popup = true,
}

---Top-level keys whose known-table entry also accepts a bare `false` instead
---of a table (see `KNOWN`'s docstring).
---@type table<string, true>
local ALLOW_FALSE = { mappings = true, commands = true }

---What the last `setup()` had to reject or flag, for `:checkhealth`. Reset on
---every call so issues from an earlier setup() never linger.
---@type string[]
local issues = {}

---`key` with the nearest known one as a hint when there is a plausible one
---(edit distance <= 3).
---@internal
---@param key any
---@param known table<string, any>
---@param prefix string
---@return string
local function describe_unknown(key, known, prefix)
  local levenshtein = require("lib.lua.strings.distance").levenshtein
  local name = tostring(key)
  local best, best_distance = nil, nil
  for candidate in pairs(known) do
    local d = levenshtein(name, candidate)
    if d <= 3 and (best_distance == nil or d < best_distance) then
      best, best_distance = candidate, d
    end
  end
  if best then
    return ("unknown option '%s%s' (did you mean '%s%s'?)"):format(prefix, name, prefix, best)
  end
  return ("unknown option '%s%s'"):format(prefix, name)
end

---Validate `opts` against `KNOWN` before the merge (ERR-50), and drop values
---whose shape does not fit their option (ERR-22) so the default survives
---instead of a crash three modules downstream: `order = "lsp"` (a string,
---not a list) used to throw "table expected, got string" out of
---`resolve.lua`'s `ipairs(cfg.order)`, and `languages = false` used to throw
---"attempt to index a boolean value" the same way.
---
---A key gopath does not recognize is still merged in (an established
---extension point — see the "unknown keys are kept" spec) but is reported
---here, so a typo like `truncted` for `truncated` is at least visible instead
---of silently leaving the real option at its default forever.
---
---Does not mutate `opts` — a type-invalid entry is left out of the returned
---copy rather than stripped from the caller's own table.
---@internal
---@param opts table
---@return table  a shallow copy of opts, minus type-invalid entries
---@return string[] found_issues
local function validate(opts)
  local clean, found_issues = {}, {}
  for key, value in pairs(opts) do
    local known = KNOWN[key]
    local drop = false
    if known == nil then
      found_issues[#found_issues + 1] = describe_unknown(key, KNOWN, "")
    elseif known == "list" then
      if type(value) ~= "table" or not is_list(value) then
        found_issues[#found_issues + 1] = ("option '%s' must be a list, got %s -- using the default"):format(
          key,
          type(value)
        )
        drop = true
      end
    elseif known == "open" then
      if type(value) ~= "table" then
        found_issues[#found_issues + 1] = ("option '%s' must be a table, got %s -- using the default"):format(
          key,
          type(value)
        )
        drop = true
      end
    elseif type(known) == "table" then
      -- `mappings`/`commands` additionally accept a bare `false` (the
      -- documented "disable the whole preset" shape) -- nothing to validate
      -- below it in that case.
      local whole_preset_off = value == false and ALLOW_FALSE[key]
      if not whole_preset_off then
        if type(value) ~= "table" then
          local shape = ALLOW_FALSE[key] and "a table or false" or "a table"
          found_issues[#found_issues + 1] = ("option '%s' must be %s, got %s -- using the default"):format(
            key,
            shape,
            type(value)
          )
          drop = true
        else
          for sub_key in pairs(value) do
            if known[sub_key] == nil then
              found_issues[#found_issues + 1] = describe_unknown(sub_key, known, key .. ".")
            end
          end
        end
      end
    end
    if not drop then clean[key] = value end
  end
  table.sort(found_issues)
  return clean, found_issues
end

---Recursively merge `src` into `dst`, preferring `src` values.
---
---Closed, curated array fields (e.g. `order`, `truncated.excluded_dirs`) are
---replaced wholesale rather than merged index-wise: index-wise merging (the
---same trap `vim.tbl_deep_extend` has for lists) would otherwise leave
---trailing default entries behind a shorter user-supplied list. E.g. a user
---setting `order = { "treesitter" }` to opt out of "lsp" and "builtin" would,
---under index-wise merging, get back `{ "treesitter", "treesitter", "builtin" }`
---(index 1 overwritten, indices 2-3 left over from the 3-element default) —
---"builtin" silently keeps running despite being explicitly left out.
---@private
---@param dst table
---@param src table
local function deep_merge_into(dst, src)
  assert(type(dst) == "table", "deep_merge_into: dst must be a table")
  for k, v in pairs(src or {}) do
    if type(v) == "table" and type(dst[k]) == "table" then
      if is_list(v) and is_list(dst[k]) then
        dst[k] = vim.deepcopy(v)
      else
        deep_merge_into(dst[k], v)
      end
    else
      dst[k] = v
    end
  end
end

---Reset `dst` in place to match `src` (the defaults), mutating rather than
---replacing every table it descends into (ERR-53) — a consumer that stashed
---a reference to one of `dst`'s sub-tables (e.g. `gopath.init._setup_cache`'s
---`tcfg`, or a test's `config.get().truncated`) must still see the reset
---values through that same reference, not a detached copy.
---@private
---@param dst table
---@param src table
local function reset_into(dst, src)
  for k in pairs(dst) do
    if src[k] == nil then dst[k] = nil end
  end
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      reset_into(dst[k], v)
    else
      dst[k] = v
    end
  end
end

---@type GopathOptions
local state = vim.deepcopy(defaults)

---Merge `opts` on top of the built-in defaults.
---
---`state` is reset to a fresh copy of the defaults first, so every call
---starts from the same baseline instead of re-merging on top of whatever an
---earlier call left behind — `setup({ truncated = { enable = false } })`
---followed by `setup({})` leaves `truncated.enable` back at its default
---(`true`), not stuck at `false` (LUA-87). `setup(nil)`/a non-table argument
---stays a true no-op and skips the reset entirely, since there is nothing to
---apply on top of it.
---
---`opts` is validated first (ERR-50/ERR-22): a value whose shape does not fit
---its option is dropped so the built-in default is what actually takes
---effect, and every issue is both warned here and kept for `:checkhealth`
---(see `M.issues()`).
---@param opts GopathOptions|nil
function M.setup(opts)
  if not opts or type(opts) ~= "table" then return end
  reset_into(state, defaults)
  local clean, found_issues = validate(opts)
  issues = found_issues
  if #issues > 0 then
    require("gopath.util.log").warn("invalid config: " .. table.concat(issues, "; "))
  end
  deep_merge_into(state, clean)
end

---Return the current effective configuration (read-only reference).
---@return GopathOptions
function M.get()
  return state
end

---What the last `setup()` had to reject or flag: unknown keys (with a
---did-you-mean hint) and options whose value did not fit their expected
---shape, one human-readable line each. Empty when everything was recognized
---and well-typed.
---@return string[]
function M.issues()
  return vim.list_extend({}, issues)
end

return M
