---@meta
---@module 'gopath.resolvers.@types'
---@brief Shared type contracts for all language-specific resolvers.
---@description
--- Every resolver under `resolvers/<lang>/` and `resolvers/common/` implements
--- the `Resolver` interface (a single `resolve()` returning `GopathResult|nil`).
--- These aliases document the conventions that the per-language resolvers and
--- the `lang_helper` utilities rely on, so the individual resolver files can
--- stay lean. Per-language folders intentionally share this single types file
--- rather than each carrying a near-identical copy (DRY over literal coverage).

-- #####################################################################
-- common/lang_helper.lua

---@class LangResultOpts
--- Options accepted by `lang_helper.make_result`.
---@field language   string       Filetype label stored on the result
---@field path       string|nil   Absolute resolved path
---@field exists     boolean      Whether `path` was confirmed on disk
---@field kind       string|nil   GopathKind override (defaults to module/file)
---@field line       integer|nil  1-based target line
---@field col        integer|nil  1-based target column
---@field confidence number|nil   Override confidence score (defaults by `exists`)
---@field source     string|nil   GopathSource override (defaults to "builtin")

-- #####################################################################
-- Custom resolvers (config.languages.<ft>.custom_resolvers)

---@alias CustomResolver Resolver|string
--- A user-provided resolver. Either:
---   • a table implementing `resolve(): GopathResult|nil`, or
---   • a string module name that, when required, returns such a table.
--- Custom resolvers run BEFORE the built-in language resolvers for their
--- filetype, so users can override or extend default behaviour.

return {}
