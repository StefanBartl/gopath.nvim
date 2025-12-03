---@meta
---@module 'gopath.@types.resolvers'

---@class _AliasEntry
---@field kind '"require"'|'"chain"'|'"id"'
---@field module string|nil
---@field chain string|nil
---@field id string|nil

---@class _AliasCache
---@field tick integer
---@field map table<string,_AliasEntry>

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

---@class Resolver
---@field resolve fun(): GopathResult|nil

---@class TSNode        -- minimal Tree-sitter node stub for LuaLS
---@field type fun(self:TSNode):string
---@field parent fun(self:TSNode):TSNode|nil
---@field range fun(self:TSNode):integer,integer,integer,integer

