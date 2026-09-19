-- scripts/ci/specs/env_shorten_spec.lua
-- gopath.env_shorten: rewrite an absolute path on the current line whose root
-- segment is a configured directory name back into a `$VAR` reference.
--
-- The property under test is that the match is *structural*, not literal: it
-- must not consult the actual value of $REPOS_DIR, so the same text rewrites
-- identically on a Windows drive, a POSIX root, a `~`-relative path, or with
-- no root marker at all. TESTS/06_env_shorten.lua is the manual guide for the
-- same ten cases; these are the assertions.

---@param H table
return function(H)
  local ES = require("gopath.env_shorten")

  local PAIRS = { { segment = "repos", var = "REPOS_DIR" } }

  ---@param line string
  ---@return string result, integer count
  local function shorten(line)
    return ES.shorten(line, PAIRS)
  end

  -- ── the four recognised root forms ─────────────────────────────────────────

  H.check("Windows drive root, backslashes", function()
    local out, n = shorten([[see E:\repos\gopath.nvim\lua\gopath\env_shorten.lua]])
    H.eq(out, [[see $REPOS_DIR\gopath.nvim\lua\gopath\env_shorten.lua]])
    H.eq(n, 1, "one replacement")
  end)

  H.check("the drive letter itself never matters", function()
    local a = shorten("path: C:/repos/gopath.nvim/README.md")
    local b = shorten("path: E:/repos/gopath.nvim/README.md")
    H.eq(a, "path: $REPOS_DIR/gopath.nvim/README.md")
    H.eq(a, b, "C: and E: produce the same text")
  end)

  H.check("POSIX absolute root", function()
    H.eq(
      shorten("on Linux: /repos/gopath.nvim/README.md"),
      "on Linux: $REPOS_DIR/gopath.nvim/README.md"
    )
  end)

  H.check("home-relative root", function()
    H.eq(shorten("or: ~/repos/gopath.nvim/README.md"), "or: $REPOS_DIR/gopath.nvim/README.md")
    H.eq(shorten([[or: ~\repos\x]]), [[or: $REPOS_DIR\x]], "backslash after ~")
  end)

  H.check("bare root-relative, with a trailing separator", function()
    H.eq(shorten("repos/gopath.nvim/README.md"), "$REPOS_DIR/gopath.nvim/README.md")
  end)

  H.check("a marked root may end the token bare", function()
    H.eq(shorten([[E:\repos]]), "$REPOS_DIR", "a directory reference with nothing after it")
    H.eq(shorten("cd /repos then"), "cd $REPOS_DIR then")
  end)

  H.check("multiple occurrences, mixed case", function()
    local out, n = shorten("E:/repos/gopath.nvim and E:/REPOS/replacer.nvim")
    H.eq(out, "$REPOS_DIR/gopath.nvim and $REPOS_DIR/replacer.nvim")
    H.eq(n, 2, "both rewritten")
  end)

  -- ── the negative cases: what must stay untouched ───────────────────────────

  H.check("'repos' nested deeper than the root is left alone", function()
    local line = [[C:\Users\bartl\AppData\Local\nvim\somefolder\repos\notthis.md]]
    local out, n = shorten(line)
    H.eq(out, line, "unchanged")
    H.eq(n, 0, "no replacement")
  end)

  H.check("a longer word starting with the segment is not truncated", function()
    local line = [[E:\repository\unrelated.md]]
    H.eq(shorten(line), line, "'repository' must not become '$REPOS_DIRitory'")
    H.eq(select(2, shorten(line)), 0)
  end)

  H.check("a bare 'repos' with no marker and no separator is an ordinary word", function()
    local line = "this line has no repos path at all, just words"
    H.eq(shorten(line), line, "unchanged")
  end)

  H.check("nothing path-like at all", function()
    local line = "nothing path-like on this line whatsoever"
    local out, n = shorten(line)
    H.eq(out, line)
    H.eq(n, 0)
  end)

  H.check("an empty line is not an error", function()
    local out, n = shorten("")
    H.eq(out, "")
    H.eq(n, 0)
  end)

  -- ── multiple configured pairs ──────────────────────────────────────────────

  H.check("the longest segment name is tried first", function()
    -- Without the length ordering, "repos" would match inside "repos-archive"
    -- first and shadow the more specific pair.
    local pairs_list = {
      { segment = "repos", var = "REPOS_DIR" },
      { segment = "repos-archive", var = "ARCHIVE_DIR" },
    }
    local out = ES.shorten("E:/repos-archive/old.md", pairs_list)
    H.eq(out, "$ARCHIVE_DIR/old.md", "the specific pair wins")
    H.eq(
      ES.shorten("E:/repos/new.md", pairs_list),
      "$REPOS_DIR/new.md",
      "and the short one still works"
    )
  end)

  H.check("the caller's pair list is not reordered in place", function()
    local pairs_list = {
      { segment = "repos", var = "REPOS_DIR" },
      { segment = "repos-archive", var = "ARCHIVE_DIR" },
    }
    ES.shorten("E:/repos-archive/old.md", pairs_list)
    H.eq(pairs_list[1].segment, "repos", "the caller's table is sorted on a copy")
  end)

  H.check("two different segments in one line", function()
    local pairs_list = {
      { segment = "repos", var = "REPOS_DIR" },
      { segment = "work", var = "WORK_DIR" },
    }
    local out, n = ES.shorten("cp E:/repos/a.md /work/b.md", pairs_list)
    H.eq(out, "cp $REPOS_DIR/a.md $WORK_DIR/b.md")
    H.eq(n, 2)
  end)

  -- ── the buffer-facing entry point ──────────────────────────────────────────

  H.check("shorten_current_line rewrites the line in place and reports the count", function()
    H.config_sandbox(function()
      H.buf({ "first", [[see E:\repos\gopath.nvim\README.md]], "third" })
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local notes = H.capture_notify(function()
        ES.shorten_current_line()
      end)

      local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      H.eq(lines[2], [[see $REPOS_DIR\gopath.nvim\README.md]], "only line 2 changed")
      H.eq(lines[1], "first", "line above untouched")
      H.eq(lines[3], "third", "line below untouched")
      H.match(H.notify_text(notes), "shortened 1 occurrence", "reported in the singular")
    end)
  end)

  H.check("shorten_current_line pluralises correctly", function()
    H.config_sandbox(function()
      H.buf({ "E:/repos/a and C:/repos/b" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local notes = H.capture_notify(function()
        ES.shorten_current_line()
      end)
      H.eq(vim.api.nvim_get_current_line(), "$REPOS_DIR/a and $REPOS_DIR/b")
      H.match(H.notify_text(notes), "shortened 2 occurrences")
    end)
  end)

  H.check("shorten_current_line warns and leaves the line alone when nothing matches", function()
    H.config_sandbox(function()
      H.buf({ "nothing to see here" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local notes = H.capture_notify(function()
        ES.shorten_current_line()
      end)
      H.eq(vim.api.nvim_get_current_line(), "nothing to see here", "unchanged")
      H.match(H.notify_text(notes), "nothing to shorten on this line")
    end)
  end)

  H.check(
    "shorten_current_line warns instead of raising in a non-modifiable buffer (ERR-01)",
    function()
      H.config_sandbox(function()
        H.buf({ "see E:/repos/a.md" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.bo.modifiable = false
        local notes = H.capture_notify(function()
          ES.shorten_current_line()
        end)
        vim.bo.modifiable = true
        H.eq(
          vim.api.nvim_get_current_line(),
          "see E:/repos/a.md",
          "unchanged -- the write never landed"
        )
        H.match(H.notify_text(notes), "not modifiable")
      end)
    end
  )

  H.check("shorten_current_line honours a user-configured shorten_dirs map", function()
    H.config_sandbox(function(c)
      c.setup({ env_variable_resolution = { shorten_dirs = { projects = "PROJ_DIR" } } })
      H.buf({ "/projects/thing/main.go" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      H.capture_notify(function()
        ES.shorten_current_line()
      end)
      H.eq(vim.api.nvim_get_current_line(), "$PROJ_DIR/thing/main.go")
    end)
  end)

  H.check("shorten_current_line falls back to the built-in pair without config", function()
    H.config_sandbox(function(c)
      -- `shorten_dirs` is a map, so the merge replaces individual keys; setting
      -- the whole feature table to a non-table exercises the `or` fallback.
      c.setup({ env_variable_resolution = false })
      H.buf({ "/repos/x.md" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      H.capture_notify(function()
        ES.shorten_current_line()
      end)
      H.eq(vim.api.nvim_get_current_line(), "$REPOS_DIR/x.md", "default pair used")
    end)
  end)
end
