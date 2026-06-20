---@meta
---@module 'gopath.@types.resolvers'
---@brief Type definitions for the resolver pipeline contracts.
---@description
--- Defines `GopathResult` (the canonical output of every resolver),
--- `Resolver` (the interface each resolver module must implement) and
--- `GopathResolveOpts` (the options accepted by `resolve.resolve_at_cursor`).
--- Treesitter node stub `TSNode` is also kept here for LSP convenience.

---@class GopathResult
--- Canonical output produced by every resolver and consumed by openers.
---@field kind       GopathKind   What was resolved (module, file, help, …)
---@field path       string|nil   Absolute file path; nil only for "help" results
---@field subject    string|nil   Help subject string (only for kind = "help")
---@field language   string       Filetype of the buffer where resolution occurred
---@field range      GopathRange|nil  Target cursor position inside the opened file; nil = top of file
---@field chain      string[]|nil Dotted access chain if resolution followed a member chain
---@field source     GopathSource Which resolver produced the result
---@field confidence number
--- Heuristic quality score in the range [0, 1].
--- Guidelines: 1.0 = definitive (LSP); 0.85 = strong heuristic (require path found on rtp);
--- 0.75 = likely correct (filetoken found on &path); 0.5 = uncertain (cfile fallback);
--- 0.3 = low-confidence guess (non-existing path). Used to break ties when multiple
--- resolvers succeed; the result with the highest confidence wins.
---@field exists     boolean      True when the file at `path` was confirmed to exist on disk

---@class Resolver
--- Interface every language-specific resolver module must satisfy.
---@field resolve fun(): GopathResult|nil

---@class GopathResolveOpts
--- Options accepted by `resolve.resolve_at_cursor`.
---@field order      string[]|nil  Override provider order for this call ({"lsp","treesitter","builtin"})
---@field timeout_ms integer|nil   LSP request timeout in milliseconds; falls back to config value

---@class _AliasEntry
---@field kind   '"require"'|'"chain"'|'"id"'
---@field module string|nil
---@field chain  string|nil
---@field id     string|nil

---@class _AliasCache
---@field tick integer
---@field map  table<string,_AliasEntry>

---@class TSNode  Minimal Tree-sitter node stub for LuaLS
---@field type   fun(self:TSNode):string
---@field parent fun(self:TSNode):TSNode|nil
---@field range  fun(self:TSNode):integer,integer,integer,integer
