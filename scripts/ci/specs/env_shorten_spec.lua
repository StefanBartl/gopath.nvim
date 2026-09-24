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

  -- ── M.shorten_known / :GopathToNvimDir: literal well-known-dir match ───────

  H.check("shorten_known: a literal absolute path, any case, any separator", function()
    local pairs_list = { { var = "NVIM_CONFIG_DIR", dir = [[C:\Users\bartl\AppData\Local\nvim]] } }
    local out, n = ES.shorten_known(
      [[edit C:/Users/bartl/AppData/Local/NVIM/lua/plugins/personal/init.lua]],
      pairs_list
    )
    H.eq(out, "edit $NVIM_CONFIG_DIR/lua/plugins/personal/init.lua")
    H.eq(n, 1)
  end)

  H.check("shorten_known: unlike shorten_segment, a bare folder name never matches", function()
    -- The whole point of the literal match: "nvim" alone (no full stdpath
    -- prefix before it) must NOT be rewritten -- that would be exactly the
    -- false-positive risk shorten_prefix exists to avoid.
    local pairs_list = { { var = "NVIM_CONFIG_DIR", dir = "/home/x/.config/nvim" } }
    local line = "cd /some/other/nvim/project"
    local out, n = ES.shorten_known(line, pairs_list)
    H.eq(out, line, "unchanged")
    H.eq(n, 0)
  end)

  H.check("shorten_known: a longer directory wins over a shorter one nested in it", function()
    local pairs_list = {
      { var = "NVIM_CONFIG_DIR", dir = "/home/x/.config/nvim" },
      { var = "CONFIG_DIR", dir = "/home/x/.config" },
    }
    H.eq(
      ES.shorten_known("/home/x/.config/nvim/init.lua", pairs_list),
      "$NVIM_CONFIG_DIR/init.lua",
      "the more specific (longer) directory wins"
    )
    H.eq(
      ES.shorten_known("/home/x/.config/other/x", pairs_list),
      "$CONFIG_DIR/other/x",
      "and the shorter one still works outside the nested one"
    )
  end)

  H.check(
    "shorten_current_line_known rewrites the current line using shorten_known_dirs",
    function()
      H.config_sandbox(function(c)
        c.setup({
          env_variable_resolution = {
            shorten_known_dirs = { PROJ_ROOT = "/home/x/work/proj" },
          },
        })
        H.buf({ "see /home/x/work/proj/README.md" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(vim.api.nvim_get_current_line(), "see $PROJ_ROOT/README.md")
        H.match(H.notify_text(notes), "shortened 1 occurrence")
      end)
    end
  )

  H.check("shorten_current_line_known accepts a resolver function, called fresh", function()
    H.config_sandbox(function(c)
      local calls = 0
      c.setup({
        env_variable_resolution = {
          shorten_known_dirs = {
            NVIM_CONFIG_DIR = function()
              calls = calls + 1
              return "/computed/config/dir"
            end,
          },
        },
      })
      H.buf({ "open /computed/config/dir/init.lua" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      H.capture_notify(function()
        ES.shorten_current_line_known()
      end)
      H.eq(vim.api.nvim_get_current_line(), "open $NVIM_CONFIG_DIR/init.lua")
      H.eq(calls, 1, "the resolver ran")
    end)
  end)

  -- These two mock `gopath.config` directly rather than going through
  -- `config_sandbox`/`c.setup()`: `deep_merge_into` merges map fields
  -- key-by-key (see the "shorten_dirs...falls back" test above), so setting
  -- `shorten_known_dirs = {}` through setup() is a no-op that leaves the
  -- default NVIM_CONFIG_DIR entry in place -- there is no way to reach a
  -- genuinely empty map through the public config API, only by replacing
  -- what `gopath.config.get()` itself returns.

  H.check(
    "shorten_current_line_known warns instead of raising when nothing is configured",
    function()
      H.with_modules({
        ["gopath.config"] = {
          get = function()
            return { env_variable_resolution = { shorten_known_dirs = {} } }
          end,
        },
      }, function()
        H.buf({ "anything at all" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(vim.api.nvim_get_current_line(), "anything at all", "unchanged")
        H.match(H.notify_text(notes), "no known directories configured")
      end)
    end
  )

  H.check("shorten_current_line_known ignores a resolver that fails or returns nothing", function()
    H.with_modules({
      ["gopath.config"] = {
        get = function()
          return {
            env_variable_resolution = {
              shorten_known_dirs = {
                BROKEN = function()
                  error("boom")
                end,
                EMPTY = function()
                  return ""
                end,
              },
            },
          }
        end,
      },
    }, function()
      H.buf({ "anything at all" })
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      local notes = H.capture_notify(function()
        ES.shorten_current_line_known()
      end)
      H.eq(vim.api.nvim_get_current_line(), "anything at all", "unchanged")
      H.match(H.notify_text(notes), "no known directories configured")
    end)
  end)

  -- ── Markdown-link relative paths, resolved against the buffer's directory ──

  H.check(
    "shorten_current_line_known: a relative Markdown image link under the known dir is rewritten",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        H.write(dir .. "/docs/ROADMAP/assets/ROADMAP-123.png", { "" })
        local note = H.write(dir .. "/docs/ROADMAP/note.md", {
          "![no symlink because not focused filetree](./assets/ROADMAP-123.png)",
        })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(
          vim.api.nvim_get_current_line(),
          "![no symlink because not focused filetree]($NVIM_CONFIG_DIR/docs/ROADMAP/assets/ROADMAP-123.png)"
        )
        H.match(H.notify_text(notes), "shortened 1 occurrence")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: two Markdown links on one line, both under the known dir",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        local note = H.write(dir .. "/docs/note.md", {
          "see [a](./assets/a.png) and [b](./assets/sub/b.png) here",
        })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        ES.shorten_current_line_known()
        H.eq(
          vim.api.nvim_get_current_line(),
          "see [a]($NVIM_CONFIG_DIR/docs/assets/a.png) and [b]($NVIM_CONFIG_DIR/docs/assets/sub/b.png) here"
        )
      end)
    end
  )

  H.check(
    "shorten_current_line_known: a relative Markdown link that resolves OUTSIDE every known dir is left untouched",
    function()
      H.config_sandbox(function(c)
        -- The known dir and the buffer's own directory are unrelated trees,
        -- so "./assets/x.png" resolves somewhere no configured root covers.
        local known_dir = H.tmpdir()
        local elsewhere = H.tmpdir()
        local note = H.write(elsewhere .. "/docs/note.md", {
          "see [x](./assets/x.png) here",
        })
        c.setup({
          env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = known_dir } },
        })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local line_before = vim.api.nvim_get_current_line()
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(vim.api.nvim_get_current_line(), line_before, "unchanged")
        H.match(H.notify_text(notes), "nothing to shorten")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: the Markdown pass and a literal absolute path on the same line both count",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        local note = H.write(dir .. "/docs/note.md", {
          "[rel](./assets/a.png) and " .. dir:gsub("\\", "/") .. "/README.md",
        })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(
          vim.api.nvim_get_current_line(),
          "[rel]($NVIM_CONFIG_DIR/docs/assets/a.png) and $NVIM_CONFIG_DIR/README.md"
        )
        H.match(H.notify_text(notes), "shortened 2 occurrences")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: a URL inside a Markdown link is NEVER treated as a relative path"
      .. " (regression: used to mangle it when the buffer itself lives under the known dir)",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        -- The bug: joining "https://github.com/foo/bar" to a bufdir that is
        -- itself under the known dir makes the JOINED string start with the
        -- known dir purely because the bufdir does -- nothing to do with the
        -- URL. shorten_prefix then matched that prefix and spliced
        -- "$NVIM_CONFIG_DIR/docs/https:/github.com/foo/bar" into the link.
        local note = H.write(dir .. "/docs/note.md", {
          "see [GitHub](https://github.com/foo/bar) and [rel](./a.png) here",
        })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        ES.shorten_current_line_known()
        H.eq(
          vim.api.nvim_get_current_line(),
          "see [GitHub](https://github.com/foo/bar) and [rel]($NVIM_CONFIG_DIR/docs/a.png) here",
          "the URL survives untouched; the genuine relative link (bufdir is dir/docs) still resolves"
        )
      end)
    end
  )

  H.check(
    "shorten_current_line: same URL guard applies to the structural (repos-dir) flavour",
    function()
      H.config_sandbox(function()
        local root = H.tmpdir():match("^(%a:[/\\])") or "/"
        H.buf(
          { "see [x](https://example.com/repos/thing) here" },
          { name = root .. "repos/note.md" }
        )
        local before = vim.api.nvim_get_current_line()
        local notes = H.capture_notify(function()
          ES.shorten_current_line()
        end)
        H.eq(vim.api.nvim_get_current_line(), before, "unchanged -- the URL is not a relative path")
        H.match(H.notify_text(notes), "nothing to shorten")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: a bare-host (schemeless) Markdown link is also excluded",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        local note = H.write(dir .. "/docs/note.md", { "see [x](github.com/foo/bar) here" })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        local before = vim.api.nvim_get_current_line()
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(vim.api.nvim_get_current_line(), before, "unchanged")
        H.match(H.notify_text(notes), "nothing to shorten")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: a URL directly selected (not in a Markdown link) is also excluded",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        local note = H.write(dir .. "/docs/note.md", { "https://github.com/foo/bar" })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
        vim.api.nvim_buf_set_mark(0, ">", 1, #"https://github.com/foo/bar" - 1, {})

        local notes = H.capture_notify(function()
          ES.shorten_current_line_known({ selection = true })
        end)
        H.eq(vim.api.nvim_get_current_line(), "https://github.com/foo/bar", "unchanged")
        H.match(H.notify_text(notes), "nothing to shorten")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: an unnamed buffer skips relative resolution, no error",
    function()
      H.config_sandbox(function(c)
        c.setup({
          env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = H.tmpdir() } },
        })
        H.buf({ "see [x](./assets/a.png) here" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known()
        end)
        H.eq(vim.api.nvim_get_current_line(), "see [x](./assets/a.png) here", "unchanged")
        H.match(H.notify_text(notes), "nothing to shorten")
      end)
    end
  )

  H.check(
    "shorten_current_line: the structural (repos-dir) flavour gets the same Markdown-relative treatment",
    function()
      H.config_sandbox(function()
        -- "repos" must be root-adjacent for the structural matcher (see the
        -- "nested deeper than the root" case in the segment tests above), so
        -- this fakes the buffer's own name rather than nesting under
        -- H.tmpdir() (always deep inside the OS temp tree). expand("%:p:h")
        -- works from the registered name alone -- the file need not exist.
        -- The root prefix is taken from a REAL tmpdir so it matches
        -- whatever absolute-path convention this platform actually uses
        -- (a Windows drive letter is required for `:p` to treat a bare
        -- leading "/" as already-absolute instead of cwd-relative).
        local root = H.tmpdir():match("^(%a:[/\\])") or "/"
        H.buf({ "see [x](../assets/logo.png) here" }, { name = root .. "repos/proj/docs/note.md" })

        ES.shorten_current_line()
        H.eq(vim.api.nvim_get_current_line(), "see [x]($REPOS_DIR/proj/assets/logo.png) here")
      end)
    end
  )

  -- ── Visual-selection range: shorten just the selected span ─────────────────

  H.check(
    "shorten_current_line_known: a selected literal span is rewritten, the rest is untouched",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        local abs = dir:gsub("\\", "/") .. "/README.md"
        local line = "prefix " .. abs .. " suffix"
        H.buf({ line })
        -- Select just the absolute path span (1-indexed, inclusive).
        local scol, ecol = #"prefix ", #("prefix " .. abs) - 1
        vim.api.nvim_buf_set_mark(0, "<", 1, scol, {})
        vim.api.nvim_buf_set_mark(0, ">", 1, ecol, {})

        ES.shorten_current_line_known({ selection = true })
        H.eq(vim.api.nvim_get_current_line(), "prefix $NVIM_CONFIG_DIR/README.md suffix")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: a selected bare relative path resolves against the buffer dir",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        local note = H.write(dir .. "/docs/note.md", { "prefix ./assets/a.png suffix" })
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        vim.cmd.edit(vim.fn.fnameescape(note))
        local line = vim.api.nvim_get_current_line()
        local scol, ecol = #"prefix ", #"prefix ./assets/a.png" - 1
        vim.api.nvim_buf_set_mark(0, "<", 1, scol, {})
        vim.api.nvim_buf_set_mark(0, ">", 1, ecol, {})
        H.eq(line:sub(scol + 1, ecol + 1), "./assets/a.png", "selection sanity check")

        ES.shorten_current_line_known({ selection = true })
        H.eq(vim.api.nvim_get_current_line(), "prefix $NVIM_CONFIG_DIR/docs/assets/a.png suffix")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: opts.selection with no marks warns instead of erroring",
    function()
      H.config_sandbox(function(c)
        c.setup({
          env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = H.tmpdir() } },
        })
        H.buf({ "nothing selected here" })
        local notes = H.capture_notify(function()
          ES.shorten_current_line_known({ selection = true })
        end)
        H.eq(vim.api.nvim_get_current_line(), "nothing selected here", "unchanged")
        H.match(H.notify_text(notes), "no %(single%-line%) selection")
      end)
    end
  )

  H.check(
    "shorten_current_line_known: opts.selection with a multi-line selection warns, does not fall back to the whole line",
    function()
      H.config_sandbox(function(c)
        local dir = H.tmpdir()
        c.setup({ env_variable_resolution = { shorten_known_dirs = { NVIM_CONFIG_DIR = dir } } })
        local abs = dir:gsub("\\", "/") .. "/README.md"
        H.buf({ abs, "second line" })
        vim.api.nvim_buf_set_mark(0, "<", 1, 0, {})
        vim.api.nvim_buf_set_mark(0, ">", 2, 0, {})

        local notes = H.capture_notify(function()
          ES.shorten_current_line_known({ selection = true })
        end)
        H.eq(
          vim.api.nvim_get_current_line(),
          abs,
          "unchanged -- not silently widened to the whole line"
        )
        H.match(H.notify_text(notes), "no %(single%-line%) selection")
      end)
    end
  )
end
