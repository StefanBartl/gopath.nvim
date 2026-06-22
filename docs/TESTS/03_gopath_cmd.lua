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

-- ── Tab-completion tests ──────────────────────────────────────────────────────
-- Type each of the following and press <Tab> to verify completion:
--
--   :Gopath <Tab>              → open copy debug probe cache
--   :Gopath open <Tab>         → edit split vsplit tab
--   :Gopath probe <Tab>        → edit split vsplit
--   :Gopath cache <Tab>        → build info add-root
--   :Gopath cache add-root <Tab> → directory completion

-- ── Alias backward-compat ────────────────────────────────────────────────────
--   :GopathOpen vsplit
--   :GopathCopy
--   :GopathDebug
--   :GopathResolve
--   :GopathCacheBuild
--   :GopathCacheInfo
--   :GopathCacheAddRoot ~/repos
