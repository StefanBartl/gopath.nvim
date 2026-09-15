-- TESTS/06_env_shorten.lua
-- Test the reverse of env_path resolution: :GopathToReposDir /
-- :Gopath to-repos-dir rewrite an absolute directory prefix on the CURRENT
-- LINE back into a `$VAR` reference.
--
-- HOW TO TEST
-- ===========
-- Place the cursor anywhere on one of the lines below (it operates on the
-- whole line, not just the token under the cursor) and run :GopathToReposDir.
-- Requires $REPOS_DIR to be set in the environment (see gopath's own
-- resolvers/common/env_path.lua, which does the opposite direction).
--
-- Configurable via env_variable_resolution.shorten_vars (default
-- { "REPOS_DIR" }); toggle the command off via commands.to_repos_dir = false.

-- ── 1. Backslash form ────────────────────────────────────────────────────────
-- Expected: "see $REPOS_DIR\gopath.nvim\lua\gopath\env_shorten.lua"
local _a = [[see E:\repos\gopath.nvim\lua\gopath\env_shorten.lua]]

-- ── 2. Forward-slash form ─────────────────────────────────────────────────────
-- Expected: "path: $REPOS_DIR/gopath.nvim/README.md"
local _b = "path: E:/repos/gopath.nvim/README.md"

-- ── 3. Multiple occurrences, mixed case ("REPOS" vs "repos") ─────────────────
-- Expected both rewritten: "$REPOS_DIR/gopath.nvim and $REPOS_DIR/replacer.nvim"
local _c = "E:/repos/gopath.nvim and E:/REPOS/replacer.nvim"

-- ── 4. No match — line left untouched, a warning is shown ────────────────────
local _d = "this line has no repos path at all, just words"
