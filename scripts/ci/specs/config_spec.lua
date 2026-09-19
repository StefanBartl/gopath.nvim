-- scripts/ci/specs/config_spec.lua
-- gopath.config: the defaults table and the recursive merge on top of it.
--
-- scripts/ci/functional_tests.lua already pins the two curated-array cases
-- (`order`, `truncated.excluded_dirs`) end-to-end. This spec covers the merge
-- function itself: what counts as a list, how deep nesting behaves, what
-- `setup()` accumulating rather than resetting actually means for a caller,
-- and the shape of the defaults the rest of the plugin reads.

---@param H table
return function(H)
  local config = require("gopath.config")

  H.check("defaults: the fields every other module reads are present and typed", function()
    local cfg = config.get()
    H.eq(type(cfg), "table")
    H.eq(cfg.mode, "hybrid", "hybrid runs the whole provider order")
    H.same(cfg.order, { "lsp", "treesitter", "builtin" })
    H.eq(cfg.lsp_timeout_ms, 200)
    H.eq(cfg.dev_mode, false)
    H.eq(type(cfg.languages), "table")
    H.eq(type(cfg.mappings), "table")
    H.eq(type(cfg.commands), "table")
    H.eq(cfg.which_key, true)
    H.eq(cfg.deps_popup, true)
  end)

  H.check("defaults: every registered filetype has a language entry", function()
    local cfg = config.get()
    -- gopath.registry keys RES by filetype; a filetype missing here would make
    -- `resolve.lua`'s `type(lang) == "table"` gate skip its pipeline entirely.
    for _, ft in ipairs({
      "lua",
      "python",
      "javascript",
      "javascriptreact",
      "typescript",
      "typescriptreact",
      "rust",
      "go",
      "c",
      "cpp",
      "cs",
      "zig",
      "java",
    }) do
      H.eq(type(cfg.languages[ft]), "table", ft .. " has a language entry")
      H.eq(cfg.languages[ft].enable, true, ft .. " is enabled by default")
    end
  end)

  H.check("defaults: feature toggles all default to on", function()
    local cfg = config.get()
    H.eq(cfg.alternate.enable, true)
    H.eq(cfg.external.enable, true)
    H.eq(cfg.url.enable, true)
    H.eq(cfg.url.bare_hosts, true)
    H.eq(cfg.env_variable_resolution.enable, true)
    H.eq(cfg.create_on_missing.enable, true)
    H.eq(cfg.create_on_missing.confirm, true)
    H.eq(cfg.truncated.enable, true)
    H.eq(cfg.linepath.enable, true)
    H.eq(cfg.linepath.cascade, true)
    H.eq(cfg.tailsearch.enable, true)
    H.same(cfg.env_variable_resolution.shorten_dirs, { repos = "REPOS_DIR" })
    H.eq(cfg.external.pdf.picker, true)
    H.eq(cfg.external.pdf.default, "system")
  end)

  H.check("setup(nil) and setup(non-table) change nothing", function()
    H.config_sandbox(function(c)
      local before = vim.deepcopy(c.get())
      c.setup(nil)
      ---@diagnostic disable-next-line: param-type-mismatch
      c.setup("nope")
      ---@diagnostic disable-next-line: param-type-mismatch
      c.setup(42)
      H.same(c.get(), before, "the state is untouched")
    end)
  end)

  H.check("setup: a nested override leaves its siblings alone", function()
    H.config_sandbox(function(c)
      c.setup({ truncated = { max_depth = 3 } })
      local t = c.get().truncated
      H.eq(t.max_depth, 3, "the overridden field")
      H.eq(t.enable, true, "a sibling default survives")
      H.eq(t.cache_refresh_interval, 600, "and another")
      H.eq(#t.excluded_dirs, 7, "the untouched curated list is intact")
    end)
  end)

  H.check("setup: a list value replaces wholesale, it is never index-merged", function()
    H.config_sandbox(function(c)
      c.setup({ tailsearch = { roots = { "/one", "/two" } } })
      H.same(c.get().tailsearch.roots, { "/one", "/two" })
      c.setup({ tailsearch = { roots = { "/only" } } })
      H.same(
        c.get().tailsearch.roots,
        { "/only" },
        "the longer previous list does not bleed through"
      )
    end)
  end)

  H.check("setup: an empty list counts as a list and clears the default", function()
    H.config_sandbox(function(c)
      c.setup({ truncated = { excluded_dirs = {} } })
      H.eq(#c.get().truncated.excluded_dirs, 0, "the user asked to exclude nothing")
    end)
  end)

  H.check("setup: a map-valued override merges rather than replacing", function()
    H.config_sandbox(function(c)
      c.setup({ mappings = { open_here = "gX" } })
      local m = c.get().mappings
      H.eq(m.open_here, "gX", "the overridden key")
      H.eq(m.debug, "g?", "every other mapping keeps its default")
      H.eq(m.probe, "<leader>pp")
    end)
  end)

  H.check("setup: a list replacing a map (and vice versa) takes the user's value", function()
    H.config_sandbox(function(c)
      -- `mappings = false` is the documented way to drop the whole preset.
      c.setup({ mappings = false })
      H.eq(c.get().mappings, false, "a scalar overwrites a table outright")
    end)
    H.eq(type(config.get().mappings), "table", "and the sandbox put it back")
  end)

  H.check("setup: deep nesting is merged all the way down", function()
    H.config_sandbox(function(c)
      c.setup({ alternate = { frecency = { max_bonus = 42 } } })
      local alt = c.get().alternate
      H.eq(alt.frecency.max_bonus, 42, "three levels deep")
      H.eq(alt.frecency.enable, true, "its sibling survived")
      H.eq(alt.enable, true, "and so did its parent's")
      H.eq(alt.similarity_threshold, 75)
    end)
  end)

  H.check("setup: unknown keys are kept, not dropped", function()
    H.config_sandbox(function(c)
      c.setup({ my_own_flag = "keep me", languages = { haskell = { enable = true } } })
      H.eq(c.get().my_own_flag, "keep me", "top-level")
      H.eq(c.get().languages.haskell.enable, true, "a language gopath has no resolver for")
    end)
  end)

  H.check(
    "setup: a misspelled key is kept but flagged with a did-you-mean hint (ERR-50)",
    function()
      H.config_sandbox(function(c)
        H.capture_notify(function()
          c.setup({ truncted = { enable = false } })
        end)
        H.eq(c.get().truncted.enable, false, "still kept, same as any other unknown key")
        H.eq(c.get().truncated.enable, true, "the real option never moved off its default")
        H.match(
          table.concat(c.issues(), "\n"),
          "unknown option 'truncted' %(did you mean 'truncated'%?%)"
        )
      end)
    end
  )

  H.check("setup: a misspelled nested key is flagged the same way", function()
    H.config_sandbox(function(c)
      H.capture_notify(function()
        c.setup({ mappings = { open_vspit = "gv" } })
      end)
      H.match(
        table.concat(c.issues(), "\n"),
        "unknown option 'mappings.open_vspit' %(did you mean 'mappings.open_vsplit'%?%)"
      )
    end)
  end)

  H.check(
    "setup: a wrong-shaped value degrades to the default instead of the crash it used to cause (ERR-22)",
    function()
      H.config_sandbox(function(c)
        H.capture_notify(function()
          ---@diagnostic disable-next-line: assign-type-mismatch
          c.setup({ order = "lsp" })
        end)
        H.same(c.get().order, { "lsp", "treesitter", "builtin" }, "order stayed the default list")
        H.match(table.concat(c.issues(), "\n"), "option 'order' must be a list, got string")
      end)
    end
  )

  H.check("setup: languages = false degrades to the default table (ERR-22)", function()
    H.config_sandbox(function(c)
      H.capture_notify(function()
        ---@diagnostic disable-next-line: assign-type-mismatch
        c.setup({ languages = false })
      end)
      H.eq(c.get().languages.lua.enable, true, "languages stayed the default table")
      H.match(table.concat(c.issues(), "\n"), "option 'languages' must be a table, got boolean")
    end)
  end)

  H.check(
    "setup: mappings/commands still accept `false` (the documented whole-preset toggle)",
    function()
      H.config_sandbox(function(c)
        local notes = H.capture_notify(function()
          c.setup({ mappings = false, commands = false })
        end)
        H.eq(c.get().mappings, false)
        H.eq(c.get().commands, false)
        H.eq(#c.issues(), 0, "false is a valid shape here, not a type error")
        H.eq(#notes, 0, "and so nothing was warned about")
      end)
    end
  )

  H.check("issues() is empty after a clean setup(), even following an earlier bad one", function()
    H.config_sandbox(function(c)
      H.capture_notify(function()
        ---@diagnostic disable-next-line: assign-type-mismatch
        c.setup({ order = "lsp" })
      end)
      H.truthy(#c.issues() > 0, "the first call left something to report")
      H.capture_notify(function()
        c.setup({ dev_mode = true })
      end)
      H.eq(#c.issues(), 0, "a later well-formed call clears it")
    end)
  end)

  H.check("setup: values are copied out of the user's list, not aliased", function()
    H.config_sandbox(function(c)
      local mine = { "a", "b" }
      c.setup({ order = mine })
      table.insert(mine, "c")
      H.eq(#c.get().order, 2, "mutating the caller's list afterwards does not reach the config")
    end)
  end)

  H.check("setup accumulates across calls — a second call does not reset to defaults", function()
    H.config_sandbox(function(c)
      c.setup({ lsp_timeout_ms = 999 })
      c.setup({ dev_mode = true })
      H.eq(c.get().lsp_timeout_ms, 999, "the first call's value is still there")
      H.eq(c.get().dev_mode, true, "alongside the second call's")
    end)
  end)

  H.check("get() hands back the live state, exactly as documented", function()
    -- Not a defect: the docstring says "read-only reference", and nothing in
    -- gopath promises a copy (unlike, say, replacer.nvim's `get()`). Pinned
    -- because H.config_sandbox depends on it, and because a future change to a
    -- deep copy would silently break every caller that mutates what it got.
    H.config_sandbox(function(c)
      local a, b = c.get(), c.get()
      H.eq(a, b, "the same table object every time")
      a.dev_mode = true
      H.eq(c.get().dev_mode, true, "a mutation of the returned table is the config")
    end)
  end)
end
