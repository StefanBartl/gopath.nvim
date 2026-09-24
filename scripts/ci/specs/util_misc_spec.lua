-- scripts/ci/specs/util_misc_spec.lua
-- The small utility layer: gopath.util.cross (separators / drive detection),
-- gopath.util.location (line/col parsing and range normalisation),
-- gopath.util.log, gopath.util.safe, gopath.util.safe_notify and
-- gopath.util.selection.
--
-- cross/log/safe_notify each bind their lib.nvim dependency to an upvalue in a
-- top-level `do ... end` block, so both the "lib.nvim is there" and the
-- "lib.nvim is missing" branch are exercised by re-requiring the module with
-- `package.loaded` swapped first — patching a field afterwards would be too
-- late to reach the upvalue.

---@param H table
return function(H)
  -- ── cross ──────────────────────────────────────────────────────────────────

  local CROSS = require("gopath.util.cross")

  H.check("cross.to_forward: every backslash becomes a slash, on every platform", function()
    H.eq(CROSS.to_forward("C:\\repos\\a\\b.lua"), "C:/repos/a/b.lua")
    H.eq(CROSS.to_forward("already/forward"), "already/forward")
    H.eq(CROSS.to_forward("mixed\\up/here"), "mixed/up/here")
    H.eq(CROSS.to_forward(""), "", "empty string")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(CROSS.to_forward(42), 42, "a non-string is handed back untouched")
  end)

  H.check("cross.has_drive: only a letter + colon + separator counts", function()
    H.eq(CROSS.has_drive("C:/x"), true, "forward slash")
    H.eq(CROSS.has_drive("e:\\x"), true, "lowercase, backslash")
    H.eq(CROSS.has_drive("C:"), false, "a bare drive with no separator")
    H.eq(CROSS.has_drive("https://x.com"), false, "a scheme is not a drive")
    H.eq(CROSS.has_drive("/usr/lib"), false, "a POSIX root")
    H.eq(CROSS.has_drive("relative/x"), false, "a relative path")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(CROSS.has_drive(nil), false, "nil")
  end)

  H.check("cross.is_windows agrees with vim's own has()", function()
    local expected = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
    H.eq(CROSS.is_windows(), expected)
  end)

  H.check("cross.to_native: round-trips through to_forward on either platform", function()
    local native = CROSS.to_native("a/b/c.lua")
    H.eq(CROSS.to_forward(native), "a/b/c.lua", "to_native is separator-only, never lossy")
    if CROSS.is_windows() then
      H.eq(native, "a\\b\\c.lua", "backslashes on Windows")
    else
      H.eq(native, "a/b/c.lua", "forward slashes elsewhere")
    end
    H.eq(CROSS.to_native(""), "", "empty string short-circuits")
  end)

  H.check("cross: degrades to built-in separator handling without lib.nvim", function()
    H.with_modules({ ["lib.nvim.cross"] = false }, function()
      local bare = require("gopath.util.cross")
      H.eq(bare.to_forward("a\\b"), "a/b", "to_forward never needed lib.nvim")
      H.eq(bare.has_drive("D:\\x"), true, "built-in drive pattern")
      H.eq(bare.has_drive("nope"), false)
      local native = bare.to_native("a/b")
      H.eq(bare.is_windows() and native == "a\\b" or native == "a/b", true, "per-OS fallback")
    end, { unload = { "gopath.util.cross" } })
    -- Restore the real module for every later spec.
    H.fresh("gopath.util.cross")
  end)

  -- ── location ───────────────────────────────────────────────────────────────

  local LOC = require("gopath.util.location")

  H.check("parse_location: the five supported suffix forms", function()
    H.same(LOC.parse_location("lua/x.lua:42:7"), { path = "lua/x.lua", line = 42, col = 7 })
    H.same(LOC.parse_location("lua/x.lua:42"), { path = "lua/x.lua", line = 42, col = 1 })
    H.same(LOC.parse_location("path(10:5)"), { path = "path", line = 10, col = 5 })
    H.same(LOC.parse_location("path(10)"), { path = "path", line = 10, col = 1 })
    H.same(LOC.parse_location("file +7"), { path = "file", line = 7, col = 1 })
  end)

  H.check("parse_location: a Windows drive letter does not eat the filename", function()
    -- The classic ":"-split failure: three-way splitting on ":" would turn
    -- "C:/…/init.lua:14:3" into path "C". It must not.
    local a = LOC.parse_location("C:/Users/x/init.lua:14:3")
    H.eq(a.path, "C:/Users/x/init.lua", "forward-slash drive path")
    H.eq(a.line, 14)
    H.eq(a.col, 3)

    local b = LOC.parse_location("C:\\Users\\x\\init.lua:14:3")
    H.eq(b.path, "C:\\Users\\x\\init.lua", "backslash drive path (separators preserved verbatim)")
    H.eq(b.line, 14)

    local c = LOC.parse_location("E:/repos/a.md")
    H.eq(c.path, "E:/repos/a.md", "no suffix at all")
    H.is_nil(c.line, "and therefore no line")
  end)

  H.check("parse_location: always returns a table, never nil", function()
    H.same(LOC.parse_location(""), { path = "" }, "empty input")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.same(LOC.parse_location(nil), { path = "" }, "nil input")
    H.same(LOC.parse_location("  spaced.txt  "), { path = "spaced.txt" }, "whitespace trimmed")
  end)

  H.check("parse_location: a matched line with no column defaults col to 1", function()
    -- This is gopath's own contract on top of lib.nvim's parser, which leaves
    -- col nil in that case.
    H.eq(LOC.parse_location("x.lua:9").col, 1)
    H.is_nil(LOC.parse_location("x.lua").col, "no line means no column either")
  end)

  H.check("create_range / normalize_range: clamp to 1, reject line 0", function()
    H.same(LOC.create_range(5, 3), { line = 5, col = 3 })
    H.same(LOC.create_range(5, nil), { line = 5, col = 1 }, "missing col")
    H.same(LOC.create_range(-2, -9), { line = 1, col = 1 }, "negatives clamp")
    H.is_nil(LOC.create_range(0, 4), "line 0 means no range")
    H.is_nil(LOC.create_range(nil, 4), "no line means no range")

    H.same(LOC.normalize_range({ line = 4, col = 0 }), { line = 4, col = 1 })
    H.is_nil(LOC.normalize_range(nil), "nil in, nil out")
    H.is_nil(LOC.normalize_range({ line = 0 }), "line 0 is not a position")
    H.is_nil(LOC.normalize_range({ col = 3 }), "a column alone is not a position")
  end)

  H.check("merge_ranges: parsed wins, then existing, then nothing", function()
    H.same(
      LOC.merge_ranges({ line = 2, col = 9 }, { line = 5, col = 5 }),
      { line = 2, col = 9 },
      "parsed takes precedence"
    )
    H.same(LOC.merge_ranges({ line = 2 }, nil), { line = 2, col = 1 }, "parsed without col")
    H.same(LOC.merge_ranges({}, { line = 5 }), { line = 5, col = 1 }, "falls back to existing")
    H.is_nil(LOC.merge_ranges({}, {}), "neither side carries a line")
    H.is_nil(LOC.merge_ranges(nil, nil), "both nil")
  end)

  -- ── log ────────────────────────────────────────────────────────────────────

  H.check("log: without lib.nvim's notifier every level goes to vim.notify, prefixed", function()
    H.with_modules({ ["lib.nvim.notify"] = false }, function()
      local LOG = require("gopath.util.log")
      local notes = H.capture_notify(function()
        LOG.info("hello")
        LOG.warn("careful")
        LOG.error("boom")
      end)
      H.eq(#notes, 3, "three notifications")
      H.eq(notes[1].msg, "[gopath] hello")
      H.eq(notes[1].level, vim.log.levels.INFO)
      H.eq(notes[2].level, vim.log.levels.WARN)
      H.eq(notes[3].level, vim.log.levels.ERROR)
    end, { unload = { "gopath.util.log" } })
    H.fresh("gopath.util.log")
  end)

  H.check("log.debug is silent unless dev_mode is on", function()
    local config = require("gopath.config")
    H.with_modules({ ["lib.nvim.notify"] = false }, function()
      local LOG = require("gopath.util.log")

      config.setup({ dev_mode = false })
      H.eq(#H.capture_notify(function()
        LOG.debug("quiet")
      end), 0, "off by default")

      config.setup({ dev_mode = true })
      local on = H.capture_notify(function()
        LOG.debug("loud")
      end)
      config.setup({ dev_mode = false })

      H.eq(#on, 1, "emitted with dev_mode")
      H.eq(on[1].msg, "[gopath] loud")
      H.eq(on[1].level, vim.log.levels.DEBUG)
    end, { unload = { "gopath.util.log" } })
    H.fresh("gopath.util.log")
  end)

  H.check("log: delegates to lib.nvim's notifier when it is installed", function()
    local seen = {}
    local fake = {
      create = function(prefix)
        return {
          debug = function(m)
            seen[#seen + 1] = { "debug", prefix, m }
          end,
          info = function(m)
            seen[#seen + 1] = { "info", prefix, m }
          end,
          warn = function(m)
            seen[#seen + 1] = { "warn", prefix, m }
          end,
          error = function(m)
            seen[#seen + 1] = { "error", prefix, m }
          end,
        }
      end,
    }
    H.with_modules({ ["lib.nvim.notify"] = fake }, function()
      local LOG = require("gopath.util.log")
      local direct = H.capture_notify(function()
        LOG.info("routed")
        LOG.warn("routed too")
      end)
      H.eq(#direct, 0, "nothing goes to vim.notify directly")
      H.eq(#seen, 2, "both reached the notifier")
      H.eq(seen[1][1], "info")
      H.eq(seen[1][2], "[gopath]", "created with gopath's prefix")
      H.eq(seen[1][3], "routed", "message passed through unprefixed")
    end, { unload = { "gopath.util.log" } })
    H.fresh("gopath.util.log")
  end)

  -- ── safe / safe_notify ─────────────────────────────────────────────────────

  H.check("safe.call: forwards results on success and the error on failure", function()
    local safe = require("gopath.util.safe")
    local ok, value = safe.call(function(a, b)
      return a + b
    end, 2, 3)
    H.eq(ok, true, "succeeded")
    H.eq(value, 5, "result forwarded")

    local bad_ok, err = safe.call(function()
      error("deliberate")
    end)
    H.eq(bad_ok, false, "failure reported, not raised")
    H.truthy(err, "and carries something to report")
  end)

  H.check("safe_notify: gated on dev_mode, and forwards the delay", function()
    local config = require("gopath.config")
    local calls = {}
    H.with_modules({
      ["lib.nvim.notify.safe"] = {
        defer = function(msg, level, opts, delay)
          calls[#calls + 1] = { msg = msg, level = level, opts = opts, delay = delay }
        end,
      },
    }, function()
      local SN = require("gopath.util.safe_notify")

      config.setup({ dev_mode = false })
      SN.safe_notify_defer("suppressed", vim.log.levels.INFO, nil, 10)
      H.eq(#calls, 0, "dev_mode off means nothing is scheduled")

      config.setup({ dev_mode = true })
      SN.safe_notify_defer("shown", vim.log.levels.WARN, { title = "t" }, 50)
      config.setup({ dev_mode = false })

      H.eq(#calls, 1, "scheduled once")
      H.eq(calls[1].msg, "shown")
      H.eq(calls[1].level, vim.log.levels.WARN)
      H.eq(calls[1].delay, 50, "delay forwarded")

      config.setup({ dev_mode = true })
      SN.safe_notify_defer("no delay given", vim.log.levels.INFO, nil, nil)
      config.setup({ dev_mode = false })
      H.eq(calls[2].delay, 0, "a missing delay becomes 0, never nil")
    end, { unload = { "gopath.util.safe_notify" } })
    H.fresh("gopath.util.safe_notify")
  end)

  -- ── selection ──────────────────────────────────────────────────────────────

  local SEL = require("gopath.util.selection")

  H.check("selection.span: a single-line charwise selection, 1-indexed inclusive", function()
    H.buf({ "hello world here" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 6, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 10, {})
    local span = SEL.span()
    H.truthy(span)
    H.eq(span.row, 1)
    H.eq(span.line:sub(span.start_col, span.end_col), "world")
  end)

  H.check(
    "selection.span: '<' after '>' is still ordered start-before-end in the result",
    function()
      -- Real Visual-mode marks always have '<' at the earlier position, but
      -- nothing stops a caller (or a test) from setting them the other way
      -- around -- this mirrors commands.lua's own get_visual_selection() in
      -- swapping rather than returning a backwards span.
      H.buf({ "hello world here" })
      vim.api.nvim_buf_set_mark(0, "<", 1, 10, {}) -- 'd' of "world", the later end
      vim.api.nvim_buf_set_mark(0, ">", 1, 6, {}) -- 'w' of "world", the earlier end
      local span = SEL.span()
      H.truthy(span)
      H.truthy(
        span.start_col <= span.end_col,
        "start_col/end_col are ordered regardless of mark order"
      )
      H.eq(span.line:sub(span.start_col, span.end_col), "world")
    end
  )

  H.check("selection.span: no marks set at all is nil", function()
    H.buf({ "hello" })
    H.is_nil(SEL.span())
  end)

  H.check("selection.span: a multi-line selection is nil (single-line only)", function()
    H.buf({ "first", "second" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 2, 0, {})
    H.is_nil(SEL.span())
  end)

  H.check("selection.span: a whitespace-only selection is nil", function()
    H.buf({ "a    b" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 1, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 4, {})
    H.is_nil(SEL.span())
  end)

  H.check("selection.span: a linewise selection's MAXCOL end is clamped in range", function()
    H.buf({ "short" })
    vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
    vim.api.nvim_buf_set_mark(0, ">", 1, 2147483647, {})
    local span = SEL.span()
    H.truthy(span)
    H.eq(span.line:sub(span.start_col, span.end_col), "short", "clamped to the actual line length")
  end)
end
