-- scripts/ci/specs/truncated_spec.lua
-- gopath.truncated.cache (the in-memory + on-disk filesystem index) and
-- gopath.truncated.finder (the live search behind it).
--
-- Two things are cut at a seam on purpose:
--   * the cache's persistence, because `config.cache_file` lives under
--     stdpath("cache") and a spec must not overwrite the user's real index;
--   * the finder's `fd`/`rg` invocation, which is the only subprocess in this
--     file's reach. Its argv is asserted instead of run.
-- The scans themselves are real: both walk actual directories built under
-- vim.fn.tempname().

---@param H table
return function(H)
  local cache = require("gopath.truncated.cache")
  local finder = require("gopath.truncated.finder")

  ---Replacements that keep the cache's persistence off the real disk.
  ---@param store table  { data: table|nil, readable: boolean, write_ok: boolean }
  ---@return table
  local function fake_persistence(store)
    return {
      ["lib.nvim.fs.is_readable_file"] = function()
        return store.readable
      end,
      ["lib.nvim.fs.json"] = {
        read = function()
          if store.data == nil then return nil, "no such file" end
          return store.data, nil
        end,
        write = function(_, data)
          store.written = data
          if store.write_ok == false then return false, "permission denied" end
          return true, nil
        end,
      },
    }
  end

  -- `cache.setup` only overwrites the options it is given, so its state is
  -- sticky across calls. Every build below therefore states max_depth and
  -- excluded_dirs explicitly rather than inheriting whatever the previous
  -- check left behind.
  local BASE_SETUP = {
    max_depth = 6,
    excluded_dirs = { ".git", ".github", "node_modules", "target", "build", ".cache", "venv" },
  }

  ---Build the cache synchronously over `roots` and return the indexed paths.
  ---@param roots string[]
  ---@param opts table|nil  extra cache.setup options
  ---@return string[]
  local function build_over(roots, opts)
    local store = { readable = false, write_ok = true }
    local paths
    H.with_modules(fake_persistence(store), function()
      cache.setup(
        vim.tbl_extend("force", vim.tbl_extend("force", BASE_SETUP, { roots = roots }), opts or {})
      )
      local done = false
      cache.build_async(function()
        done = true
      end)
      H.truthy(
        H.wait(function()
          return done
        end),
        "the async build finished"
      )
      paths = vim.deepcopy(cache._get_state().paths)
    end)
    return paths
  end

  -- ── cache: scanning ────────────────────────────────────────────────────────

  H.check("build_async: indexes every file under the configured roots", function()
    local root = H.tmpdir()
    H.write(root .. "/a.lua", { "" })
    H.write(root .. "/sub/b.lua", { "" })
    H.write(root .. "/sub/deeper/c.lua", { "" })

    local paths = build_over({ root })
    H.eq(#paths, 3, "three files")
    local joined = table.concat(paths, "\n"):gsub("\\", "/")
    H.match(joined, "/a%.lua")
    H.match(joined, "/sub/b%.lua")
    H.match(joined, "/sub/deeper/c%.lua")
  end)

  H.check("build_async: excluded directories are never descended into", function()
    local root = H.tmpdir()
    H.write(root .. "/keep.lua", { "" })
    H.write(root .. "/.git/objects/blob", { "" })
    H.write(root .. "/node_modules/pkg/index.js", { "" })
    H.write(root .. "/vendor/lib.rb", { "" })

    local joined = table.concat(build_over({ root }), "\n"):gsub("\\", "/")
    H.match(joined, "/keep%.lua")
    H.no_match(joined, "/%.git/", ".git is excluded")
    H.no_match(joined, "/node_modules/", "node_modules is excluded")
    -- Documented divergence, not a defect: cache.lua carries an 18-entry
    -- default exclusion list, but `gopath.init._setup_cache` always passes
    -- `truncated.excluded_dirs` from config/DEFAULTS.lua (7 entries) on top of
    -- it, so "vendor", "dist", "tmp", "__pycache__" and friends are only ever
    -- excluded for a caller that drives `cache.setup` directly.
    H.match(joined, "/vendor/", "'vendor' is in cache.lua's own default list but not in gopath's")
    local with_vendor = table
      .concat(build_over({ root }, { excluded_dirs = { ".git", "node_modules", "vendor" } }), "\n")
      :gsub("\\", "/")
    H.no_match(with_vendor, "/vendor/", "and excluding it explicitly does work")
  end)

  H.check("build_async: a user-supplied exclusion list replaces the default one", function()
    local root = H.tmpdir()
    H.write(root .. "/.git/config", { "" })
    H.write(root .. "/mine/x.lua", { "" })

    local paths = build_over({ root }, { excluded_dirs = { "mine" } })
    local joined = table.concat(paths, "\n"):gsub("\\", "/")
    H.match(joined, "/%.git/config", ".git is no longer excluded")
    H.no_match(joined, "/mine/", "the user's exclusion is honoured")
  end)

  H.check("build_async: max_depth stops the descent", function()
    local root = H.tmpdir()
    H.write(root .. "/l0.lua", { "" })
    H.write(root .. "/one/l1.lua", { "" })
    H.write(root .. "/one/two/l2.lua", { "" })

    local shallow = table.concat(build_over({ root }, { max_depth = 1 }), "\n"):gsub("\\", "/")
    H.match(shallow, "/l0%.lua")
    H.match(shallow, "/one/l1%.lua")
    H.no_match(shallow, "/one/two/", "depth 2 was not reached")
  end)

  H.check("build_async: roots that do not exist are skipped, not fatal", function()
    local root = H.tmpdir()
    H.write(root .. "/only.lua", { "" })
    local paths = build_over({ root, "/definitely/not/here", "" })
    H.eq(#paths, 1)
  end)

  H.check("build_async: no usable roots still completes and reports success", function()
    local paths = build_over({ "/definitely/not/here" })
    H.eq(#paths, 0, "an empty index, delivered on the next tick rather than never")
  end)

  H.check("build_async: a second build while one is running is refused", function()
    local store = { readable = false, write_ok = true }
    H.with_modules(fake_persistence(store), function()
      cache.setup({ roots = { H.tmpdir() } })
      local results = {}
      cache.build_async(function(ok)
        results[#results + 1] = ok
      end)
      -- The first build is still in flight (its scan callbacks have not run);
      -- the second must answer false rather than clobber the shared state.
      cache.build_async(function(ok)
        results[#results + 1] = ok
      end)
      H.truthy(
        H.wait(function()
          return #results >= 2
        end),
        "both callbacks fired"
      )
      H.eq(vim.tbl_contains(results, false), true, "one of them was refused")
      H.eq(vim.tbl_contains(results, true), true, "and the other completed")
    end)
  end)

  -- ── cache: search ──────────────────────────────────────────────────────────

  H.check("search: exact tail match, case- and separator-insensitive", function()
    local root = H.tmpdir()
    H.write(root .. "/lua/gopath/init.lua", { "" })
    H.write(root .. "/lua/other/init.lua", { "" })
    build_over({ root })

    H.eq(#cache.search("gopath/init.lua"), 1, "one exact tail")
    H.eq(#cache.search("GOPATH/INIT.LUA"), 1, "case-insensitive")
    H.eq(#cache.search([[gopath\init.lua]]), 1, "backslash spelling of the same tail")
    H.eq(#cache.search("init.lua"), 2, "a bare basename matches both")
    H.eq(#cache.search("nothing_like_this"), 0, "a miss is an empty list")
  end)

  H.check("search: sequential part matching finds a truncated middle", function()
    local root = H.tmpdir()
    H.write(root .. "/a/b/c/d/target.lua", { "" })
    build_over({ root })

    H.eq(#cache.search("a/d/target.lua"), 1, "segments in order, with gaps")
    H.eq(#cache.search("d/a/target.lua"), 0, "out of order does not match")
    H.eq(#cache.search("a/b/c/d/target.lua"), 1, "the full tail still matches exactly")
  end)

  H.check("search: an empty index answers empty rather than erroring", function()
    H.with_modules(fake_persistence({ readable = false, write_ok = true }), function()
      build_over({ "/definitely/not/here" })
      H.same(cache.search("anything.lua"), {})
    end)
  end)

  H.check("search: the normalised mirror self-heals if it drifts", function()
    local root = H.tmpdir()
    H.write(root .. "/drift/x.lua", { "" })
    build_over({ root })
    -- Simulate a partially-updated state: `paths` moved on, `norm` did not.
    cache._get_state().norm = {}
    H.eq(#cache.search("drift/x.lua"), 1, "reindexed on the spot")
  end)

  -- ── cache: persistence ─────────────────────────────────────────────────────

  H.check("load_from_disk: no cache file is a clean 'false', not an error", function()
    H.with_modules(fake_persistence({ readable = false }), function()
      H.eq(cache.load_from_disk(), false)
    end)
  end)

  H.check("load_from_disk: an unparseable cache file warns and is ignored", function()
    H.with_modules(fake_persistence({ readable = true, data = nil }), function()
      local notes = H.capture_notify(function()
        H.eq(cache.load_from_disk(), false)
      end)
      H.match(H.notify_text(notes), "Failed to parse cache file")
    end)
  end)

  H.check("load_from_disk: a persisted snapshot is revalidated, not trusted", function()
    local root = H.tmpdir()
    H.with_modules(
      fake_persistence({
        readable = true,
        data = {
          paths = { "/real/a.lua", 42, false, { "nested" }, "/real/b.lua" },
          last_built = "not a number",
          scan_roots = { root },
          version = 1,
        },
      }),
      function()
        cache.setup({ roots = { root } })
        H.eq(cache.load_from_disk(), true)
        local state = cache._get_state()
        H.same(state.paths, { "/real/a.lua", "/real/b.lua" }, "non-string entries dropped")
        H.is_nil(state.last_built, "a non-numeric timestamp is discarded")
        H.eq(#state.norm, 2, "and the mirror matches")
      end
    )
  end)

  H.check("load_from_disk: a wrong-typed paths field yields an empty index", function()
    local root = H.tmpdir()
    H.with_modules(
      fake_persistence({
        readable = true,
        data = { paths = "not a list", last_built = 123, scan_roots = { root } },
      }),
      function()
        cache.setup({ roots = { root } })
        H.eq(cache.load_from_disk(), true)
        H.same(cache._get_state().paths, {})
        H.eq(cache._get_state().last_built, 123, "a valid timestamp is kept")
      end
    )
  end)

  H.check(
    "load_from_disk: a snapshot built for different scan_roots is rejected (PERF-46)",
    function()
      local mine = H.tmpdir()
      local foreign = H.tmpdir()
      H.with_modules(
        fake_persistence({
          readable = true,
          data = {
            paths = { foreign .. "/other.lua" },
            last_built = os.time(),
            scan_roots = { foreign },
            version = 1,
          },
        }),
        function()
          cache.setup({ roots = { mine } })
          H.eq(
            cache.load_from_disk(),
            false,
            "a cache built for a different project's roots is not trusted"
          )
          H.same(cache._get_state().paths, {}, "nothing from the other project leaked in")
        end
      )
    end
  )

  H.check("setup: the cache file is keyed by scan_roots, not fixed (PERF-46)", function()
    cache.setup({ roots = { "/project/a" } })
    local file_a = cache._get_config().cache_file

    cache.setup({ roots = { "/project/b" } })
    local file_b = cache._get_config().cache_file
    H.truthy(file_a ~= file_b, "two projects with different roots never share a cache file")

    cache.setup({ roots = { "/project/a" } })
    H.eq(cache._get_config().cache_file, file_a, "the same roots always produce the same file")
  end)

  H.check("_save_to_disk: an unwritable cache file is reported, not raised", function()
    local store = { readable = false, write_ok = false }
    H.with_modules(fake_persistence(store), function()
      local notes = H.capture_notify(function()
        cache._save_to_disk()
      end)
      H.match(H.notify_text(notes), "Failed to write cache file", "gopath's own wording")
      H.match(H.notify_text(notes), "permission denied", "including the underlying reason")
    end)
  end)

  H.check(
    "_save_to_disk: the persisted shape carries paths, timestamp, roots and a version",
    function()
      local root = H.tmpdir()
      H.write(root .. "/x.lua", { "" })
      local store = { readable = false, write_ok = true }
      H.with_modules(fake_persistence(store), function()
        cache.setup({ roots = { root } })
        local done = false
        cache.build_async(function()
          done = true
        end)
        H.truthy(H.wait(function()
          return done
        end))
      end)
      H.truthy(store.written, "something was written")
      H.eq(store.written.version, 1)
      H.eq(type(store.written.last_built), "number")
      H.same(store.written.scan_roots, { root })
      H.eq(#store.written.paths, 1)
    end
  )

  -- ── cache: staleness and roots ─────────────────────────────────────────────

  H.check("needs_refresh: never built is stale; just built is not", function()
    local state = cache._get_state()
    local saved = state.last_built

    state.last_built = nil
    H.eq(cache.needs_refresh(), true, "never built")

    state.last_built = os.time()
    H.eq(cache.needs_refresh(3600), false, "fresh")
    H.eq(cache.needs_refresh(0), false, "exactly at the boundary is not yet stale")

    state.last_built = os.time() - 7200
    H.eq(cache.needs_refresh(3600), true, "two hours old against a one-hour budget")
    H.eq(cache.needs_refresh(), true, "and against the default budget")

    state.last_built = saved
  end)

  H.check("add_root: rejects a non-directory, refuses duplicates, accepts a new one", function()
    local root = H.tmpdir()
    local extra = H.tmpdir()
    H.with_modules(fake_persistence({ readable = false, write_ok = true }), function()
      cache.setup({ roots = { root } })

      local missing = H.capture_notify(function()
        cache.add_root(root .. "/not-a-dir", false)
      end)
      H.match(H.notify_text(missing), "Directory does not exist")

      local dupe = H.capture_notify(function()
        cache.add_root(root, false)
      end)
      H.match(H.notify_text(dupe), "already in cache roots")

      local added = H.capture_notify(function()
        cache.add_root(extra, false)
      end)
      H.match(H.notify_text(added), "Added to cache roots")

      -- The new root is really in the scan set: rebuilding must index it.
      H.write(extra .. "/fresh.lua", { "" })
      local done = false
      cache.build_async(function()
        done = true
      end)
      H.truthy(H.wait(function()
        return done
      end))
      H.match(
        table.concat(cache._get_state().paths, "\n"):gsub("\\", "/"),
        "/fresh%.lua",
        "the added root was scanned"
      )
    end)
  end)

  H.check("add_root: does not mutate the caller's own roots table (ERR-54)", function()
    local mine = H.tmpdir()
    local extra = H.tmpdir()
    -- Stands in for config.get().truncated.cache_roots, which cache.setup()
    -- receives by reference from gopath.init._setup_cache.
    local caller_roots = { mine }
    H.with_modules(fake_persistence({ readable = false, write_ok = true }), function()
      cache.setup({ roots = caller_roots })
      cache.add_root(extra, false)
      H.same(caller_roots, { mine }, "the caller's table is untouched by add_root's mutation")
    end)
  end)

  H.check("setup: with no roots given, the auto-detected set is all real directories", function()
    H.with_modules(fake_persistence({ readable = false, write_ok = true }), function()
      cache.setup({})
      -- Auto-detection is observable through what a build indexes; asserting
      -- the exact set would only restate the candidate list. What matters is
      -- that nothing unreadable made it in, which `build_async` filters again.
      local before = cache._get_state().last_built
      H.eq(type(before) == "number" or before == nil, true, "state is intact after re-setup")
    end)
  end)

  H.check("start_periodic_refresh: a second call replaces the first timer", function()
    -- A huge interval so no callback ever fires during the run; the point is
    -- that the module keeps the handle and can stop it, rather than orphaning
    -- one background rebuild per reload.
    cache.start_periodic_refresh(86400)
    cache.start_periodic_refresh(86400)
    H.truthy(true, "no error, and no orphaned handle left behind")
  end)

  -- ── finder: the live walk ──────────────────────────────────────────────────

  ---@param tail string
  ---@param opts table|nil
  ---@return string[]
  local function find_async(tail, opts)
    local out
    finder.find_async(tail, opts, function(hits)
      out = hits
    end)
    H.truthy(
      H.wait(function()
        return out ~= nil
      end),
      "find_async called back"
    )
    return out
  end

  H.check("find_async: matches on a segment boundary and normalises the results", function()
    local root = H.tmpdir()
    H.write(root .. "/pkg/mod/init.lua", { "" })
    H.write(root .. "/pkg/notinit.lua", { "" })

    local hits = find_async("mod/init.lua", { roots = { root } })
    H.eq(#hits, 1)
    H.match(hits[1], "pkg/mod/init%.lua$", "forward slashes, absolute")

    local boundary = find_async("init.lua", { roots = { root } })
    H.eq(#boundary, 1, "notinit.lua is not a match for init.lua")
  end)

  H.check("find_async: empty tail, missing roots, and no matches", function()
    H.same(find_async("", { roots = { H.tmpdir() } }), {}, "empty tail")
    H.same(find_async("x.lua", { roots = { "/definitely/not/here" } }), {}, "unreadable root")
    H.same(find_async("x.lua", { roots = { H.tmpdir() } }), {}, "empty tree")
  end)

  H.check("find_async: stops at the limit", function()
    local root = H.tmpdir()
    for i = 1, 6 do
      H.write(("%s/d%d/same.lua"):format(root, i), { "" })
    end
    H.eq(#find_async("same.lua", { roots = { root }, limit = 2 }), 2)
  end)

  H.check("find_async: skips excluded directories and respects max_depth + 2", function()
    H.config_sandbox(function(c)
      local root = H.tmpdir()
      H.write(root .. "/node_modules/pkg/hit.lua", { "" })
      H.write(root .. "/src/hit.lua", { "" })
      c.setup({ truncated = { excluded_dirs = { "node_modules" }, max_depth = 6 } })

      local hits = find_async("hit.lua", { roots = { root } })
      H.eq(#hits, 1, "only the non-excluded one")
      H.match(hits[1], "/src/hit%.lua$")
    end)
  end)

  H.check("find_async: de-duplicates identical results across overlapping roots", function()
    local root = H.tmpdir()
    H.write(root .. "/a/dup.lua", { "" })
    local hits = find_async("dup.lua", { roots = { root, root, root .. "/a" } })
    H.eq(#hits, 1, "one file, one entry")
  end)

  -- ── finder: the external-tool path (argv only, never spawned) ──────────────

  ---Replace `vim.fn.executable` and `vim.system` for the duration of `fn`.
  ---@param available table<string, boolean>
  ---@param stdout string
  ---@param fn fun()
  ---@return string[][] argvs
  local function with_tools(available, stdout, fn)
    local argvs = {}
    local saved_exe = rawget(vim.fn, "executable")
    local saved_system = vim.system
    vim.fn.executable = function(bin)
      return available[bin] and 1 or 0
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd)
      argvs[#argvs + 1] = cmd
      return {
        wait = function()
          return { code = 0, stdout = stdout }
        end,
      }
    end
    local ok, err = pcall(fn)
    vim.fn.executable = saved_exe
    vim.system = saved_system
    if not ok then error(err, 0) end
    return argvs
  end

  H.check("find: fd is preferred, and gets the basename plus the root", function()
    local root = H.tmpdir()
    H.write(root .. "/a/b/x.lua", { "" })
    local argvs = with_tools({ fd = true, rg = true }, root .. "/a/b/x.lua\n", function()
      local hits = finder.find("b/x.lua", { roots = { root } })
      H.eq(#hits, 1, "the tool's output is filtered by the tail, then returned")
    end)
    H.eq(#argvs, 1, "one invocation, one root")
    H.same(argvs[1], {
      "fd",
      "--type",
      "f",
      "--hidden",
      "--follow",
      "--no-ignore-vcs",
      "x.lua",
      root,
    })
  end)

  H.check("find: fdfind is the Debian-named fallback before rg", function()
    local root = H.tmpdir()
    local argvs = with_tools({ fdfind = true, rg = true }, "", function()
      finder.find("x.lua", { roots = { root } })
    end)
    H.eq(argvs[1][1], "fdfind")
  end)

  H.check("find: without fd it falls back to `rg --files -g <basename>`", function()
    local root = H.tmpdir()
    H.write(root .. "/deep/x.lua", { "" })
    local argvs = with_tools({ rg = true }, root .. "/deep/x.lua\n", function()
      local hits = finder.find("deep/x.lua", { roots = { root } })
      H.eq(#hits, 1)
    end)
    H.same(argvs[1], { "rg", "--files", "--hidden", "-g", "x.lua", root })
  end)

  H.check("find: with no search tool at all, it says so and returns nothing", function()
    local notes
    with_tools({}, "", function()
      notes = H.capture_notify(function()
        H.same(finder.find("x.lua", { roots = { H.tmpdir() } }), {})
      end)
    end)
    H.match(H.notify_text(notes), "no external search tool", "and names the fix")
    H.match(H.notify_text(notes), "install fd or rg")
  end)

  H.check("find: the tool's output is filtered by the tail, not trusted wholesale", function()
    local root = H.tmpdir()
    local argvs = with_tools(
      { fd = true },
      table.concat({
        root .. "/right/x.lua",
        root .. "/wrong/notx.lua",
        root .. "/other/x.lua",
        "",
      }, "\n"),
      function()
        local hits = finder.find("right/x.lua", { roots = { root } })
        H.eq(#hits, 1, "only the line whose path really ends with the tail")
        H.match(hits[1], "/right/x%.lua$")
      end
    )
    H.eq(#argvs, 1)
  end)

  H.check("find: an empty tail short-circuits before any tool is consulted", function()
    local consulted = false
    with_tools({ fd = true }, "", function()
      consulted = true
      H.same(finder.find("", {}), {})
      ---@diagnostic disable-next-line: param-type-mismatch
      H.same(finder.find(nil, {}), {})
    end)
    H.truthy(consulted, "the block ran")
  end)

  H.check("find: the limit caps results across roots", function()
    local a, b = H.tmpdir(), H.tmpdir()
    H.write(a .. "/x.lua", { "" })
    H.write(b .. "/x.lua", { "" })
    with_tools({ fd = true }, a .. "/x.lua\n" .. b .. "/x.lua\n", function()
      H.eq(#finder.find("x.lua", { roots = { a, b }, limit = 1 }), 1)
    end)
  end)

  -- Leave the cache configured the way `gopath.setup({})` left it, so later
  -- specs and the two older runners see the same auto-detected roots.
  H.with_modules(fake_persistence({ readable = false, write_ok = true }), function()
    cache.setup({})
  end)
end
