---@meta
---@module 'gopath.@types'
---@brief Top-level shared type aliases for gopath.nvim.
---@description
--- Shared aliases and lightweight value types used across the entire plugin.
--- Language-specific resolver types live in their own @types subfolders.
--- The `GopathResult` class and `Resolver` interface live in `@types/resolvers`.

---@alias GopathKind
---| '"module"'   # A Lua/language module (e.g. resolved via require path)
---| '"file"'     # A plain file path (resolved by filetoken or cfile fallback)
---| '"function"' # A function definition
---| '"method"'   # A method on a table/class
---| '"field"'    # A table field
---| '"table"'    # A Lua table / namespace
---| '"primitive"'# A primitive value binding
---| '"help"'     # A Neovim :help subject

---@alias GopathSource
---| '"lsp"'              # Resolved via LSP goto-definition
---| '"treesitter"'       # Resolved via Treesitter semantic analysis
---| '"builtin"'          # Resolved via built-in heuristics / rtp search
---| '"builtin-fallback"' # Last-resort cfile fallback
---| '"regex"'            # Resolved via a pattern match (language-specific)
---| '"static"'           # Statically known (e.g. stdlib mapping)

---@class GopathRange
--- A 1-based cursor position used to jump to a definition after opening.
---@field line integer  1-based line number
---@field col  integer  1-based column number
