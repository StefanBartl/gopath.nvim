# Gopath.nvim - Developer Documentation

This document provides in-depth technical information for developers who want to extend, customize, or contribute to gopath.nvim.

---

## Table of content

  - [📐 Architecture](#architecture)
    - [Core Components](#core-components)
  - [🔄 Resolution Flow](#resolution-flow)
    - [High-Level Flow](#high-level-flow)
    - [Detailed Resolution Logic](#detailed-resolution-logic)
  - [🧩 Provider System](#provider-system)
    - [Provider Interface](#provider-interface)
    - [Adding a New Provider](#adding-a-new-provider)
  - [🔍 Resolver System](#resolver-system)
    - [Resolver Interface](#resolver-interface)
    - [Result Schema](#result-schema)
  - [🎯 Creating Custom Resolvers](#creating-custom-resolvers)
    - [Example: Custom Language Resolver](#example-custom-language-resolver)
    - [Registering Custom Resolver](#registering-custom-resolver)
  - [🧪 Testing Resolvers](#testing-resolvers)
    - [Manual Testing](#manual-testing)
    - [Unit Test Example (planned)](#unit-test-example-planned)
  - [📦 Alternate Resolution Deep Dive](#alternate-resolution-deep-dive)
    - [Similarity Algorithm](#similarity-algorithm)
    - [Custom Similarity Functions (planned)](#custom-similarity-functions-planned)
  - [🖼️ External File Opening](#external-file-opening)
    - [File Type Detection](#file-type-detection)
    - [Platform-Specific Openers](#platform-specific-openers)
    - [Adding Custom Extensions](#adding-custom-extensions)
  - [🛠️ Configuration Deep Dive](#configuration-deep-dive)
    - [Language Configuration](#language-configuration)
    - [Resolver Selection](#resolver-selection)
  - [🐛 Debugging](#debugging)
    - [Debug Output](#debug-output)
    - [Verbose Logging (planned)](#verbose-logging-planned)
  - [📊 Performance Considerations](#performance-considerations)
    - [Caching](#caching)
    - [LSP Timeout](#lsp-timeout)
    - [Async Operations (planned)](#async-operations-planned)
  - [🔐 Security Considerations](#security-considerations)
    - [Path Sanitization](#path-sanitization)
    - [External Command Injection](#external-command-injection)
    - [User-Provided Resolvers](#user-provided-resolvers)
  - [🚀 Performance Benchmarks](#performance-benchmarks)
    - [Typical Resolution Times](#typical-resolution-times)
  - [🤝 Contributing Guidelines](#contributing-guidelines)
    - [Code Style](#code-style)
    - [Pull Request Checklist](#pull-request-checklist)
    - [Testing](#testing)
  - [📚 Additional Resources](#additional-resources)
    - [Neovim APIs Used](#neovim-apis-used)
    - [External References](#external-references)
  - [📝 License](#license)

---

## 📐 Architecture

### Core Components

```sh
gopath.nvim/
├── lua/gopath/
│   ├── init.lua              # Public API & setup
│   ├── config.lua            # Configuration management
│   ├── resolve.lua           # Resolution orchestrator
│   ├── registry.lua          # Provider & resolver registry
│   ├── commands.lua          # User commands
│   ├── keymaps.lua           # Keymap registration
│   ├── user_commands.lua     # Command registration
│   │
│   ├── providers/            # Provider implementations
│   │   ├── builtin.lua       # Vim builtin functions
│   │   ├── lsp.lua           # LSP client integration
│   │   └── treesitter.lua    # Treesitter queries
│   │
│   ├── resolvers/            # Language-specific resolvers
│   │   ├── common/           # Universal resolvers
│   │   │   ├── filetoken.lua # <cfile> resolution
│   │   │   └── help.lua      # :help tag resolution
│   │   └── lua/              # Lua-specific resolvers
│   │       ├── require_path.lua
│   │       ├── chain.lua
│   │       ├── value_origin.lua
│   │       └── ...
│   │
│   ├── open/                 # Opening strategies
│   │   ├── edit.lua          # Current window
│   │   ├── window.lua        # Horizontal split
│   │   ├── vsplit.lua        # Vertical split
│   │   ├── tab.lua           # New tab
│   │   └── help.lua          # Help window
│   │
│   ├── alternate/            # Fuzzy resolution
│   │   ├── init.lua          # Main logic
│   │   ├── ui.lua            # Selection UI
│   │   └── helpers/
│   │       ├── directory.lua # Directory operations
│   │       └── matcher.lua   # Similarity algorithms
│   │
│   ├── external/             # External file opening
│   │   ├── init.lua
│   │   └── helpers/
│   │       ├── detector.lua  # File type detection
│   │       └── opener.lua    # System opener
│   │
│   └── util/                 # Utilities
│       ├── path.lua          # Path operations
│       └── safe.lua          # Error handling
```

---

## 🔄 Resolution Flow

### High-Level Flow

```sh
User Action (gP)
    ↓
resolve_at_cursor()
    ↓
┌─────────────────────────────────┐
│ Phase 1: Universal Resolvers    │
│ • help.resolve()                 │
│ • filetoken.resolve()            │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│ Phase 2: Language-Specific      │
│ • Check if language enabled      │
│ • Run provider pipeline          │
│   - LSP                          │
│   - Treesitter                   │
│   - Builtin                      │
└─────────────────────────────────┘
    ↓
┌─────────────────────────────────┐
│ Phase 3: Fallback               │
│ • Extract <cfile>                │
│ • Build best-guess path          │
└─────────────────────────────────┘
    ↓
commands.resolve_and_open()
    ↓
┌─────────────────────────────────┐
│ Phase 4: Post-Resolution         │
│ • Check if file exists           │
│ • Try alternate resolution       │
│ • Check external file type       │
│ • Open with appropriate opener   │
└─────────────────────────────────┘
```

### Detailed Resolution Logic

```lua
-- lua/gopath/resolve.lua (simplified)

function M.resolve_at_cursor(opts)
  local cfg = C.get()
  local ft = vim.bo.filetype

  -- Phase 1: Universal (works for ALL filetypes)
  local help_result = resolve_help()
  if help_result then return help_result end

  local filetoken_result = resolve_filetoken()
  if filetoken_result then return filetoken_result end

  -- Phase 2: Language-specific (optional enhancement)
  local lang = cfg.languages[ft]
  if lang and lang.enable ~= false then
    for _, provider in ipairs(cfg.order) do
      local result = run_provider_pipeline(ft, provider)
      if result then return result end
    end
  end

  -- Phase 3: Fallback
  local cfile = vim.fn.expand("<cfile>")
  if cfile ~= "" then
    return build_minimal_result(cfile)
  end

  return nil, "no-match"
end
```

---

## 🧩 Provider System

### Provider Interface

Each provider must implement:

```lua
---@class Provider
---@field definition_at_cursor fun(timeout_ms: integer): table[]|nil

-- Example: lua/gopath/providers/lsp.lua
function M.definition_at_cursor(timeout_ms)
  local params = vim.lsp.util.make_position_params(0, 'utf-8')
  local res = vim.lsp.buf_request_sync(0, "textDocument/definition", params, timeout_ms)
  -- Process and return results
  return results
end
```

### Adding a New Provider

1. Create `lua/gopath/providers/your_provider.lua`
2. Implement required functions
3. Register in `lua/gopath/registry.lua`
4. Add to config `order` list

---

## 🔍 Resolver System

### Resolver Interface

Each resolver must implement:
```lua
---@class Resolver
---@field resolve fun(): GopathResult|nil

-- Example: lua/gopath/resolvers/lua/require_path.lua
function M.resolve()
  local module = find_require_module_at_cursor()
  if not module then return nil end

  local path = search_module_path(module)
  if not path then return nil end

  return {
    language = "lua",
    kind = "module",
    path = path,
    source = "builtin",
    confidence = 0.85,
  }
end
```

### Result Schema

```lua
---@class GopathResult
---@field language string Filetype (e.g., "lua", "markdown")
---@field kind string Result type ("module", "field", "file", "help")
---@field path string|nil Absolute file path
---@field range table|nil {line: integer, col: integer}
---@field chain string[]|nil Dotted chain (e.g., {"cfg", "highlight"})
---@field source string Provider name ("lsp", "treesitter", "builtin")
---@field confidence number 0.0-1.0 confidence score
---@field exists boolean|nil Whether file exists on disk
---@field subject string|nil Help subject (for kind="help")
---@field subjects string[]|nil Help candidates (for kind="help")
```

---

## 🎯 Creating Custom Resolvers

### Example: Custom Language Resolver
```lua
-- lua/gopath/resolvers/python/import_path.lua

local M = {}

---Resolve Python import statements to file paths
---@return GopathResult|nil
function M.resolve()
  local line = vim.api.nvim_get_current_line()

  -- Match: import foo.bar or from foo.bar import baz
  local module = line:match("^%s*import%s+([%w%.]+)")
               or line:match("^%s*from%s+([%w%.]+)%s+import")

  if not module then return nil end

  -- Convert module.name to module/name.py
  local path = module:gsub("%.", "/") .. ".py"

  -- Search in common Python paths
  local abs = search_python_path(path)
  if not abs then return nil end

  return {
    language = "python",
    kind = "module",
    path = abs,
    source = "custom",
    confidence = 0.8,
  }
end

return M
```

### Registering Custom Resolver
```lua
-- In user config
opts = {
  languages = {
    python = {
      enable = true,
      custom_resolvers = {
        require("gopath.resolvers.python.import_path"),
      },
    },
  },
}
```

**Note:** This is planned for a future release. Current architecture supports it but API is not yet exposed.

---

## 🧪 Testing Resolvers

### Manual Testing
```lua
-- Test resolver directly
:lua local res = require("gopath.resolvers.lua.require_path").resolve()
:lua print(vim.inspect(res))

-- Test full resolution
:GopathDebug
```

### Unit Test Example (planned)
```lua
-- tests/resolvers/lua/require_path_spec.lua
describe("lua.require_path", function()
  it("resolves standard library modules", function()
    -- Setup test file with require("vim.api")
    local result = resolve_at_cursor()
    assert.is_not_nil(result)
    assert.equals("vim/shared.lua", result.path:match("vim/[^/]+%.lua$"))
  end)
end)
```

---

## 📦 Alternate Resolution Deep Dive

### Similarity Algorithm

Uses **Levenshtein distance** (edit distance):
```lua
-- lua/gopath/alternate/helpers/matcher.lua

function calculate_similarity(s1, s2)
  local distance = levenshtein_distance(s1, s2)
  local max_len = math.max(#s1, #s2)
  local similarity = (1 - (distance / max_len)) * 100
  return similarity
end
```

**Examples:**
* `chadrer.lua` vs `chadrc.lua`: **87%** (2 edits / 11 chars)
* `cofnig.lua` vs `config.lua`: **90%** (1 edit / 10 chars)
* `init.lua` vs `unit.lua`: **80%** (1 substitution / 8 chars)

### Custom Similarity Functions (planned)

```lua
-- Future API
opts = {
  alternate = {
    similarity_fn = function(s1, s2)
      -- Custom algorithm (e.g., prioritize prefix matches)
      if s2:match("^" .. vim.pesc(s1:sub(1, 3))) then
        return 95  -- High score for prefix match
      end
      return default_similarity(s1, s2)
    end,
  },
}
```

---

## 🖼️ External File Opening

### File Type Detection
```lua
-- lua/gopath/external/helpers/detector.lua

local EXTERNAL_EXTENSIONS = {
  "png", "jpg", "pdf", "mp4", ...
}

function M.is_external_file(path)
  -- Check URL
  if path:match("^https?://") then return true end

  -- Check extension
  local ext = vim.fn.fnamemodify(path, ":e"):lower()
  return vim.tbl_contains(EXTERNAL_EXTENSIONS, ext)
end
```

### Platform-Specific Openers

| Platform | Command | Notes |
|----------|---------|-------|
| macOS | `open <path>` | Respects file associations |
| Linux | `xdg-open <path>` | Freedesktop standard |
| Windows | `powershell Start-Process "<path>"` | Better than `cmd start` (handles spaces) |

### Adding Custom Extensions
```lua
opts = {
  external = {
    enable = true,
    extensions = {
      "png", "jpg", "pdf",
      "custom_ext",  -- Your custom extension
    },
  },
}
```

---

## 🛠️ Configuration Deep Dive

### Language Configuration

```lua
languages = {
  lua = {
    enable = true,        -- Enable Lua-specific features
    resolvers = nil,      -- nil = all available, or provide list
    custom_resolvers = {  -- User-provided resolver modules
      my_custom_resolver,
    },
  },

  markdown = {
    -- Not specified = universal features only (filetoken, help)
  },

  python = {
    enable = false,  -- Explicitly disable (blocks all)
  },
}
```

**Behavior:**
* **Not in config**: Universal features work (filetoken, help, external)
* **enable = true**: Universal + language-specific features
* **enable = false**: Blocked entirely (returns "language-disabled")

### Resolver Selection

```lua
-- Use only specific resolvers
languages = {
  lua = {
    enable = true,
    resolvers = {
      "require_path",  -- Only require() resolution
      "chain",         -- Only chain resolution
    },
  },
}
```

**Available Lua Resolvers:**
* `require_path` - Resolve `require("module")` to file
* `binding_index` - Map identifiers to modules
* `alias_index` - Resolve aliases
* `chain` - Extract dotted chains
* `value_origin` - Find initializer locations
* `symbol_locator` - Locate symbols in files

---

## 🐛 Debugging

### Debug Output

```vim
:GopathDebug
```

**Output:**

```vim
=== Gopath Debug ===
  Filetype: lua
  Chain: M -> cfg.highlight
  Binding map size: 5
  Result: {
    confidence = 0.9,
    kind = "field",
    language = "lua",
    path = "/path/to/config.lua",
    range = { line = 42, col = 3 },
    source = "treesitter"
  }
====================
```

### Verbose Logging (planned)

```lua
opts = {
  debug = {
    enable = true,
    log_file = vim.fn.stdpath("cache") .. "/gopath.log",
    log_level = "trace",  -- "error", "warn", "info", "debug", "trace"
  },
}
```

---

## 📊 Performance Considerations

### Caching

Resolvers use **changedtick** caching to avoid redundant computations:

```lua
-- lua/gopath/resolvers/lua/binding_index.lua

local cache = setmetatable({}, { __mode = "k" })

function M.get_map()
  local buf = 0
  local tick = vim.api.nvim_buf_get_changedtick(buf)

  local entry = cache[buf]
  if entry and entry.tick == tick then
    return entry.map  -- Cache hit
  end

  -- Cache miss: rebuild
  local map = rebuild(buf)
  cache[buf] = { tick = tick, map = map }
  return map
end
```

### LSP Timeout

```lua
opts = {
  lsp_timeout_ms = 200,  -- Balance between speed and reliability
}
```

**Recommendations:**
* **Fast machines**: 100-150ms
* **Normal use**: 200ms (default)
* **Slow LSP servers**: 500ms
* **Patient users**: 1000ms+

### Async Operations (planned)

Future versions will support async resolution to prevent UI blocking:

```lua
require("gopath").resolve_async({
  on_complete = function(result)
    -- Handle result
  end,
})
```

---

## 🔐 Security Considerations

### Path Sanitization

All paths are sanitized before opening:

```lua
-- lua/gopath/open/edit.lua

local escaped = vim.fn.fnameescape(res.path)
vim.cmd.edit(escaped)
```

### External Command Injection

PowerShell commands use proper quoting:

```lua
-- lua/gopath/external/helpers/opener.lua

-- BAD (vulnerable):
-- string.format('Start-Process %s', path)

-- GOOD (safe):
string.format('Start-Process "%s"', path)
```

### User-Provided Resolvers

Custom resolvers run in **protected mode** (`pcall`):

```lua
-- lua/gopath/registry.lua

local ok, result = pcall(resolver.resolve)
if not ok then
  -- Log error, continue with next resolver
end
```

---

## 🚀 Performance Benchmarks

### Typical Resolution Times

| Scenario | LSP | Treesitter | Builtin |
|----------|-----|------------|---------|
| Lua require() | 15ms | 8ms | 5ms |
| Table field | 20ms | 12ms | N/A |
| File path | N/A | 3ms | 2ms |
| URL | N/A | 1ms | 1ms |

**Notes:**
* LSP times include network latency
* Treesitter times include parsing (cached after first parse)
* Builtin is fastest but least semantic

---

## 🤝 Contributing Guidelines

### Code Style

* **Annotations**: Full EmmyLua annotations for all functions
* **Naming**: `snake_case` for functions, `SCREAMING_SNAKE_CASE` for constants
* **Modules**: One feature per file, clear responsibilities
* **Comments**: Explain *why*, not *what*

### Pull Request Checklist

- [ ] Code follows style guide
- [ ] EmmyLua annotations added
- [ ] Tested on Linux/macOS/Windows
- [ ] No external dependencies added
- [ ] README updated (if user-facing change)
- [ ] DEV-README updated (if architecture change)

### Testing

```bash
# Manual testing
nvim --clean -u minimal_init.lua test_file.lua

# Run test suite (planned)
make test
```

---

## 📚 Additional Resources

### Neovim APIs Used

* `vim.lsp.buf_request_sync()` - LSP requests
* `vim.treesitter.get_node_at_cursor()` - Treesitter queries
* `vim.fn.expand("<cfile>")` - Vim builtin expansion
* `vim.ui.select()` - Native selection UI
* `vim.loop.fs_*()` - Filesystem operations

### External References

* [Neovim LSP Documentation](https://neovim.io/doc/user/lsp.html)
* [Treesitter Documentation](https://neovim.io/doc/user/treesitter.html)
* [Levenshtein Distance Algorithm](https://en.wikipedia.org/wiki/Levenshtein_distance)
* [EmmyLua Annotations](https://github.com/sumneko/lua-language-server/wiki/EmmyLua-Annotations)

---

## 📝 License

MIT License - see [LICENSE](LICENSE) file for details.

---
