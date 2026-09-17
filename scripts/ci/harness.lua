-- scripts/ci/harness.lua
-- Shared assertion/fixture helpers for the spec files under scripts/ci/specs/.
--
-- Deliberately the same shape as the `check()` + `assert_eq()` pair that
-- scripts/ci/functional_tests.lua has always used -- this is that harness,
-- lifted out so more than one file can use it, not a new framework. Specs are
-- plain Lua modules returning `function(H) ... end`; scripts/ci/unit_tests.lua
-- discovers and runs them.
--
-- What it adds over the inline version:
--   * fixture helpers that write real files under vim.fn.tempname()
--   * buffer/cursor helpers, since almost every resolver reads both
--   * `with_modules`, which replaces entries in `package.loaded` *before* the
--     module under test is required. Modules here bind their dependencies to
--     upvalues at load time (`local LOG = require("gopath.util.log")`), so
--     patching a field afterwards is too late.
--   * notification capture, so a spec can assert the message a user would
--     actually see rather than merely that something failed.

local H = {}

H.failures = {} ---@type string[]
H.checks = 0
H.assertions = 0

-- ── Reporting ────────────────────────────────────────────────────────────────

---Run `fn` as one named check, reporting pass/fail instead of propagating.
---@param name string
---@param fn fun()
---@return nil
function H.check(name, fn)
  H.checks = H.checks + 1
  local ok, err = pcall(fn)
  if ok then
    print(("[ OK ] %s"):format(name))
  else
    print(("[FAIL] %s: %s"):format(name, err))
    H.failures[#H.failures + 1] = name
  end
end

-- ── Assertions ───────────────────────────────────────────────────────────────

---@param actual any
---@param expected any
---@param msg string|nil
---@return nil
function H.eq(actual, expected, msg)
  H.assertions = H.assertions + 1
  if actual ~= expected then
    error(
      ("%s: expected %s, got %s"):format(msg or "eq", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

---Deep equality for plain tables (lists and maps), by value.
---@param actual any
---@param expected any
---@param msg string|nil
---@return nil
function H.same(actual, expected, msg)
  H.assertions = H.assertions + 1
  if not vim.deep_equal(actual, expected) then
    error(
      ("%s: expected %s, got %s"):format(msg or "same", vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

---@param v any
---@param msg string|nil
---@return nil
function H.truthy(v, msg)
  H.assertions = H.assertions + 1
  if not v then error(msg or "expected a truthy value", 2) end
end

---@param v any
---@param msg string|nil
---@return nil
function H.falsy(v, msg)
  H.assertions = H.assertions + 1
  if v then error((msg or "expected a falsy value") .. ", got " .. vim.inspect(v), 2) end
end

---@param v any
---@param msg string|nil
---@return nil
function H.is_nil(v, msg)
  H.assertions = H.assertions + 1
  if v ~= nil then error((msg or "expected nil") .. ", got " .. vim.inspect(v), 2) end
end

---Assert that `s` contains `pattern` (a Lua pattern).
---@param s any
---@param pattern string
---@param msg string|nil
---@return nil
function H.match(s, pattern, msg)
  H.assertions = H.assertions + 1
  if type(s) ~= "string" or not s:find(pattern) then
    error(("%s: %s does not match %q"):format(msg or "match", vim.inspect(s), pattern), 2)
  end
end

---Assert that `s` does NOT contain `pattern`.
---@param s any
---@param pattern string
---@param msg string|nil
---@return nil
function H.no_match(s, pattern, msg)
  H.assertions = H.assertions + 1
  if type(s) == "string" and s:find(pattern) then
    error(("%s: %s unexpectedly matches %q"):format(msg or "no_match", vim.inspect(s), pattern), 2)
  end
end

---Assert that `list` contains `value`.
---@param list any[]
---@param value any
---@param msg string|nil
---@return nil
function H.contains(list, value, msg)
  H.assertions = H.assertions + 1
  for _, v in ipairs(list or {}) do
    if v == value then return end
  end
  error(
    ("%s: %s not found in %s"):format(msg or "contains", vim.inspect(value), vim.inspect(list)),
    2
  )
end

---Assert that calling `fn` raises, and that the message matches `pattern`.
---@param fn fun()
---@param pattern string|nil
---@param msg string|nil
---@return string the error message
function H.raises(fn, pattern, msg)
  H.assertions = H.assertions + 1
  local ok, err = pcall(fn)
  if ok then error((msg or "raises") .. ": expected an error, none was raised", 2) end
  local text = tostring(err)
  if pattern and not text:find(pattern) then
    error(("%s: error %q does not match %q"):format(msg or "raises", text, pattern), 2)
  end
  return text
end

-- ── Fixtures ─────────────────────────────────────────────────────────────────

---A fresh, empty temporary directory. Real disk, not a mock: the path helpers
---under test call `fs_stat`/`fs_scandir` and would be untested against a fake.
---@return string dir  absolute, forward slashes
function H.tmpdir()
  local dir = (vim.fn.tempname()):gsub("\\", "/") .. "_gopath_spec"
  vim.fn.mkdir(dir, "p")
  return dir
end

---Write `lines` to `path`, creating parent directories as needed.
---@param path string
---@param lines string[]|string|nil
---@return string path
function H.write(path, lines)
  local parent = vim.fn.fnamemodify(path, ":h")
  if parent ~= "" then vim.fn.mkdir(parent, "p") end
  if type(lines) == "string" then lines = vim.split(lines, "\n", { plain = true }) end
  vim.fn.writefile(lines or { "" }, path)
  return path
end

---Create a directory (and parents).
---@param path string
---@return string path
function H.mkdir(path)
  vim.fn.mkdir(path, "p")
  return path
end

-- ── Buffers and the cursor ───────────────────────────────────────────────────

---Open a scratch buffer holding `lines`, make it current, and optionally set
---its filetype and name.
---@param lines string[]
---@param opts { filetype?: string, name?: string, listed?: boolean }|nil
---@return integer bufnr
function H.buf(lines, opts)
  opts = opts or {}
  local bufnr = vim.api.nvim_create_buf(opts.listed == true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(bufnr)
  if opts.name then vim.api.nvim_buf_set_name(bufnr, opts.name) end
  if opts.filetype then vim.bo[bufnr].filetype = opts.filetype end
  return bufnr
end

---Place the cursor on the first occurrence of `anchor` in line `row` (1-based).
---@param row integer
---@param anchor string  plain substring of that line
---@return nil
function H.cursor_on(row, anchor)
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local col = line:find(anchor, 1, true)
  if not col then error(("anchor %q not found in line %d (%q)"):format(anchor, row, line), 2) end
  vim.api.nvim_win_set_cursor(0, { row, col - 1 })
end

---Shorthand: one-line buffer with the cursor on `anchor`.
---@param line string
---@param anchor string
---@param opts { filetype?: string, name?: string }|nil
---@return integer bufnr
function H.line_at(line, anchor, opts)
  local bufnr = H.buf({ line }, opts)
  H.cursor_on(1, anchor)
  return bufnr
end

-- ── Module substitution ──────────────────────────────────────────────────────

---Drop `names` from `package.loaded` so the next `require` re-executes them.
---@param names string[]
---@return nil
function H.unload(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

---Run `fn` with `package.loaded` entries replaced by the given values, then
---restore whatever was there before (including "was not loaded at all").
---
---`opts.unload` names modules to evict first, so that a module under test
---re-runs its top-level `require`s and picks up the replacements. Without
---that, a module already loaded in this session keeps the real dependency in
---an upvalue and the substitution has no effect at all.
---@param replacements table<string, any>  module name -> replacement (false = make `require` fail)
---@param fn fun()
---@param opts { unload?: string[] }|nil
---@return nil
function H.with_modules(replacements, fn, opts)
  opts = opts or {}
  local saved, had = {}, {}
  local names = {}
  for name in pairs(replacements) do
    names[#names + 1] = name
  end
  for _, name in ipairs(opts.unload or {}) do
    names[#names + 1] = name
  end
  for _, name in ipairs(names) do
    had[name] = package.loaded[name] ~= nil
    saved[name] = package.loaded[name]
    package.loaded[name] = nil
  end

  local preloaded = {}
  for name, value in pairs(replacements) do
    if value == false then
      -- Make `require(name)` fail the way a missing plugin does.
      preloaded[name] = package.preload[name]
      package.preload[name] = function()
        error("module '" .. name .. "' not found (harness)", 0)
      end
    else
      package.loaded[name] = value
    end
  end

  local ok, err = pcall(fn)

  for name in pairs(replacements) do
    if preloaded[name] ~= nil or package.preload[name] then
      package.preload[name] = preloaded[name]
    end
  end
  for _, name in ipairs(names) do
    package.loaded[name] = had[name] and saved[name] or nil
  end

  if not ok then error(err, 0) end
end

---Require `name` from scratch, discarding any cached copy first.
---@param name string
---@return any
function H.fresh(name)
  package.loaded[name] = nil
  return require(name)
end

-- ── Swapping single values ───────────────────────────────────────────────────

---Temporarily replace `tbl[key]` with `value` while `fn` runs.
---@param tbl table
---@param key any
---@param value any
---@param fn fun()
---@return nil
function H.with_field(tbl, key, value, fn)
  local saved = tbl[key]
  tbl[key] = value
  local ok, err = pcall(fn)
  tbl[key] = saved
  if not ok then error(err, 0) end
end

---Run `fn` with `vim.notify` captured; returns every message it emitted.
---@param fn fun()
---@return { msg: string, level: integer|nil }[]
function H.capture_notify(fn)
  local seen = {}
  local real = vim.notify
  vim.notify = function(msg, level, _)
    seen[#seen + 1] = { msg = tostring(msg), level = level }
  end
  local ok, err = pcall(fn)
  vim.notify = real
  if not ok then error(err, 0) end
  return seen
end

---The concatenated text of every captured notification, for substring checks.
---@param notes { msg: string }[]
---@return string
function H.notify_text(notes)
  local parts = {}
  for _, n in ipairs(notes) do
    parts[#parts + 1] = n.msg
  end
  return table.concat(parts, "\n")
end

---Run `fn` with `vim.ui.select` answering with `choice` (nil = cancel), and
---report what it was offered.
---@param choice any  a value, or a function(items, opts) -> value
---@param fn fun()
---@return { items: any[], opts: table }[] calls
function H.with_ui_select(choice, fn)
  local calls = {}
  local real = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    calls[#calls + 1] = { items = items, opts = opts }
    local answer = choice
    if type(choice) == "function" then answer = choice(items, opts) end
    on_choice(answer)
  end
  local ok, err = pcall(fn)
  vim.ui.select = real
  if not ok then error(err, 0) end
  return calls
end

---Run `fn` with the gopath config restored afterwards, whatever it did to it.
---
---`config.get()` hands back the live state table (documented as a "read-only
---reference"), and `config.setup()` merges cumulatively rather than resetting —
---so a spec that calls `setup()` would otherwise leak its options into every
---later spec in the run.
---@param fn fun(config: table)
---@return nil
function H.config_sandbox(fn)
  local config = require("gopath.config")
  local state = config.get()
  local snapshot = vim.deepcopy(state)
  local ok, err = pcall(fn, config)
  for k in pairs(state) do
    state[k] = nil
  end
  for k, v in pairs(snapshot) do
    state[k] = v
  end
  if not ok then error(err, 0) end
end

---Drive the event loop until `predicate` returns true or `timeout_ms` elapses.
---Used for the libuv-based async walks, which finish on later loop ticks.
---@param predicate fun(): boolean
---@param timeout_ms integer|nil
---@return boolean satisfied
function H.wait(predicate, timeout_ms)
  return vim.wait(timeout_ms or 5000, predicate, 10)
end

return H
