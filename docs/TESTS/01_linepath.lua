-- docs/TESTS/01_linepath.lua
-- Test the whole-line path extraction (linepath / pathfinder strategy).
--
-- HOW TO TEST
-- ===========
-- Place the cursor anywhere on one of the test lines below and press gP.
-- Expected: Neovim opens the resolved file at the correct line/column.
-- If the cursor is NOT on the path segment itself (e.g. you're on the word
-- "Error") linepath should still find the path from the full line content.
--
-- You can also run:  :Gopath debug   to see what resolution was used.

-- ── 1. Stacktrace-style  (path:line:col) ─────────────────────────────────────
-- Put cursor anywhere on the line — linepath uses the WHOLE line.
-- Expected: open init.lua at line 14, col 3 (or nearest)
local _a = "Error in C:/Users/bartl/AppData/Local/nvim/init.lua:14:3 unexpected token"

-- ── 2. Stacktrace-style  (path:line only) ────────────────────────────────────
local _b = "  at lua/gopath/resolve.lua:42 in function 'resolve_at_cursor'"

-- ── 3. Extension-driven expansion ────────────────────────────────────────────
-- The extractor finds ".lua" in the line and expands around it.
local _c = "see lua/gopath/config.lua for all defaults"

-- ── 4. Absolute path (Windows) ───────────────────────────────────────────────
local _d = "loaded from C:\\Users\\bartl\\AppData\\Local\\nvim\\lua\\custom\\pathprobe\\init.lua"

-- ── 5. Absolute path (unix style) ────────────────────────────────────────────
local _e = "module '/usr/share/nvim/runtime/lua/vim/lsp.lua' not found"

-- ── 6. Relative path with extension ──────────────────────────────────────────
local _f = "require path: lua/gopath/resolvers/common/tailsearch.lua"

-- ── 7. No path — should NOT open anything ────────────────────────────────────
local _g = "this line has no file path at all, just words"
