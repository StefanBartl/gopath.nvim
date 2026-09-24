-- TESTS/06_env_shorten.lua
-- Test the reverse of env_path resolution, in its two flavours:
--
-- 1. :GopathToReposDir / :Gopath to-repos-dir rewrite an absolute path on
--    the CURRENT LINE whose root segment is a configured directory name
--    (default "repos") back into a `$VAR` reference. Structural, not
--    literal: it does NOT check the actual value of $REPOS_DIR, so it
--    works across any drive letter / OS.
--
-- 2. :GopathToNvimDir / :Gopath to-nvim-dir rewrite LITERAL occurrences of
--    a configured "well-known" directory (default: this Neovim's own
--    vim.fn.stdpath('config')) back into a `$VAR` reference. Unlike (1),
--    no real environment variable needs to be set for the result to
--    resolve again later -- the forward $VAR resolver falls back to
--    calling stdpath('config') itself when the env var is absent.
--
-- HOW TO TEST
-- ===========
-- Cases 1-10 (flavour 1): place the cursor anywhere on one of those lines
-- (it operates on the whole line, not just the token under the cursor) and
-- run :GopathToReposDir.
--
-- Configurable via env_variable_resolution.shorten_dirs (default
-- { repos = "REPOS_DIR" }); toggle the command off via commands.to_repos_dir
-- = false.
--
-- Case 11 (flavour 2): replace the placeholder below with YOUR actual
-- stdpath('config') (run :lua print(vim.fn.stdpath('config')) to see it),
-- place the cursor on that line, and run :GopathToNvimDir. Expected:
-- "edit $NVIM_CONFIG_DIR/lua/plugins/personal/init.lua". Then place the
-- cursor on the resulting line and run gP (or :Gopath open) -- it should
-- open the same file, with no NVIM_CONFIG_DIR environment variable set
-- anywhere.
--
-- Configurable via env_variable_resolution.shorten_known_dirs (default
-- { NVIM_CONFIG_DIR = function() return vim.fn.stdpath('config') end });
-- toggle the command off via commands.to_nvim_dir = false.

-- ── 1. Windows drive, backslash ───────────────────────────────────────────────
-- Expected: "see $REPOS_DIR\gopath.nvim\lua\gopath\env_shorten.lua"
local _a = [[see E:\repos\gopath.nvim\lua\gopath\env_shorten.lua]]

-- ── 2. Different drive letter, forward slash ──────────────────────────────────
-- Expected: "path: $REPOS_DIR/gopath.nvim/README.md" -- the drive letter
-- (C: here vs. E: above) must not matter.
local _b = "path: C:/repos/gopath.nvim/README.md"

-- ── 3. POSIX absolute root ─────────────────────────────────────────────────────
-- Expected: "on Linux: $REPOS_DIR/gopath.nvim/README.md"
local _c = "on Linux: /repos/gopath.nvim/README.md"

-- ── 4. Home-relative ────────────────────────────────────────────────────────────
-- Expected: "or: $REPOS_DIR/gopath.nvim/README.md"
local _d = "or: ~/repos/gopath.nvim/README.md"

-- ── 5. Bare root-relative (no drive/root marker at all) ───────────────────────
-- Expected: "$REPOS_DIR/gopath.nvim/README.md"
local _e = "repos/gopath.nvim/README.md"

-- ── 6. Multiple occurrences, mixed case ("REPOS" vs "repos") ─────────────────
-- Expected both rewritten: "$REPOS_DIR/gopath.nvim and $REPOS_DIR/replacer.nvim"
local _f = "E:/repos/gopath.nvim and E:/REPOS/replacer.nvim"

-- ── 7. NOT a match: "repos" nested deeper than the root ───────────────────────
-- "repos" here is just a subfolder name, not the path root -- must be left
-- untouched (a real repos-root path never has anything before it but the
-- drive/root marker).
local _g = "C:\\Users\\bartl\\AppData\\Local\\nvim\\somefolder\\repos\\notthis.md"

-- ── 8. NOT a match: "repository" must not be truncated to "repos" + "itory" ──
local _h = "E:\\repository\\unrelated.md"

-- ── 9. NOT a match: bare "repos" with no drive/root/`~` marker and no
-- trailing separator is just an ordinary word, not a path reference ─────────
local _i = "this line has no repos path at all, just words"

-- ── 10. No match at all — line left untouched, a warning is shown ────────────
local _j = "nothing path-like on this line whatsoever"

-- ── 11. Flavour 2 — a literal stdpath('config') occurrence ───────────────────
-- Replace this with YOUR real stdpath('config'), then run :GopathToNvimDir
-- on it. Expected: "edit $NVIM_CONFIG_DIR/lua/plugins/personal/init.lua"
local _k = "edit C:/Users/YOU/AppData/Local/nvim/lua/plugins/personal/init.lua"
