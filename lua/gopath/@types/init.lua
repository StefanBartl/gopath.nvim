---@meta
---@module 'gopath.@types'

-- FIX: Diese beiden noch implementieren

---@alias GopathKind "module"|"function"|"method"|"field"|"table"|"primitive"
---@alias GopathSource "lsp"|"treesitter"|"builtin"|"regex"|"static"

---@class GopathRange
---@field line integer  -- 1-based
---@field col integer   -- 1-based

