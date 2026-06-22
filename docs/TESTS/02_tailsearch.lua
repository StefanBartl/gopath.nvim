-- docs/TESTS/02_tailsearch.lua
-- Test the suffix-based filesystem search (tailsearch / pathprobe strategy).
--
-- HOW TO TEST
-- ===========
-- A) Via probe keymap:
--    1. Visual-select a path token (or place cursor on it in normal mode)
--    2. Press <leader>pp
--    Expected: file opens in a vertical split; vim.ui.select if ambiguous.
--
-- B) Via command:
--    :Gopath probe vsplit
--    :GopathProbe         (same, with vsplit)
--    :GopathProbe!        (uses :split instead of :vsplit)
--
-- C) Via gP (goes through the full pipeline including tailsearch fallback):
--    Place cursor on one of the paths below and press gP.

-- ── 1. Truncated path (classic "..." prefix) ──────────────────────────────────
-- Select just the truncated part and press <leader>pp
local _a = "...nvim/lua/gopath/config.lua:42"

-- ── 2. Partial relative path (no ellipsis) ───────────────────────────────────
-- tailsearch still finds it via suffix search
local _b = "gopath/resolvers/common/tailsearch.lua"

-- ── 3. Filename only ─────────────────────────────────────────────────────────
-- Single filename → tailsearch searches all roots for any matching file
local _c = "health.lua"

-- ── 4. Multi-segment tail with line number ───────────────────────────────────
local _d = "resolvers/common/filetoken.lua:88"

-- ── 5. Ambiguous filename (multiple matches expected) ────────────────────────
-- vim.ui.select should appear so you can pick the right one
local _e = "init.lua"

-- ── 6. Path that does not exist anywhere ─────────────────────────────────────
-- Expected: [gopath] probe: no match found …
local _f = "totally/nonexistent/file.lua"

-- ── 7. Visual selection test ──────────────────────────────────────────────────
-- Visual-select exactly "gopath/health.lua" (without quotes) and press <leader>pp
local _g = [[open gopath/health.lua in your editor]]
