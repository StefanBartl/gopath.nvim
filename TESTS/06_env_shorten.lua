-- TESTS/06_env_shorten.lua
-- Test the reverse of env_path resolution: :GopathToReposDir /
-- :Gopath to-repos-dir rewrite an absolute path on the CURRENT LINE whose
-- root segment is a configured directory name (default "repos") back into
-- a `$VAR` reference. Structural, not literal: it does NOT check the actual
-- value of $REPOS_DIR, so it works across any drive letter / OS.
--
-- HOW TO TEST
-- ===========
-- Place the cursor anywhere on one of the lines below (it operates on the
-- whole line, not just the token under the cursor) and run :GopathToReposDir.
--
-- Configurable via env_variable_resolution.shorten_dirs (default
-- { repos = "REPOS_DIR" }); toggle the command off via commands.to_repos_dir
-- = false.

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
