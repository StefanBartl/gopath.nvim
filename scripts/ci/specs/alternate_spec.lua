-- scripts/ci/specs/alternate_spec.lua
-- gopath.alternate: the fuzzy "did you mean this file instead?" flow —
-- directory helpers, the similarity matcher, the selection UI and the
-- callback contract the whole thing hangs on.
--
-- The frecency reordering has its own end-to-end group in
-- scripts/ci/functional_tests.lua (it is about the saturating ceiling, which
-- needs a real store); what is asserted here is where it sits in the flow.

---@param H table
return function(H)
  local dir_helper = require("gopath.alternate.helpers.directory")
  local matcher = require("gopath.alternate.helpers.matcher")
  local ui = require("gopath.alternate.ui")
  local alternate = require("gopath.alternate")

  -- ── directory helpers ──────────────────────────────────────────────────────

  H.check("is_directory / extract_directory / extract_filename", function()
    local dir = H.tmpdir()
    local file = H.write(dir .. "/notes/a.md", { "" })

    H.eq(dir_helper.is_directory(dir), true)
    H.eq(dir_helper.is_directory(file), false, "a file is not a directory")
    H.eq(dir_helper.is_directory(dir .. "/nope"), false)
    H.eq(dir_helper.is_directory(""), false)
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(dir_helper.is_directory(nil), false)

    H.eq(
      (vim.fs.normalize(dir_helper.extract_directory(file))),
      (vim.fs.normalize(dir .. "/notes")),
      "the parent directory"
    )
    H.is_nil(dir_helper.extract_directory("/no/such/place/at/all/x.md"), "no directory to return")
    H.is_nil(dir_helper.extract_directory(""), "empty input")

    H.eq(dir_helper.extract_filename(file), "a.md")
    H.eq(dir_helper.extract_filename([[C:\x\y\b.md]]), "b.md", "backslash spelling")
    H.is_nil(dir_helper.extract_filename(""), "empty input")
  end)

  H.check("scan_directory: regular files only, nil for an unreadable directory", function()
    local dir = H.tmpdir()
    H.write(dir .. "/a.md", { "" })
    H.write(dir .. "/b.md", { "" })
    H.mkdir(dir .. "/subdir")

    local files = dir_helper.scan_directory(dir)
    H.eq(#files, 2, "the subdirectory is not a file")
    H.is_nil(dir_helper.scan_directory(dir .. "/missing"), "an unreadable directory")
  end)

  H.check("file_meta: human-readable size and age, nil when the file vanished", function()
    local dir = H.tmpdir()
    local file = H.write(dir .. "/meta.md", { "hello" })
    local meta = dir_helper.file_meta(file)
    H.truthy(meta, "expected a summary")
    H.match(meta, "^%d+ B, modified ", "bytes for a tiny file, then the age")
    H.match(meta, "just now", "freshly written")
    H.is_nil(dir_helper.file_meta(dir .. "/vanished.md"), "cosmetic, so a miss is nil not an error")

    local big = H.write(dir .. "/big.md", { string.rep("x", 3000) })
    H.match(dir_helper.file_meta(big), "KB", "kilobytes once it is large enough")
  end)

  -- ── matcher ────────────────────────────────────────────────────────────────

  H.check("calculate_similarity: identical, case-insensitive, and unrelated", function()
    H.eq(matcher.calculate_similarity("config.lua", "config.lua"), 100, "identical")
    H.eq(matcher.calculate_similarity("Config.lua", "config.lua"), 100, "case is ignored")
    H.truthy(matcher.calculate_similarity("config.lua", "zzzzzzzzzz") < 40, "unrelated")
  end)

  H.check("calculate_similarity: a shared prefix is worth more than edit distance alone", function()
    local truncated = matcher.calculate_similarity("confi", "config.lua")
    H.truthy(truncated >= 50, "a truncated name still scores its prefix ratio: " .. truncated)
    H.truthy(
      truncated > matcher.calculate_similarity("confi", "xxxxxg.lua"),
      "and beats a same-length name that shares nothing"
    )
  end)

  H.check("find_similar_files: threshold, sorting and the empty cases", function()
    local dir = H.tmpdir()
    H.write(dir .. "/config.lua", { "" })
    H.write(dir .. "/configs.lua", { "" })
    H.write(dir .. "/unrelated_thing.txt", { "" })

    local matches = matcher.find_similar_files(dir, "config.lua", 75)
    H.eq(#matches, 2, "the unrelated file is below the threshold")
    H.eq(matches[1].filename, "config.lua", "sorted by similarity, best first")
    H.eq(matches[1].similarity, 100)
    H.truthy(matches[2].similarity < 100)
    H.match(matches[1].path, "config%.lua$", "the full path comes along")

    H.same(matcher.find_similar_files(dir, "config.lua", 101), {}, "an impossible threshold")
    H.same(matcher.find_similar_files(dir .. "/missing", "x", 0), {}, "an unreadable directory")
    H.same(matcher.find_similar_files(H.tmpdir(), "x", 0), {}, "an empty directory")
  end)

  -- ── selection UI ───────────────────────────────────────────────────────────

  H.check("present_selection: an empty candidate list reports 'nothing chosen'", function()
    local answered, choice = false, "unset"
    ui.present_selection({}, "/gone.lua", {
      on_choice = function(c)
        answered, choice = true, c
      end,
    })
    H.truthy(answered, "the callback still fires")
    H.is_nil(choice)
  end)

  H.check("present_selection: ui.kit is preferred and gets a formatted, titled list", function()
    local dir = H.tmpdir()
    local file = H.write(dir .. "/config.lua", { "x" })
    local shown
    H.with_modules({
      ["ui.kit"] = {
        select = function(spec)
          shown = spec
          spec.on_select(spec.items[1])
        end,
      },
    }, function()
      local got
      ui.present_selection(
        { { path = file, filename = "config.lua", similarity = 87.5 } },
        "/gone.lua",
        {
          on_choice = function(c)
            got = c
          end,
        }
      )
      H.truthy(shown, "the picker opened")
      H.eq(shown.respect_override, true, "a user's own vim.ui.select still wins")
      H.match(shown.title, "File not found: gone%.lua", "the title names the missing file")
      local label = shown.format_item(shown.items[1])
      H.match(label, "config%.lua %(88%%%)", "name and rounded similarity")
      H.match(label, "— %d+ B, modified", "plus the size/age hint")
      H.eq(got.path, file, "the choice is reported")
    end)
  end)

  H.check("present_selection: cancelling reports nil exactly once", function()
    local calls, got = 0, "unset"
    H.with_modules({
      ["ui.kit"] = {
        select = function(spec)
          spec.on_cancel()
        end,
      },
    }, function()
      ui.present_selection({ { path = "/a", filename = "a", similarity = 90 } }, "/gone.lua", {
        on_choice = function(c)
          calls = calls + 1
          got = c
        end,
      })
    end)
    H.eq(calls, 1)
    H.is_nil(got)
  end)

  H.check("present_selection: without ui.nvim it falls back to vim.ui.select", function()
    local dir = H.tmpdir()
    local file = H.write(dir .. "/config.lua", { "x" })
    H.with_modules({ ["ui.kit"] = false }, function()
      local got
      local calls = H.with_ui_select(function(items)
        return items[1]
      end, function()
        ui.present_selection(
          { { path = file, filename = "config.lua", similarity = 90 } },
          "/gone.lua",
          {
            on_choice = function(c)
              got = c
            end,
          }
        )
      end)
      H.eq(#calls, 1)
      H.match(calls[1].opts.prompt, "File not found")
      H.eq(type(calls[1].opts.format_item), "function")
      H.eq(got.path, file)
    end)
  end)

  H.check("present_selection: a missing on_choice is not an error", function()
    H.with_modules({ ["ui.kit"] = false }, function()
      H.with_ui_select(nil, function()
        ui.present_selection({ { path = "/a", filename = "a", similarity = 90 } }, "/g.lua", {})
        ---@diagnostic disable-next-line: param-type-mismatch
        ui.present_selection({ { path = "/a", filename = "a", similarity = 90 } }, "/g.lua", nil)
      end)
    end)
    H.truthy(true, "no error")
  end)

  -- ── try_resolve ────────────────────────────────────────────────────────────

  H.check("try_resolve: reports 'nothing shown' for junk input and empty directories", function()
    local function handled_for(path)
      local seen = "unset"
      alternate.try_resolve(path, {}, function(h)
        seen = h
      end)
      return seen
    end

    H.eq(handled_for(""), false, "empty path")
    ---@diagnostic disable-next-line: param-type-mismatch
    H.eq(handled_for(nil), false, "nil path")
    H.eq(handled_for("/no/such/directory/at/all/x.lua"), false, "the directory does not exist")
    H.eq(handled_for(H.tmpdir() .. "/x.lua"), false, "the directory is empty")
  end)

  H.check("try_resolve: nothing above the threshold is 'nothing shown'", function()
    local dir = H.tmpdir()
    H.write(dir .. "/completely_different.txt", { "" })
    local seen = "unset"
    alternate.try_resolve(dir .. "/config.lua", { similarity_threshold = 95 }, function(h)
      seen = h
    end)
    H.eq(seen, false)
  end)

  H.check("try_resolve: a picked candidate is opened through gopath.open", function()
    local dir = H.tmpdir()
    local other = H.write(dir .. "/configs.lua", { "" })
    local opened, handled
    H.with_modules({
      ["gopath.open"] = {
        open = function(res, mode)
          opened = { res = res, mode = mode }
        end,
      },
      ["ui.kit"] = {
        select = function(spec)
          spec.on_select(spec.items[1])
        end,
      },
    }, function()
      alternate.try_resolve(
        dir .. "/config.lua",
        { mode = "vsplit", range = { line = 5, col = 1 } },
        function(h)
          handled = h
        end
      )
    end)
    H.eq(handled, true, "handled, so the caller must not offer to create the original")
    H.truthy(opened, "gopath.open was used, not a raw :edit")
    H.eq(opened.mode, "vsplit", "the window mode is carried through")
    H.eq(opened.res.path, other)
    H.eq(opened.res.kind, "file")
    H.eq(opened.res.source, "alternate")
    H.eq(opened.res.exists, true, "so the create offer is skipped")
    H.same(opened.res.range, { line = 5, col = 1 }, "the original result's position is kept")
  end)

  H.check(
    "try_resolve: cancelling counts as NOT handled, so the caller can still offer to create the original",
    function()
      local dir = H.tmpdir()
      H.write(dir .. "/configs.lua", { "" })
      local opened, handled = false, nil
      H.with_modules({
        ["gopath.open"] = {
          open = function()
            opened = true
          end,
        },
        ["ui.kit"] = {
          select = function(spec)
            spec.on_cancel()
          end,
        },
      }, function()
        alternate.try_resolve(dir .. "/config.lua", {}, function(h)
          handled = h
        end)
      end)
      H.eq(
        handled,
        false,
        "declining the alternates is not the same as declining to create the original"
      )
      H.falsy(opened, "and nothing was opened")
    end
  )

  H.check("try_resolve: the frecency pass sees the candidates before the picker does", function()
    local dir = H.tmpdir()
    H.write(dir .. "/configs.lua", { "" })
    H.write(dir .. "/config.lua", { "" })
    local reranked, recorded
    H.with_modules({
      ["gopath.alternate.frecency"] = {
        rerank = function(matches)
          reranked = #matches
          return matches
        end,
        record = function(path)
          recorded = path
        end,
      },
      ["gopath.open"] = { open = function() end },
      ["ui.kit"] = {
        select = function(spec)
          spec.on_select(spec.items[1])
        end,
      },
    }, function()
      alternate.try_resolve(dir .. "/config.lua", {}, function() end)
    end)
    H.eq(reranked, 2, "both candidates were offered for reordering")
    H.truthy(recorded, "and the choice was recorded")
  end)

  H.check("try_resolve_with_matches: pre-computed candidates skip the directory scan", function()
    local opened, handled
    H.with_modules({
      ["gopath.open"] = {
        open = function(res, mode)
          opened = { res = res, mode = mode }
        end,
      },
      ["ui.kit"] = {
        select = function(spec)
          spec.on_select(spec.items[2])
        end,
      },
    }, function()
      alternate.try_resolve_with_matches(
        {
          { path = "/a/first.lua", filename = "first.lua", similarity = 90 },
          { path = "/a/second.lua", filename = "second.lua", similarity = 80 },
        },
        "/a/orig.lua",
        { mode = "tab" },
        function(h)
          handled = h
        end
      )
    end)
    H.eq(handled, true)
    H.eq(opened.res.path, "/a/second.lua", "the second entry was chosen")
    H.eq(opened.mode, "tab")
  end)

  H.check("try_resolve_with_matches: an empty match list is 'nothing shown'", function()
    local seen = "unset"
    alternate.try_resolve_with_matches({}, "/a/orig.lua", {}, function(h)
      seen = h
    end)
    H.eq(seen, false)
    ---@diagnostic disable-next-line: param-type-mismatch
    alternate.try_resolve_with_matches(nil, "/a/orig.lua", {}, function(h)
      seen = h
    end)
    H.eq(seen, false, "nil list too")
  end)
end
