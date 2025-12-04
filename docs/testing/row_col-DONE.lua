-- row-col jump: Testing file
-- /row_col.lua
-- Test in any buffer

-- 1. Simple file path with line number
"lua/gopath/init.lua:15"
-- Expected: Opens init.lua at line 42
-- Resultat:  Debug  15:55:40 notify.debug [gopath] No range provided in result
-- 15:56:21 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 15:56:21 msg_show.lua_print   GopathDebug   Filetype: lua
-- 15:56:21 msg_show.lua_print   GopathDebug   <cfile>: lua/gopath/init.lua
-- 15:56:21 msg_show.lua_print   GopathDebug   Chain: nil
-- 15:56:21 msg_show.lua_print   GopathDebug   Binding map size: 1
-- 15:56:21 msg_show.lua_print   GopathDebug   Result:
-- 15:56:21 msg_show.lua_print   GopathDebug     language: lua
-- 15:56:21 msg_show.lua_print   GopathDebug     kind: module
-- 15:56:21 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim\lua\gopath\init.lua
-- 15:56:21 msg_show.lua_print   GopathDebug     source: builtin
-- 15:56:21 msg_show.lua_print   GopathDebug     confidence: 0.75
-- 15:56:21 msg_show.lua_print   GopathDebug     exists: true
-- 15:56:21 msg_show.lua_print   GopathDebug     range: nil
-- 15:56:21 msg_show.lua_print   GopathDebug ====================

-- 2. File path with line and column
"lua/gopath/config.lua:15:8"
-- Expected: Opens config.lua at line 15, column 8
-- Resultat:  Debug  15:55:47 notify.debug [gopath] No range provided in result
-- 15:59:00 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 15:59:00 msg_show.lua_print   GopathDebug   Filetype: lua
-- 15:59:00 msg_show.lua_print   GopathDebug   <cfile>: lua/gopath/config.lua
-- 15:59:00 msg_show.lua_print   GopathDebug   Chain: nil
-- 15:59:00 msg_show.lua_print   GopathDebug   Binding map size: 1
-- 15:59:00 msg_show.lua_print   GopathDebug   Result:
-- 15:59:00 msg_show.lua_print   GopathDebug     language: lua
-- 15:59:00 msg_show.lua_print   GopathDebug     kind: module
-- 15:59:00 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim\lua\gopath\config.lua
-- 15:59:00 msg_show.lua_print   GopathDebug     source: builtin
-- 15:59:00 msg_show.lua_print   GopathDebug     confidence: 0.75
-- 15:59:00 msg_show.lua_print   GopathDebug     exists: true
-- 15:59:00 msg_show.lua_print   GopathDebug     range: nil
-- 15:59:00 msg_show.lua_print   GopathDebug ====================

-- 3. Error message format
"Error in ...nvim-data/lazy/gopath.nvim/lua/gopath/init.lua:7"
-- Expected: Opens init.lua at line 42
-- Resultat:    Error  15:55:53 notify.error [gopath] File not found: Error
-- 15:59:30 msg_show.lua_print === Gopath Debug ===
-- 15:59:30 msg_show.lua_print   Filetype: lua
-- 15:59:30 msg_show.lua_print   <cfile>: in
-- 15:59:30 msg_show.lua_print   Chain: nil
-- 15:59:30 msg_show.lua_print   Binding map size: 1
-- 15:59:30 msg_show.lua_print   Result:
-- 15:59:30 msg_show.lua_print     language: lua
-- 15:59:30 msg_show.lua_print     kind: file
-- 15:59:30 msg_show.lua_print     path: in
-- 15:59:30 msg_show.lua_print     source: builtin-fallback
-- 15:59:30 msg_show.lua_print     confidence: 0.5
-- 15:59:30 msg_show.lua_print     exists: false
-- 15:59:30 msg_show.lua_print     range: nil
-- 15:59:30 msg_show.lua_print ====================

