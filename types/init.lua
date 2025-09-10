---@module 'gopath.types'
---@brief Common types for annotations.

---@alias GopathKind "module"|"function"|"method"|"field"|"table"|"primitive"
---@alias GopathSource "lsp"|"treesitter"|"builtin"|"regex"|"static"

---@class GopathRange
---@field line integer  -- 1-based
---@field col integer   -- 1-based

---@class GopathResult
---@field language string
---@field kind GopathKind
---@field path string
---@field range GopathRange|nil
---@field chain string[]|nil
---@field source GopathSource
---@field confidence number

---@class GopathLanguageCfg
---@field enable boolean
---@field resolvers string[]|nil

---@class GopathOptions
---@field mode "builtin"|"treesitter"|"lsp"|"hybrid"
---@field order string[]
---@field lsp_timeout_ms integer
---@field languages table<string, GopathLanguageCfg>
