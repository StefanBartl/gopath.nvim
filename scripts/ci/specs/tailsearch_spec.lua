-- scripts/ci/specs/tailsearch_spec.lua
-- gopath.resolvers.common.tailsearch: turn a partial/truncated path token into
-- a real file by matching path tails.
--
-- `git_root` walks up for a `.git` marker via `lib.nvim.fs.find_root` and the
-- live walk lives in `gopath.truncated.finder`; both are cut at a seam here
-- and the arguments they would have used are asserted instead. Everything
-- else runs against real directories under vim.fn.tempname().

---@param H table
return function(H)
  local TS = require("gopath.resolvers.common.tailsearch")

  -- ── sanitize ───────────────────────────────────────────────────────────────

  H.check("sanitize: splits off :line and :line:col", function()
    local t, l, c = TS.sanitize("lua/gopath/init.lua:42:7")
    H.eq(t, "lua/gopath/init.lua")
    H.eq(l, 42)
    H.eq(c, 7)

    t, l, c = TS.sanitize("lua/gopath/init.lua:42")
    H.eq(t, "lua/gopath/init.lua")
    H.eq(l, 42)
    H.is_nil(c, "no column given")

    t, l, c = TS.sanitize("lua/gopath/init.lua")
    H.eq(t, "lua/gopath/init.lua")
    H.is_nil(l)
    H.is_nil(c)
  end)

  H.check("sanitize: strips ellipsis, './', quotes and trailing punctuation", function()
    H.eq((TS.sanitize(".../nvim/lua/x.lua")), "nvim/lua/x.lua", "truncated error output")
    H.eq((TS.sanitize("./rel/x.lua")), "rel/x.lua", "cwd-relative prefix")
    H.eq((TS.sanitize("'lua/x.lua'")), "lua/x.lua", "single quotes")
    H.eq((TS.sanitize("see lua/x.lua.")), "see/lua/x.lua", "trailing sentence period")
    H.eq((TS.sanitize([[a\b\c.lua]])), "a/b/c.lua", "backslashes become slashes")
  end)

  H.check("sanitize: non-strings and empties", function()
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq((TS.sanitize(nil)), "", "nil")
    H.eq((TS.sanitize("")), "", "empty")
  end)

  H.check("BUG: sanitize only strips a Windows drive spelled '<UPPER>:/'", function()
    -- The drive strip is the FIRST gsub in the chain, so it runs before
    -- backslashes are normalised and it is anchored to an uppercase letter:
    --
    --   base = raw:gsub("^%u:/", ""):gsub("\\", "/"): …
    --
    -- Consequences, all Windows-only:
    H.eq((TS.sanitize("C:/repos/gopath.nvim/x.lua")), "repos/gopath.nvim/x.lua", "this one works")
    H.eq(
      (TS.sanitize([[C:\repos\gopath.nvim\x.lua]])),
      "C/repos/gopath.nvim/x.lua",
      "BUG: a backslash drive survives as a bogus leading segment 'C'"
    )
    H.eq(
      (TS.sanitize("c:/repos/x.lua")),
      "c/repos/x.lua",
      "BUG: a lowercase drive survives as a bogus leading segment 'c'"
    )
    H.eq(
      (TS.sanitize("E:/repos/x.lua:12:3")),
      "E:/repos/x.lua",
      "BUG: the :line:col branch returns before the drive strip runs at all"
    )
    -- Why it degrades rather than breaks: `suffix_candidates` tries shorter
    -- tails afterwards, so the junk leading segment only costs one wasted pass
    -- — unless max_components is 1, where it is the only candidate there is.
    H.same(
      TS.suffix_candidates((TS.sanitize([[C:\repos\x.lua]])), 1),
      { "x.lua" },
      "a one-component search still lands on the basename"
    )
    H.same(
      TS.suffix_candidates((TS.sanitize([[C:\repos\x.lua]])), 3),
      { "C/repos/x.lua", "repos/x.lua", "x.lua" },
      "BUG: the longest, most trusted candidate is the unmatchable one"
    )
  end)

  -- ── suffix_candidates ──────────────────────────────────────────────────────

  H.check("suffix_candidates: longest first, clamped to the segment count", function()
    H.same(TS.suffix_candidates("a/b/c.lua", 6), { "a/b/c.lua", "b/c.lua", "c.lua" })
    H.same(TS.suffix_candidates("a/b/c.lua", 2), { "b/c.lua", "c.lua" }, "max_components caps it")
    H.same(TS.suffix_candidates("c.lua", 6), { "c.lua" }, "a single segment")
    H.same(TS.suffix_candidates("", 6), {}, "nothing to split")
    H.same(TS.suffix_candidates("///", 6), {}, "separators only")
    H.same(TS.suffix_candidates("a/b", 0), { "b" }, "a zero cap still yields one component")
  end)

  -- ── pick_best ──────────────────────────────────────────────────────────────

  H.check("pick_best: the shortest path is the most specific", function()
    H.eq(TS.pick_best({ "/a/b/c/x.lua", "/a/x.lua", "/a/b/x.lua" }), "/a/x.lua")
    H.eq(TS.pick_best({ "/only.lua" }), "/only.lua")
    H.is_nil(TS.pick_best({}), "nothing to pick")
  end)

  -- ── find_by_tail (real filesystem walk, no subprocess) ─────────────────────

  H.check("find_by_tail: matches only on a segment boundary", function()
    local root = H.tmpdir()
    H.write(root .. "/pkg/mod/init.lua", { "" })
    H.write(root .. "/other/notinit.lua", { "" })
    H.write(root .. "/deep/pkg/mod/init.lua", { "" })

    local hits = TS.find_by_tail("mod/init.lua", { root }, 100)
    H.eq(#hits, 2, "both real matches found")
    for _, p in ipairs(hits) do
      H.match(p, "mod/init%.lua$")
    end

    local none = TS.find_by_tail("notinit.lua", { root }, 100)
    H.eq(#none, 1, "exact basename match")

    -- "init.lua" must not match "notinit.lua": the character before the tail
    -- has to be a separator.
    local boundary = TS.find_by_tail("init.lua", { root }, 100)
    for _, p in ipairs(boundary) do
      H.no_match(p, "notinit%.lua$", "a suffix that is not a whole segment does not count")
    end
  end)

  H.check("find_by_tail: honours the limit and survives an unreadable root", function()
    local root = H.tmpdir()
    for i = 1, 5 do
      H.write(("%s/d%d/same.lua"):format(root, i), { "" })
    end
    H.eq(#TS.find_by_tail("same.lua", { root }, 2), 2, "stops at the limit")
    H.same(TS.find_by_tail("same.lua", { root .. "/does-not-exist" }, 10), {}, "missing root")
  end)

  -- ── guess_roots ────────────────────────────────────────────────────────────

  H.check("guess_roots: buffer dir, cwd and stdpaths, deduplicated, no duplicates", function()
    local dir = H.tmpdir()
    local file = H.write(dir .. "/note.md", { "" })
    H.buf({ "x" }, { name = file })

    local roots
    H.with_modules({
      ["lib.nvim.fs.find_root"] = function()
        error("no marker found (harness stub)")
      end,
    }, function()
      -- pcall'd inside git_root, so a throwing finder factory simply means
      -- "no git root", which is the branch under test here.
      roots = TS.guess_roots()
    end)

    H.truthy(#roots >= 2, "at least the buffer dir and cwd")
    local seen = {}
    for _, r in ipairs(roots) do
      local key = (vim.fs.normalize(r))
      H.falsy(seen[key], "no duplicate root: " .. r)
      seen[key] = true
    end
    H.match(vim.fs.normalize(roots[1]), vim.pesc(vim.fs.normalize(dir)) .. "$", "buffer dir first")
  end)

  H.check(
    "guess_roots: the git-root probe uses lib.nvim.fs.find_root with a `.git` marker (LUA-02)",
    function()
      local dir = H.tmpdir()
      H.buf({ "x" }, { name = H.write(dir .. "/a.md", { "" }) })

      local calls = {}
      H.with_modules({
        ["lib.nvim.fs.find_root"] = function(opts)
          local call = { opts = opts }
          calls[#calls + 1] = call
          return {
            find = function(d)
              call.dir = d
              return nil
            end,
          }
        end,
      }, function()
        TS.guess_roots()
      end)

      H.truthy(#calls >= 1, "find_root was consulted")
      H.same(calls[1].opts.markers, { ".git" }, "no unbounded subprocess -- a marker walk instead")
      H.eq(calls[1].dir, vim.fs.dirname(dir .. "/a.md"))
    end
  )

  H.check("guess_roots: a git root that exists is added, one that does not is ignored", function()
    local dir = H.tmpdir()
    local repo = H.tmpdir()
    H.buf({ "x" }, { name = H.write(dir .. "/a.md", { "" }) })

    local roots
    H.with_modules({
      ["lib.nvim.fs.find_root"] = function()
        return {
          find = function()
            return repo
          end,
        }
      end,
    }, function()
      roots = TS.guess_roots()
    end)
    H.contains(
      vim.tbl_map(function(r)
        return vim.fs.normalize(r)
      end, roots),
      vim.fs.normalize(repo),
      "a real directory is taken as a root"
    )

    H.with_modules({
      ["lib.nvim.fs.find_root"] = function()
        return {
          find = function()
            return "/definitely/not/a/directory"
          end,
        }
      end,
    }, function()
      roots = TS.guess_roots()
    end)
    H.falsy(
      vim.tbl_contains(roots, "/definitely/not/a/directory"),
      "find_root's answer is still checked against the filesystem"
    )
  end)

  H.check("guess_roots: extra roots from config are appended", function()
    local extra = H.tmpdir()
    local roots
    H.with_field(vim, "system", function()
      error("no git here")
    end, function()
      roots = TS.guess_roots({ extra, "/not/a/real/dir" })
    end)
    H.contains(roots, extra, "an existing extra root is used")
    H.falsy(vim.tbl_contains(roots, "/not/a/real/dir"), "a missing one is dropped")
  end)

  -- ── cache_lookup ───────────────────────────────────────────────────────────

  ---A stand-in for gopath.truncated.cache that answers from a fixed table.
  ---@param answers table<string, string[]>
  ---@return table module, string[] queried
  local function fake_cache(answers)
    local queried = {}
    return {
      search = function(tail)
        queried[#queried + 1] = tail
        return answers[tail] or {}
      end,
    },
      queried
  end

  H.check("cache_lookup: tries the longest suffix first and stops on the first hit", function()
    local cache, queried = fake_cache({ ["b/c.lua"] = { "/x/b/c.lua" } })
    H.with_modules({ ["gopath.truncated.cache"] = cache }, function()
      local hits = TS.cache_lookup("a/b/c.lua", 6)
      H.same(hits, { "/x/b/c.lua" })
      H.same(queried, { "a/b/c.lua", "b/c.lua" }, "it never fell through to the bare basename")
    end)
  end)

  H.check("cache_lookup: deduplicates and normalises what the cache returns", function()
    local cache = fake_cache({
      ["c.lua"] = { [[C:\x\c.lua]], "C:/x/c.lua", "/y/c.lua" },
    })
    H.with_modules({ ["gopath.truncated.cache"] = cache }, function()
      local hits = TS.cache_lookup("c.lua", 6)
      H.eq(#hits, 2, "two spellings of the same path collapse into one")
      H.contains(hits, "C:/x/c.lua")
      H.contains(hits, "/y/c.lua")
    end)
  end)

  H.check("cache_lookup: empty input, a missing cache, and a throwing cache", function()
    H.same(TS.cache_lookup("", 6), {}, "empty tail")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.same(TS.cache_lookup(nil, 6), {}, "nil tail")
    H.with_modules({ ["gopath.truncated.cache"] = false }, function()
      H.same(TS.cache_lookup("a.lua", 6), {}, "no cache module at all")
    end)
    H.with_modules({
      ["gopath.truncated.cache"] = {
        search = function()
          error("cache is corrupt")
        end,
      },
    }, function()
      H.same(TS.cache_lookup("a.lua", 6), {}, "a throwing cache is a miss, not a crash")
    end)
  end)

  -- ── resolve_cached ─────────────────────────────────────────────────────────

  H.check("resolve_cached: never touches the filesystem, and scores ambiguity lower", function()
    local one = fake_cache({ ["c.lua"] = { "/x/c.lua" } })
    H.with_modules({ ["gopath.truncated.cache"] = one }, function()
      local r = TS.resolve_cached("c.lua", { line = 3, col = 9 })
      H.truthy(r, "expected a result")
      H.eq(r.path, "/x/c.lua")
      H.eq(r.kind, "file")
      H.eq(r.exists, true)
      H.eq(r.source, "tailsearch")
      H.eq(r.confidence, 0.85, "an unambiguous cache hit")
      H.same(r.range, { line = 3, col = 9 })
    end)

    local many = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/deeper/c.lua" } })
    H.with_modules({ ["gopath.truncated.cache"] = many }, function()
      local r = TS.resolve_cached("c.lua", {})
      H.eq(r.confidence, 0.72, "ambiguous")
      H.eq(r.path, "/x/c.lua", "shortest wins")
      H.is_nil(r.range, "no line given, no range invented")
    end)
  end)

  H.check("resolve_cached: a miss is nil, so the caller can go async", function()
    H.with_modules({ ["gopath.truncated.cache"] = fake_cache({}) }, function()
      H.is_nil(TS.resolve_cached("nothing.lua", {}))
      H.is_nil(TS.resolve_cached("", {}), "empty tail")
    end)
  end)

  H.check("resolve_cached: line 0 is not a position", function()
    H.with_modules(
      { ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua" } }) },
      function()
        H.is_nil(TS.resolve_cached("c.lua", { line = 0, col = 4 }).range)
      end
    )
  end)

  -- ── resolve_sync ───────────────────────────────────────────────────────────

  H.check("resolve_sync: the cache short-circuits the blocking walk", function()
    local walked = false
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["hit.lua"] = { "/cached/hit.lua" } }),
    }, function()
      H.with_field(vim.fs, "find", function()
        walked = true
        return {}
      end, function()
        local r = TS.resolve_sync("hit.lua", { roots = { "/irrelevant" } })
        H.eq(r.path, "/cached/hit.lua")
      end)
    end)
    H.falsy(walked, "vim.fs.find was never reached")
  end)

  H.check("resolve_sync: on a cache miss it walks the given roots", function()
    local root = H.tmpdir()
    H.write(root .. "/a/b/uniq_sync.lua", { "" })
    H.with_modules({ ["gopath.truncated.cache"] = fake_cache({}) }, function()
      local r = TS.resolve_sync("b/uniq_sync.lua", { roots = { root } })
      H.truthy(r, "expected a result")
      H.match(r.path, "b/uniq_sync%.lua$")
      H.eq(r.confidence, 0.85, "an unambiguous hit on one suffix")
    end)
  end)

  H.check("resolve_sync: nothing anywhere means nil, and an empty tail short-circuits", function()
    local root = H.tmpdir()
    H.with_modules({ ["gopath.truncated.cache"] = fake_cache({}) }, function()
      H.is_nil(TS.resolve_sync("no_such_file_here.lua", { roots = { root } }))
      H.is_nil(TS.resolve_sync("", { roots = { root } }))
      ---@diagnostic disable-next-line: param-type-mismatch
      H.is_nil(TS.resolve_sync(nil, { roots = { root } }))
    end)
  end)

  -- ── resolve_async ──────────────────────────────────────────────────────────

  H.check("resolve_async: an empty tail answers immediately with nil", function()
    local answered, value = false, "unset"
    TS.resolve_async("", {}, function(r)
      answered, value = true, r
    end)
    H.truthy(answered, "called back synchronously")
    H.is_nil(value)
  end)

  H.check("resolve_async: a cache hit skips the live search entirely", function()
    local started = false
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua" } }),
      ["gopath.truncated.finder"] = {
        find_async = function()
          started = true
        end,
      },
    }, function()
      local got
      TS.resolve_async("c.lua", { line = 2 }, function(r)
        got = r
      end, function()
        error("on_live_start must not fire for a cache hit")
      end)
      H.truthy(got, "answered")
      H.eq(got.confidence, 0.9, "the async path scores a single cache hit higher than the sync one")
      H.same(got.range, { line = 2, col = 1 })
    end)
    H.falsy(started, "the walker was never asked")
  end)

  H.check(
    "resolve_async: on a miss it announces the live search and forwards roots/limit",
    function()
      local seen_args, announced
      H.with_modules({
        ["gopath.truncated.cache"] = fake_cache({}),
        ["gopath.truncated.finder"] = {
          find_async = function(tail, opts, on_done)
            seen_args = { tail = tail, opts = opts }
            on_done({ "/found/a/c.lua", "/found/b/deeper/c.lua" })
          end,
        },
      }, function()
        local got
        TS.resolve_async("c.lua", { roots = { "/r1" }, limit = 7 }, function(r)
          got = r
        end, function()
          announced = true
        end)
        H.truthy(announced, "the user is only told when the slow walk really starts")
        H.eq(seen_args.tail, "c.lua")
        H.same(seen_args.opts.roots, { "/r1" })
        H.eq(seen_args.opts.limit, 7)
        H.eq(got.path, "/found/a/c.lua", "shortest of the hits")
        H.eq(got.confidence, 0.8, "ambiguous")
      end)
    end
  )

  H.check("resolve_async: no hits, and a missing finder module, both answer nil", function()
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({}),
      ["gopath.truncated.finder"] = {
        find_async = function(_, _, on_done)
          on_done({})
        end,
      },
    }, function()
      local got = "unset"
      TS.resolve_async("c.lua", {}, function(r)
        got = r
      end)
      H.is_nil(got)
    end)

    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({}),
      ["gopath.truncated.finder"] = false,
    }, function()
      local got, announced = "unset", false
      TS.resolve_async("c.lua", {}, function(r)
        got = r
      end, function()
        announced = true
      end)
      H.is_nil(got, "answered nil")
      H.falsy(announced, "and never claimed a search had started")
    end)
  end)

  -- ── probe ──────────────────────────────────────────────────────────────────

  H.check("probe: an unusable token answers nil without searching", function()
    local got = "unset"
    TS.probe("", {}, function(r)
      got = r
    end)
    H.is_nil(got, "empty raw token")

    got = "unset"
    TS.probe(":::", {}, function(r)
      got = r
    end)
    H.is_nil(got, "a token that sanitizes to nothing")
  end)

  H.check("probe: a single cache hit is returned without asking the user", function()
    H.with_modules(
      { ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua" } }) },
      function()
        local got
        TS.probe("c.lua:9", {}, function(r)
          got = r
        end)
        H.truthy(got)
        H.eq(got.path, "/x/c.lua")
        H.eq(got.confidence, 0.85)
        H.same(got.range, { line = 9, col = 1 }, "the :line suffix survives sanitisation")
      end
    )
  end)

  H.check("probe: ambiguity with ask = false picks the shortest silently", function()
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/z/c.lua" } }),
      ["ui.kit"] = {
        select = function()
          error("ask = false must not open a picker")
        end,
      },
    }, function()
      local got
      TS.probe("c.lua", { ask = false }, function(r)
        got = r
      end)
      H.eq(got.path, "/x/c.lua")
    end)
  end)

  H.check("probe: ambiguity with ask = true offers the matches and honours the choice", function()
    local shown
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/z/c.lua" } }),
      ["ui.kit"] = {
        select = function(spec)
          shown = spec
          spec.on_select("/y/z/c.lua")
        end,
      },
    }, function()
      local got
      TS.probe("c.lua", { ask = true }, function(r)
        got = r
      end)
      H.truthy(shown, "the picker was opened")
      H.same(shown.items, { "/x/c.lua", "/y/z/c.lua" })
      H.match(shown.title, "multiple matches")
      H.eq(got.path, "/y/z/c.lua", "the user's choice, not the shortest")
      H.eq(got.confidence, 0.85)
    end)
  end)

  H.check("probe: without ui.nvim, ambiguity falls back to vim.ui.select (LUA-01)", function()
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/z/c.lua" } }),
      ["ui.kit"] = false,
    }, function()
      local got
      local calls = H.with_ui_select("/y/z/c.lua", function()
        TS.probe("c.lua", { ask = true }, function(r)
          got = r
        end)
      end)
      H.eq(#calls, 1, "vim.ui.select was offered the matches")
      H.same(calls[1].items, { "/x/c.lua", "/y/z/c.lua" })
      H.eq(got.path, "/y/z/c.lua")
      H.eq(got.confidence, 0.85)
    end)
  end)

  H.check("probe: dismissing the vim.ui.select fallback still calls back once, with nil", function()
    local calls = 0
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/c.lua" } }),
      ["ui.kit"] = false,
    }, function()
      local got = "unset"
      H.with_ui_select(nil, function()
        TS.probe("c.lua", { ask = true }, function(r)
          calls = calls + 1
          got = r
        end)
      end)
      H.is_nil(got)
    end)
    H.eq(calls, 1, "on_done fires exactly once")
  end)

  H.check("probe: dismissing the picker still calls back exactly once, with nil", function()
    local calls = 0
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({ ["c.lua"] = { "/x/c.lua", "/y/c.lua" } }),
      ["ui.kit"] = {
        select = function(spec)
          spec.on_cancel()
        end,
      },
    }, function()
      local got = "unset"
      TS.probe("c.lua", { ask = true }, function(r)
        calls = calls + 1
        got = r
      end)
      H.is_nil(got)
    end)
    H.eq(calls, 1, "on_done fires exactly once, as the contract promises")
  end)

  H.check("probe: the picker shortens paths under the first root for display", function()
    local shown
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({
        ["c.lua"] = { "/root/a/c.lua", "/elsewhere/c.lua" },
      }),
      ["ui.kit"] = {
        select = function(spec)
          shown = spec
          spec.on_cancel()
        end,
      },
    }, function()
      TS.probe("c.lua", { ask = true, roots = { "/root" } }, function() end)
    end)
    H.eq(shown.format_item("/root/a/c.lua"), "./a/c.lua", "relative to the first root")
    H.eq(shown.format_item("/elsewhere/c.lua"), "/elsewhere/c.lua", "outside it, shown in full")
  end)

  H.check("probe: a cache miss goes to the live walker with the resolved roots", function()
    local seen
    H.with_modules({
      ["gopath.truncated.cache"] = fake_cache({}),
      ["gopath.truncated.finder"] = {
        find_async = function(tail, opts, on_done)
          seen = { tail = tail, opts = opts }
          on_done({ "/live/c.lua" })
        end,
      },
    }, function()
      local got
      TS.probe("c.lua", { roots = { "/given" }, limit = 5 }, function(r)
        got = r
      end)
      H.eq(seen.tail, "c.lua")
      H.same(seen.opts.roots, { "/given" })
      H.eq(seen.opts.limit, 5)
      H.eq(got.path, "/live/c.lua")
    end)
  end)
end
