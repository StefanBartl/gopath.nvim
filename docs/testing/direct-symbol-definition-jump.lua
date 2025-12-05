-- Direct symbol definition jump: Testing File
--- direct-symbol-definiton-jump

-- ==== Test Case 1: Direct Symbol Jump (LSP) ====

local config = require("gopath.config")
config.setup()
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at line where setup() is defined
-- Source: LSP (confidence 1.0)
-- Aktuelles Resultat: Funktioniert


-- ==== Test Case 2: Chained Symbol (LSP fallback to Treesitter) ==== ONLY NOT DONE YET!

local setup = require("gopath.config").setup
--                                     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP if available, treesitter as fallback
-- Aktuelles Resultat: FIX:   Error  10:54:58 notify.error [gopath] File not found: B:\repos\gopath.nvim/).setup
-- 10:55:05 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 10:55:05 msg_show.lua_print   GopathDebug   Filetype: lua
-- 10:55:05 msg_show.lua_print   GopathDebug   <cfile>: .setup
-- 10:55:05 msg_show.lua_print   GopathDebug   Chain: nil
-- 10:55:05 msg_show.lua_print   GopathDebug   Binding map size: 3
-- 10:55:05 msg_show.lua_print   GopathDebug   Result:
-- 10:55:05 msg_show.lua_print   GopathDebug     language: lua
-- 10:55:05 msg_show.lua_print   GopathDebug     kind: file
-- 10:55:05 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim/).setup
-- 10:55:05 msg_show.lua_print   GopathDebug     source: builtin
-- 10:55:05 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 10:55:05 msg_show.lua_print   GopathDebug     exists: false
-- 10:55:05 msg_show.lua_print   GopathDebug     range: nil
-- 10:55:05 msg_show.lua_print   GopathDebug ====================


-- ==== Test Case 3: Bare Identifier to Module ====

-- File: test.lua
local resolver = require("gopath.resolve")
--    ^^^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/resolve.lua
-- Source: identifier_locator (NEW!)
-- -- Aktuelles Resultat: Funktioniert!

-- -- ==== Test Case 4: Variable Usage ====

config.get()
--^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua (not at specific line, module-level)
-- Source: identifier_locator
-- Aktuelles Resultat:  Funktioniert!


-- ==== Test Case 5: Function Call on Variable ====

config.setup({ mode = "hybrid" })
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP (parses chain correctly)
-- Aktuelles Resultat:  Funktioert perfekt!

