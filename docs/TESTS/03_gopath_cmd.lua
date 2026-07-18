-- docs/TESTS/03_gopath_cmd.lua
-- Test the unified :Gopath command and all individual aliases.
--
-- Run these from the command line while cursor is on a relevant symbol / path.

-- ── :Gopath open ─────────────────────────────────────────────────────────────
-- Place cursor on a require() call or file path, then:
--
--   :Gopath open          → opens in current window (edit)
--   :Gopath open split    → opens in horizontal split
--   :Gopath open vsplit   → opens in vertical split
--   :Gopath open tab      → opens in new tab

local example_require = require("gopath.config")  -- cursor on "gopath.config"

-- ── :Gopath copy ─────────────────────────────────────────────────────────────
--   :Gopath copy
-- Expected: "[gopath] copied to clipboard" notification
-- Clipboard: <path>:<line>:<col>

-- ── :Gopath debug ────────────────────────────────────────────────────────────
--   :Gopath debug
--   :GopathDebug
-- Expected: prints resolution chain to :messages

-- ── :Gopath probe ────────────────────────────────────────────────────────────
-- Place cursor on a partial/truncated path or visual-select one, then:
--
--   :Gopath probe           → opens resolved file in vsplit
--   :Gopath probe edit      → opens in current window
--   :Gopath probe split     → opens in horizontal split
--   :GopathProbe            → same as :Gopath probe vsplit
--   :GopathProbe!           → opens in horizontal split

local _path = "resolvers/common/tailsearch.lua:55"  -- cursor here, then :Gopath probe

-- ── :Gopath cache ────────────────────────────────────────────────────────────
--   :Gopath cache info          → show cache statistics
--   :Gopath cache build         → rebuild the filesystem index
--   :Gopath cache add-root ~/   → add home dir to cache roots

-- ── :Gopath check / gC ───────────────────────────────────────────────────────
-- Place cursor on a markdown link / path token, then:
--
--   gC | :Gopath check | :GopathCheck
--
-- Case 1 — path exists:
--   Expected: "[gopath] exists: <path>" info notification, buffer unchanged.
--
-- Case 2 — path does not exist, no existing ancestor dir / no filetree.nvim:
--   Expected: confirm dialog (lib.nvim ui.kit.confirm, or vim.ui.select
--   fallback if lib.nvim is absent) "gopath: '<path>' not found" with
--   choices [Create file] [Cancel].
--     Create file → file (+ parent dirs) created, opened in current window,
--                   cursor jumps to res.range if the resolver produced one.
--     Cancel      → "[gopath] File not created: <path>" warning, nothing opened.
--   This prompt fires even when `create_on_missing.enable = false` in setup()
--   (the opt-out only silences the automatic prompt from gP/g|/g\/g}).
--
-- Case 2b — path does not exist, but an ancestor directory does AND
-- filetree.nvim is installed + set up:
--   Expected: same dialog, but with a third choice [Open in filetree]
--   in between. Selecting it sets cwd to that ancestor directory and
--   roots/focuses filetree.nvim's tree there; nothing is created or opened
--   as a buffer.
--
-- Case 3 — gP/g|/g\/g} on a missing path (create_on_missing.enable = true,
-- the default): same dialog as above, "Create file" opens in the mode of the
-- keymap that triggered it (edit/split/vsplit/tab) instead of always "edit".
-- There is no more automatic "open nearest folder as a buffer" fallback.

local _missing_link = "[missing doc](./docs/DOES-NOT-EXIST.md)"  -- cursor on the path, then gC

-- ── Tab-completion tests ──────────────────────────────────────────────────────
-- Type each of the following and press <Tab> to verify completion:
--
--   :Gopath <Tab>              → open copy debug check probe cache
--   :Gopath open <Tab>         → edit split vsplit tab
--   :Gopath probe <Tab>        → edit split vsplit
--   :Gopath cache <Tab>        → build info add-root
--   :Gopath cache add-root <Tab> → directory completion

-- ── Alias backward-compat ────────────────────────────────────────────────────
--   :GopathOpen vsplit
--   :GopathCopy
--   :GopathDebug
--   :GopathCheck
--   :GopathResolve
--   :GopathCacheBuild
--   :GopathCacheInfo
--   :GopathCacheAddRoot ~/repos
