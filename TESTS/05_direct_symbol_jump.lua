-- TESTS/05_direct_symbol_jump.lua
-- Test direct symbol/definition jumps (LSP / treesitter / identifier_locator)
-- on require() bindings and their subsequent usages.
--
-- HOW TO TEST
-- ===========
-- Place the cursor on the marked (^^^) token in each case below and press gP.

-- ==== Test Case 1: Direct Symbol Jump (LSP) ====

local config = require("gopath.config")
config.setup()
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at line where setup() is defined
-- Source: LSP (confidence 1.0)

-- ==== Test Case 2: Chained Symbol (LSP fallback to Treesitter) ====

local setup = require("gopath.config").setup
--                                     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP if available, treesitter as fallback

-- ==== Test Case 3: Bare Identifier to Module ====

-- File: test.lua
local resolver = require("gopath.resolve")
--    ^^^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/resolve.lua
-- Source: identifier_locator

-- ==== Test Case 4: Variable Usage ====

local config = require("gopath.config")

-- Later in file...
config.get()
--^^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua (not at specific line, module-level)
-- Source: identifier_locator

-- ==== Test Case 5: Function Call on Variable ====

local config = require("gopath.config")
config.setup({ mode = "hybrid" })
--     ^^^^^
-- Cursor here → gP
-- Expected: Opens gopath/config.lua at setup() definition
-- Source: LSP (parses chain correctly)