-- 4. Parenthesis format
"init.lua(42)"
-- Expected: Opens init.lua at line 42
-- Resultat:  Debug  15:55:56 notify.debug [gopath] No range provided in result
-- 15:59:53 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 15:59:53 msg_show.lua_print   GopathDebug   Filetype: lua
-- 15:59:53 msg_show.lua_print   GopathDebug   <cfile>: init.lua
-- 15:59:53 msg_show.lua_print   GopathDebug   Chain: init -> lua
-- 15:59:53 msg_show.lua_print   GopathDebug   Binding map size: 1
-- 15:59:53 msg_show.lua_print   GopathDebug   Result:
-- 15:59:53 msg_show.lua_print   GopathDebug     language: lua
-- 15:59:53 msg_show.lua_print   GopathDebug     kind: module
-- 15:59:53 msg_show.lua_print   GopathDebug     path: C:/Users/Bernhard/AppData/Local/nvim/init.lua
-- 15:59:53 msg_show.lua_print   GopathDebug     source: builtin
-- 15:59:53 msg_show.lua_print   GopathDebug     confidence: 0.75
-- 15:59:53 msg_show.lua_print   GopathDebug     exists: true
-- 15:59:53 msg_show.lua_print   GopathDebug     range: nil
-- 15:59:53 msg_show.lua_print   GopathDebug ====================


-- 5. Vim-style format
"init.lua +42"
-- Expected: Opens init.lua at line 42
-- Resultat:  Debug  15:56:03 notify.debug [gopath] No range provided in result
-- 16:00:10 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:00:10 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:00:10 msg_show.lua_print   GopathDebug   <cfile>: init.lua
-- 16:00:10 msg_show.lua_print   GopathDebug   Chain: init -> lua
-- 16:00:10 msg_show.lua_print   GopathDebug   Binding map size: 1
-- 16:00:10 msg_show.lua_print   GopathDebug   Result:
-- 16:00:10 msg_show.lua_print   GopathDebug     language: lua
-- 16:00:10 msg_show.lua_print   GopathDebug     kind: module
-- 16:00:10 msg_show.lua_print   GopathDebug     path: C:/Users/Bernhard/AppData/Local/nvim/init.lua
-- 16:00:10 msg_show.lua_print   GopathDebug     source: builtin
-- 16:00:10 msg_show.lua_print   GopathDebug     confidence: 0.75
-- 16:00:10 msg_show.lua_print   GopathDebug     exists: true
-- 16:00:10 msg_show.lua_print   GopathDebug     range: nil
-- 16:00:10 msg_show.lua_print   GopathDebug ====================

-- 6. LSP definition (automatic via LSP)
local config = require("gopath.config")
config.setup()
--     ^^^^^
-- Cursor here → gP → Opens config.lua at setup() definition line
-- Resultat:   Error  15:56:10 notify.error [gopath] File not found: B:\repos\gopath.nvim\docs\testing/config.setup
-- 16:00:31 msg_show.lua_print   GopathDebug === Gopath Debug ===
-- 16:00:31 msg_show.lua_print   GopathDebug   Filetype: lua
-- 16:00:31 msg_show.lua_print   GopathDebug   <cfile>: config.setup
-- 16:00:31 msg_show.lua_print   GopathDebug   Chain: config -> setup
-- 16:00:31 msg_show.lua_print   GopathDebug   Binding map size: 1
-- 16:00:31 msg_show.lua_print   GopathDebug   Result:
-- 16:00:31 msg_show.lua_print   GopathDebug     language: lua
-- 16:00:31 msg_show.lua_print   GopathDebug     kind: file
-- 16:00:31 msg_show.lua_print   GopathDebug     path: B:\repos\gopath.nvim\docs\testing/config.setup
-- 16:00:31 msg_show.lua_print   GopathDebug     source: builtin
-- 16:00:31 msg_show.lua_print   GopathDebug     confidence: 0.3
-- 16:00:31 msg_show.lua_print   GopathDebug     exists: false
-- 16:00:31 msg_show.lua_print   GopathDebug     range: nil
-- 16:00:31 msg_show.lua_print   GopathDebug ====================

