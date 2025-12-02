---@module 'gopath.types'
---@brief Common types for annotations.

---@alias GopathKind "module"|"function"|"method"|"field"|"table"|"primitive"
---@alias GopathSource "lsp"|"treesitter"|"builtin"|"regex"|"static"

---@class GopathRange
---@field line integer  -- 1-based
---@field col integer   -- 1-based

---@class GopathResult
---@field kind string
---@field path string|nil
---@field subject string|nil
---@field language string
---@field range {line:integer,col:integer}|nil
---@field chain string[]|nil
---@field source string
---@field confidence number
---@field exists boolean

---@class GopathLanguageCfg
---@field enable boolean
---@field resolvers string[]|nil

---@class GopathOptions
---@field mode "builtin"|"treesitter"|"lsp"|"hybrid"
---@field order string[]
---@field lsp_timeout_ms integer
---@field languages table<string, GopathLanguageCfg>
---@field alternate table --FIX

---@class _AliasEntry
---@field kind '"require"'|'"chain"'|'"id"'
---@field module string|nil
---@field chain string|nil
---@field id string|nil

---@class _AliasCache
---@field tick integer
---@field map table<string,_AliasEntry>

---@class TSNode        -- minimal Tree-sitter node stub for LuaLS
---@field type fun(self:TSNode):string
---@field parent fun(self:TSNode):TSNode|nil
---@field range fun(self:TSNode):integer,integer,integer,integer

