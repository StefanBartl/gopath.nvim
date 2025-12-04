-- Direct symbol definition jump: Testing File
--- direct-symbol-definiton-jump

-- ==== Test Case 1: Direct Symbol Jump (LSP) ====

local config = require("gopath.config")
config.setup()
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at line where setup() is defined
-- Source: LSP (confidence 1.0)
-- Aktuelles Resultat:    Error  15:35:43 notify.error [gopath] File not found: B:\repos\gopath.nvim/config.setup
-- 16:11:36 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:11:36 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:11:36 msg_show.lua_print   GopathDebug   <cfile>: config.setup
-- 16:11:36 msg_show.lua_print   GopathDebug   Chain: config -> setup
-- 16:11:36 msg_show.lua_print   GopathDebug   Binding map size: 3
-- 16:11:36 msg_show.lua_print   GopathDebug   Result:
-- 16:11:36 msg_show.lua_print   GopathDebug     language: lua
-- 16:11:36 msg_show.lua_print   GopathDebug     kind: file
-- 16:11:36 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim/config.setup
-- 16:11:36 msg_show.lua_print   GopathDebug     source: builtin
-- 16:11:36 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 16:11:36 msg_show.lua_print   GopathDebug     exists: false
-- 16:11:36 msg_show.lua_print   GopathDebug     range: nil
-- 16:11:36 msg_show.lua_print   GopathDebug ====================


-- ==== Test Case 2: Chained Symbol (LSP fallback to Treesitter) ====

local setup = require("gopath.config").setup
--                                     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP if available, treesitter as fallback
-- Aktuelles Resultat:    Error  15:37:15 notify.error [gopath] File not found: B:\repos\gopath.nvim/.setup
-- 16:11:11 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:11:11 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:11:11 msg_show.lua_print   GopathDebug   <cfile>: .setup
-- 16:11:11 msg_show.lua_print   GopathDebug   Chain: nil
-- 16:11:11 msg_show.lua_print   GopathDebug   Binding map size: 3
-- 16:11:11 msg_show.lua_print   GopathDebug   Result:
-- 16:11:11 msg_show.lua_print   GopathDebug     language: lua
-- 16:11:11 msg_show.lua_print   GopathDebug     kind: file
-- 16:11:11 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim/.setup
-- 16:11:11 msg_show.lua_print   GopathDebug     source: builtin
-- 16:11:11 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 16:11:11 msg_show.lua_print   GopathDebug     exists: false
-- 16:11:11 msg_show.lua_print   GopathDebug     range: nil
-- 16:11:11 msg_show.lua_print   GopathDebug ====================


-- ==== Test Case 3: Bare Identifier to Module ====

-- File: test.lua
local resolver = require("gopath.resolve")
--    ^^^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/resolve.lua
-- Source: identifier_locator (NEW!)
-- Aktuelles Resultat: öffnet die datei nicht, gibt aber aus:
 -- Debug  16:08:03 notify.debug [gopath] Opening with range: line=25, col=7
 -- Debug  16:08:03 notify.debug [gopath] Normalized range: line=25, col=7
 --   Info  16:08:03 notify.info [gopath] Jumped to line 25, col 6

-- 16:09:01 msg_show.lua_print === Gopath Debug ===
-- 16:09:01 msg_show.lua_print   Filetype: lua
-- 16:09:01 msg_show.lua_print   <cfile>: resolver
-- 16:09:01 msg_show.lua_print   Chain: nil
-- 16:09:01 msg_show.lua_print   Binding map size: 3
-- 16:09:01 msg_show.lua_print   Result:
-- 16:09:01 msg_show.lua_print     language: lua
-- 16:09:01 msg_show.lua_print     kind: module
-- 16:09:01 msg_show.lua_print     path: B:/repos/gopath.nvim/lua/gopath/resolve.lua
-- 16:09:01 msg_show.lua_print     source: treesitter
-- 16:09:01 msg_show.lua_print     confidence: 0.85
-- 16:09:01 msg_show.lua_print     exists: nil
-- 16:09:01 msg_show.lua_print     range: nil
-- 16:09:01 msg_show.lua_print ====================
-- -- ==== Test Case 4: Variable Usage ====

local config = require("gopath.config")

-- Later in file...
config.get()
--^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua (not at specific line, module-level)
-- Source: identifier_locator
-- Aktuelles Resultat:    Error  15:38:05 notify.error [gopath] File not found: B:\repos\gopath.nvim/config.get
-- 16:09:58 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:09:58 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:09:58 msg_show.lua_print   GopathDebug   <cfile>: config.get
-- 16:09:58 msg_show.lua_print   GopathDebug   Chain: config -> get
-- 16:09:58 msg_show.lua_print   GopathDebug   Binding map size: 3
-- 16:09:58 msg_show.lua_print   GopathDebug   Result:
-- 16:09:58 msg_show.lua_print   GopathDebug     language: lua
-- 16:09:58 msg_show.lua_print   GopathDebug     kind: file
-- 16:09:58 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim/config.get
-- 16:09:58 msg_show.lua_print   GopathDebug     source: builtin
-- 16:09:58 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 16:09:58 msg_show.lua_print   GopathDebug     exists: false
-- 16:09:58 msg_show.lua_print   GopathDebug     range: nil
-- 16:09:58 msg_show.lua_print   GopathDebug ====================

-- ==== Test Case 5: Function Call on Variable ====

local config = require("gopath.config")
config.setup({ mode = "hybrid" })
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP (parses chain correctly)
-- Aktuelles Resultat:    Error  15:38:44 notify.error [gopath] File not found: B:\repos\gopath.nvim/config.setup
-- 16:10:37 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:10:37 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:10:37 msg_show.lua_print   GopathDebug   <cfile>: config.setup
-- 16:10:37 msg_show.lua_print   GopathDebug   Chain: config -> setup
-- 16:10:37 msg_show.lua_print   GopathDebug   Binding map size: 3
-- 16:10:37 msg_show.lua_print   GopathDebug   Result:
-- 16:10:37 msg_show.lua_print   GopathDebug     language: lua
-- 16:10:37 msg_show.lua_print   GopathDebug     kind: file
-- 16:10:37 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim/config.setup
-- 16:10:37 msg_show.lua_print   GopathDebug     source: builtin
-- 16:10:37 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 16:10:37 msg_show.lua_print   GopathDebug     exists: false
-- 16:10:37 msg_show.lua_print   GopathDebug     range: nil
-- 16:10:37 msg_show.lua_print   GopathDebug ====================


