---@meta
---@module 'gopath.@types.config'

---@class GopathKeymaps
---@field open_here string|string[]|false Default: "gP"
---@field open_split string|string[]|false Default: "g|"
---@field open_vsplit string|string[]|false Default: "g\\"
---@field open_tab string|string[]|false Default: "g}"
---@field copy_location string|string[]|false Default: "gY"
---@field debug string|string[]|false Default: "g?"

---@class GopathCommands
---@field resolve boolean Default: true (creates :GopathResolve)
---@field open boolean Default: true (creates :GopathOpen)
---@field copy boolean Default: true (creates :GopathCopy)
---@field debug boolean Default: true (creates :GopathDebug)

---@class GopathAlternateOptions
---@field enable boolean Default: true
---@field similarity_threshold number Default: 75 (0-100)

---@class GopathExternalOptions
---@field enable boolean Default: true
---@field extensions string[]|nil Default: nil (uses built-in list)

---@class GopathLanguageOptions
---@field enable boolean Default: true
---@field resolvers string[]|nil Default: nil (all available resolvers). Whitelist of resolver names to run for this filetype.
---@field custom_resolvers CustomResolver[]|nil
--- User-supplied resolvers run BEFORE the built-in ones for this filetype.
--- Each entry is either a table implementing `resolve(): GopathResult|nil`
--- or a string module name that returns such a table when required.

---@class GopathTruncated
---@field enable boolean Default: true
---@field use_cache boolean
---@field cache_refresh_interval number Refresh every 10 minutes
---@field max_cache_age number Consider cache stale after 1 hour
---@field live_search_fallback boolean Use fd/rg/find if cache misses
---@field similarity_threshold number For multiple match selection
---@field cache_roots table|nil
---@field max_depth number Maximum directory depth to scan
---@field excluded_dirs string[]|nil Directories to skip
---@field watch_patterns string[]|nil
---@field auto_rebuild_on_save boolean

---@class GopathOptions
---@field dev_mode boolean # Print debug notifies
---@field mode? "builtin"|"treesitter"|"lsp"|"hybrid" Default: "hybrid"
---@field order? string[] Default: { "treesitter", "lsp", "builtin" }
---@field lsp_timeout_ms? integer Default: 200
---@field languages? table<string, GopathLanguageOptions> Language-specific configuration
---@field alternate? GopathAlternateOptions Fuzzy alternate resolution
---@field external? GopathExternalOptions External file opening
---@field mappings? GopathKeymaps|false Keymaps (false = disable all)
---@field commands? GopathCommands|false User commands (false = disable all)
---@field truncated GopathTruncated
