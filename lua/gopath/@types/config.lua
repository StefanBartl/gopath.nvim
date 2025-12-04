---@meta
---@module 'gopath.@types.config'

---@class GopathKeymaps
---@field open_here string|false Default: "gP"
---@field open_split string|false Default: "g|"
---@field open_vsplit string|false Default: "g\\"
---@field open_tab string|false Default: "g}"
---@field copy_location string|false Default: "gY"
---@field debug string|false Default: "g?"

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
---@field resolvers string[]|nil Default: nil (all available resolvers)
---@field custom_resolvers table[]|nil Custom resolver modules

---@class GopathOptions
---@field mode? "builtin"|"treesitter"|"lsp"|"hybrid" Default: "hybrid"
---@field order? string[] Default: { "treesitter", "lsp", "builtin" }
---@field lsp_timeout_ms? integer Default: 200
---@field languages? table<string, GopathLanguageOptions> Language-specific configuration
---@field alternate? GopathAlternateOptions Fuzzy alternate resolution
---@field external? GopathExternalOptions External file opening
---@field mappings? GopathKeymaps|false Keymaps (false = disable all)
---@field commands? GopathCommands|false User commands (false = disable all)

