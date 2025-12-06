# Feature 2: Symbol-to-Path Resolution - Implementation

## Table of content

  - [Analyse](#analyse)
  - [Implementation Plan](#implementation-plan)
  - [1. Registry Integration](#1-registry-integration)
    - [Update: `lua/gopath/registry.lua`](#update-luagopathregistrylua)
  - [2. Verbesserter identifier_locator](#2-verbesserter-identifier_locator)
    - [Update: `lua/gopath/resolvers/lua/identifier_locator.lua`](#update-luagopathresolversluaidentifier_locatorlua)
  - [3. Sicherstellen dass binding_index richtig arbeitet](#3-sicherstellen-dass-binding_index-richtig-arbeitet)
    - [Verify: `lua/gopath/resolvers/lua/binding_index.lua`](#verify-luagopathresolversluabinding_indexlua)
  - [4. Testing Suite](#4-testing-suite)
    - [Test File: `tests/feature2_symbol_to_path.lua`](#test-file-testsfeature2_symbol_to_pathlua)
  - [5. Edge Cases Handling](#5-edge-cases-handling)
    - [Edge Case 1: Scope Shadowing](#edge-case-1-scope-shadowing)
    - [Edge Case 2: Aliased Requires](#edge-case-2-aliased-requires)
    - [Edge Case 3: Require mit Ausdruck](#edge-case-3-require-mit-ausdruck)
  - [6. Debug Enhancement](#6-debug-enhancement)
    - [Update: `lua/gopath/commands.lua` (debug output)](#update-luagopathcommandslua-debug-output)
  - [7. Documentation](#7-documentation)
    - [Add to DEV-README.md](#add-to-dev-readmemd)
  - [Feature 2: Symbol-to-Path Resolution](#feature-2-symbol-to-path-resolution)
    - [Overview](#overview)
    - [Architecture](#architecture)
    - [Provider Priority](#provider-priority)
    - [Supported Patterns](#supported-patterns)
    - [Edge Cases](#edge-cases)
    - [Testing](#testing)
  - [Summary](#summary)
    - [Files Modified](#files-modified)
    - [Files Verified (No Changes Needed)](#files-verified-no-changes-needed)
    - [New Files](#new-files)
  - [Expected Behavior](#expected-behavior)

---

## Analyse

**Ziel:** Wenn Cursor auf einem Identifier steht, der ein `require()`-Ergebnis speichert, direkt zum Modul springen.

**Beispiel:**
```lua
local config = require("gopath.config")
--    ^^^^^^
-- Cursor hier → gP → Öffnet lua/gopath/config.lua
```

**Aktueller Stand:**
- `binding_index.lua` mappt bereits `identifier → module`
- `identifier_locator.lua` existiert bereits (wurde in Feature 3 erstellt)
- **Problem:** Wird nicht im Provider-Flow aufgerufen

---

## Implementation Plan

1. **identifier_locator.lua** in Registry integrieren
2. **Verbesserung:** Auch für Methoden-Chains arbeiten
3. **Tests** für alle Szenarien

---

## 1. Registry Integration

### Update: `lua/gopath/registry.lua`

```lua
---@module 'gopath.registry'
---@brief Registers feature resolvers per language and coordinates provider passes.

local C = require("gopath.config")

-- Language resolvers
local RES = {
  lua = {
    require_path       = require("gopath.resolvers.lua.require_path"),
    binding_index      = require("gopath.resolvers.lua.binding_index"),
    alias_index        = require("gopath.resolvers.lua.alias_index"),
    chain              = require("gopath.resolvers.lua.chain"),
    value_origin       = require("gopath.resolvers.lua.value_origin"),
    symbol_locator     = require("gopath.resolvers.lua.symbol_locator"),
    identifier_locator = require("gopath.resolvers.lua.identifier_locator"),
  },
  common = {
    filetoken = require("gopath.resolvers.common.filetoken"),
    help      = require("gopath.resolvers.common.help"),
  },
}

local function has_name(list, name)
  if not list then return true end
  for i = 1, #list do
    if list[i] == name then return true end
  end
  return false
end

local M = {}

---Run the per-language pipeline for one provider pass.
---@param filetype string
---@param provider "lsp"|"treesitter"|"builtin"
---@param opts table|nil
---@return table|nil  -- GopathResult
function M.run_language_pipeline(filetype, provider, opts)
  local cfg = C.get()
  local lang_cfg = cfg.languages[filetype]

  if not (lang_cfg and lang_cfg.enable ~= false) then
    return nil
  end

  local L = RES[filetype]
  if not L then return nil end

  local active = lang_cfg.resolvers

  -- Always try help first
  do
    local hr = RES.common.help.resolve()
    if hr then return hr end
  end

  -- === LSP PROVIDER === (HIGHEST PRECISION)
  if provider == "lsp" then
    -- Symbol locator with LSP precision
    if has_name(active, "symbol_locator") and L.symbol_locator then
      local rr = L.symbol_locator.via_lsp({ timeout_ms = cfg.lsp_timeout_ms })
      if rr then return rr end
    end

    -- Fallback: module resolution
    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end

    return nil
  end

  -- === TREESITTER PROVIDER === (SEMANTIC ANALYSIS)
  if provider == "treesitter" then
    -- 1. Value origin (cfg.* → M.cfg.*)
    if has_name(active, "value_origin") and L.value_origin then
      local vo = L.value_origin.resolve()
      if vo then return vo end
    end

    -- 2. Identifier locator (bare identifier → module)
    -- CRITICAL: Must come BEFORE chain resolution
    if has_name(active, "identifier_locator") and L.identifier_locator then
      local id_result = L.identifier_locator.resolve()
      if id_result then return id_result end
    end

    -- 3. Build context for symbol locator
    local chain = nil
    if has_name(active, "chain") and L.chain then
      chain = L.chain.get_chain_at_cursor()
    end

    local bind = nil
    if has_name(active, "binding_index") and L.binding_index then
      bind = L.binding_index.get_map()
    end

    -- 4. Symbol locator with treesitter fallback
    if has_name(active, "symbol_locator") and L.symbol_locator and chain and bind then
      local rr = L.symbol_locator.via_treesitter(chain, bind)
      if rr then return rr end
    end

    -- 5. Require path resolution
    if has_name(active, "require_path") and L.require_path then
      local rp = L.require_path.resolve()
      if rp then return rp end
    end

    return nil
  end

  -- === BUILTIN PROVIDER === (FALLBACK)
  if provider == "builtin" then
    -- 1. Generic file token
    if has_name(active, "filetoken") then
      local r = RES.common.filetoken.resolve()
      if r then return r end
    end

    -- 2. Require path
    if has_name(active, "require_path") and L.require_path then
      local rr = L.require_path.resolve()
      if rr then return rr end
    end

    return nil
  end

  return nil
end

---For UI/debug.
---@param filetype string
---@return string[]
function M.available_resolvers(filetype)
  local t = RES[filetype] or {}
  local out, i = {}, 0
  for k, _ in pairs(t) do
    i = i + 1
    out[i] = k
  end
  table.sort(out)
  return out
end

return M
```

**Änderungen:**
1. ✅ `identifier_locator` in Treesitter-Pipeline eingefügt
2. ✅ **Vor** Chain-Resolution (wichtig!)
3. ✅ Kommentare zur Priorität

---

## 2. Verbesserter identifier_locator

### Update: `lua/gopath/resolvers/lua/identifier_locator.lua`

```lua
---@module 'gopath.resolvers.lua.identifier_locator'
---@brief Resolve bare identifiers to their module sources.
---Handles: local config = require("gopath.config") → cursor on 'config'

local PATH = require("gopath.util.path")
local TS = require("gopath.providers.treesitter")

local M = {}

---Check if cursor is on a bare identifier (not part of a chain)
---@return string|nil identifier Identifier text or nil
local function get_bare_identifier()
  local node = TS.node_at_cursor()
  if not node then
    return nil
  end

  -- Only match standalone identifiers
  if node:type() ~= "identifier" then
    return nil
  end

  -- Check if parent is a chain (field_expression, dot_index, etc.)
  local parent = node:parent()
  if parent then
    local ptype = parent:type()

    -- Skip if part of a chain (e.g., config.setup)
    if ptype == "field_expression"
      or ptype == "dot_index_expression"
      or ptype == "method_index_expression" then
      return nil
    end

    -- Skip if it's the function name in a call (e.g., setup() where setup is identifier)
    if ptype == "function_call" then
      -- Check if we're the function name, not an argument
      local first_child = parent:child(0)
      if first_child and first_child == node then
        return nil -- This is the function being called, not a variable
      end
    end
  end

  -- Extract identifier text
  local ok, text = pcall(vim.treesitter.get_node_text, node, 0)
  if not ok or not text or text == "" then
    return nil
  end

  return text
end

---Resolve bare identifier to module path
---@return table|nil GopathResult
function M.resolve()
  local identifier = get_bare_identifier()
  if not identifier then
    return nil
  end

  -- Get binding map (identifier → module)
  local bind_index = require("gopath.resolvers.lua.binding_index")
  local bind = bind_index.get_map()

  local mod = bind[identifier]
  if not mod then
    return nil
  end

  -- Resolve module to file path
  local rel = mod:gsub("%.", "/")
  local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" })
           or PATH.search_with_package_path(mod)

  if not abs then
    return nil
  end

  -- Check if file exists
  local exists = PATH.exists(abs)

  return {
    language   = "lua",
    kind       = "module",
    path       = abs,
    range      = nil,  -- No specific location, open module root
    chain      = nil,
    source     = "identifier-locator",
    confidence = 0.85,
    exists     = exists,
  }
end

return M
```

**Verbesserungen:**
1. ✅ Bessere Parent-Checks (keine function_call Namen)
2. ✅ Exists-Flag gesetzt
3. ✅ Klarere Kommentare

---

## 3. Sicherstellen dass binding_index richtig arbeitet

### Verify: `lua/gopath/resolvers/lua/binding_index.lua`

```lua
---@module 'gopath.resolvers.lua.binding_index'
---@brief Map identifiers to modules: local id = require("mod")

local M = {}

---@class _BindingCache
---@field tick integer
---@field map table<string,string>

local cache = setmetatable({}, { __mode = "k" })

local function cur_tick(buf)
  return vim.api.nvim_buf_get_changedtick(buf)
end

---@param buf integer
---@return table<string,string>
local function rebuild(buf)
  local n = vim.api.nvim_buf_line_count(buf)
  local map = {}

  for i = 1, n do
    local s = vim.api.nvim_buf_get_lines(buf, i - 1, i, false)[1] or ""

    -- Pattern 1: local id = require "mod" or require("mod")
    local id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
    if id and mod then
      map[id] = mod
      goto continue
    end

    -- Pattern 2: local id = require [[mod]]
    id, mod = s:match("^%s*local%s+([%w_]+)%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
    if id and mod then
      map[id] = mod
      goto continue
    end

    -- Pattern 3: id = require "mod" (non-local, but allow it)
    id, mod = s:match("^%s*([%w_]+)%s*=%s*require%s*[%(%s]*[\"']([%w%._/%-]+)[\"']")
    if id and mod then
      map[id] = mod
      goto continue
    end

    -- Pattern 4: id = require [[mod]] (non-local)
    id, mod = s:match("^%s*([%w_]+)%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]")
    if id and mod then
      map[id] = mod
      goto continue
    end

    ::continue::
  end

  return map
end

---Get identifier→module map for current buffer with changedtick cache.
---@return table<string,string>
function M.get_map()
  local buf = 0
  local entry = cache[buf]
  local tick = cur_tick(buf)

  if entry and entry.tick == tick then
    return entry.map
  end

  local map = rebuild(buf)
  cache[buf] = { tick = tick, map = map }
  return map
end

return M
```

**Keine Änderungen nötig** - bereits korrekt implementiert!

---

## 4. Testing Suite

### Test File: `tests/feature2_symbol_to_path.lua`

```lua
---@diagnostic disable: unused-local
-- Feature 2: Symbol-to-Path Resolution Tests

-- ==== Test 1: Basic Identifier Resolution ====

local config = require("gopath.config")
--    ^^^^^^
-- Cursor here → gP
-- Expected: Opens lua/gopath/config.lua (module root, no line)
-- Source: identifier_locator
-- Confidence: 0.85


-- ==== Test 2: Multiple Requires ====

local resolve = require("gopath.resolve")
local commands = require("gopath.commands")
local registry = require("gopath.registry")

-- Cursor on 'resolve' → Opens lua/gopath/resolve.lua
-- Cursor on 'commands' → Opens lua/gopath/commands.lua
-- Cursor on 'registry' → Opens lua/gopath/registry.lua


-- ==== Test 3: Identifier in Expression ====

local config = require("gopath.config")
local mode = config.get().mode
--           ^^^^^^
-- Cursor on first 'config' → Opens lua/gopath/config.lua
-- (Not on 'get', that would be chain resolution)


-- ==== Test 4: Identifier as Function Argument ====

local config = require("gopath.config")

local function test(cfg)
  return cfg.mode
end

test(config)
--   ^^^^^^
-- Cursor on 'config' → Opens lua/gopath/config.lua


-- ==== Test 5: Identifier in Conditional ====

local config = require("gopath.config")

if config then
-- ^^^^^^
-- Cursor on 'config' → Opens lua/gopath/config.lua
  print("Config loaded")
end


-- ==== Test 6: Shadowed Identifier (should not resolve) ====

local config = require("gopath.config")

local function test()
  local config = { custom = true }  -- Shadows outer config
  --    ^^^^^^
  -- Cursor here → Should NOT open module (local override)
  -- Expected: No resolution or jump to local definition
end


-- ==== Test 7: Non-Module Identifier (should not resolve) ====

local some_var = "not a module"
--    ^^^^^^^^
-- Cursor here → Should NOT resolve (not bound to require)
-- Expected: No resolution


-- ==== Test 8: Chained Access (should NOT use identifier_locator) ====

local config = require("gopath.config")

config.setup()
--     ^^^^^
-- Cursor on 'setup' → Should use symbol_locator, not identifier_locator
-- Expected: Opens lua/gopath/config.lua at setup() definition line


-- ==== Test 9: Method Call (should NOT use identifier_locator) ====

local config = require("gopath.config")

config.get()
--     ^^^
-- Cursor on 'get' → Should use symbol_locator
-- Expected: Opens lua/gopath/config.lua at get() definition line


-- ==== Test 10: Identifier in Return Statement ====

local function get_config()
  local config = require("gopath.config")
  return config
  --     ^^^^^^
  -- Cursor here → Opens lua/gopath/config.lua
end
```

---

## 5. Edge Cases Handling

### Edge Case 1: Scope Shadowing

**Problem:** Lokale Variable überschreibt äußere:
```lua
local config = require("gopath.config")  -- Line 1

function test()
  local config = {}  -- Line 4, shadows outer
  print(config)      -- Should refer to line 4, not line 1
end
```

**Lösung:** `binding_index` arbeitet File-Level, kann Scopes nicht unterscheiden. LSP würde hier richtig zur lokalen Variable springen.

**Akzeptables Verhalten:** identifier_locator öffnet Modul, LSP (wenn verfügbar) wäre präziser.

---

### Edge Case 2: Aliased Requires

**Problem:**
```lua
local cfg = require("gopath.config")
--    ^^^
-- binding_index mappt: cfg → "gopath.config"
-- Works! ✓
```

**Status:** Bereits unterstützt!

---

### Edge Case 3: Require mit Ausdruck

**Problem:**
```lua
local mod_name = "gopath.config"
local config = require(mod_name)  -- Dynamic require
--    ^^^^^^
```

**Status:** Wird **nicht** unterstützt (Pattern matcht nur String-Literale). Akzeptabel, da dynamische requires selten sind.

---

## 6. Debug Enhancement

### Update: `lua/gopath/commands.lua` (debug output)

```lua
function M.debug_under_cursor()
  local chain = nil
  pcall(function()
    chain = require("gopath.resolvers.lua.chain").get_chain_at_cursor()
  end)

  local bind_sz = 0
  local bind_map = {}
  pcall(function()
    bind_map = require("gopath.resolvers.lua.binding_index").get_map()
    for _ in pairs(bind_map) do bind_sz = bind_sz + 1 end
  end)

  local cfile = vim.fn.expand("<cfile>")

  -- Check identifier_locator
  local identifier = nil
  pcall(function()
    local id_loc = require("gopath.resolvers.lua.identifier_locator")
    -- Access internal function for debugging
    local TS = require("gopath.providers.treesitter")
    local node = TS.node_at_cursor()
    if node and node:type() == "identifier" then
      identifier = vim.treesitter.get_node_text(node, 0)
    end
  end)

  local res, err = RESOLVE.resolve_at_cursor({})

  print("=== Gopath Debug ===")
  print("  Filetype:", vim.bo.filetype)
  print("  <cfile>:", cfile)
  print("  Identifier:", identifier or "nil")
  print("  Chain:", chain and (chain.base .. " -> " .. table.concat(chain.chain, ".")) or "nil")
  print("  Binding map size:", bind_sz)

  -- Show sample bindings
  if bind_sz > 0 then
    print("  Bindings:")
    local count = 0
    for id, mod in pairs(bind_map) do
      print(string.format("    %s → %s", id, mod))
      count = count + 1
      if count >= 3 then break end -- Show max 3
    end
  end

  if res then
    print("  Result:")
    print("    language:", res.language)
    print("    kind:", res.kind)
    print("    path:", res.path)
    print("    source:", res.source)
    print("    confidence:", res.confidence)
    print("    exists:", tostring(res.exists))

    if res.range then
      print("    range:")
      print("      line:", res.range.line)
      print("      col:", res.range.col)
    else
      print("    range: nil")
    end
  else
    print("  Result: nil")
    print("  Error:", err or "unknown")
  end
  print("====================")
end
```

---

## 7. Documentation

### Add to DEV-README.md

```markdown
## Feature 2: Symbol-to-Path Resolution

### Overview

Resolves bare identifiers that store `require()` results directly to their module files.

### Architecture

```
Cursor on: local config = require("gopath.config")
                 ^^^^^^
         ↓
Treesitter: Detect identifier node
         ↓
Check parent: Not part of chain (field_expression)
         ↓
binding_index: Lookup "config" → "gopath.config"
         ↓
identifier_locator: Resolve module → lua/gopath/config.lua
         ↓
Open: gopath/config.lua (no specific line)
```

### Provider Priority

In Treesitter pipeline:
1. **value_origin** (cfg.* → M.cfg.*)
2. **identifier_locator** (bare identifier → module) ← NEW!
3. **symbol_locator** (chain → symbol definition)

**Critical:** identifier_locator must run BEFORE symbol_locator to catch bare identifiers.

### Supported Patterns

```lua
-- ✅ Supported
local config = require("gopath.config")
local cfg = require("gopath.config")  -- Alias works
config = require("gopath.config")     -- Non-local works

-- ❌ Not Supported
local config = require(variable)      -- Dynamic require
local config = req("gopath.config")   -- Aliased require function
```

### Edge Cases

**Scope Shadowing:**
```lua
local config = require("gopath.config")  -- Outer

function test()
  local config = {}  -- Inner, shadows outer
  print(config)      -- identifier_locator opens module (file-level binding)
  --    ^^^^^^        -- LSP would correctly point to inner scope
end
```

**Behavior:** identifier_locator works at file-level scope. For precise scope handling, LSP is preferred (higher priority).

### Testing

Run test suite:
```vim
:edit tests/feature2_symbol_to_path.lua
" Navigate to each test case, press gP
```

Expected results: All bare identifiers resolve to their modules without line numbers.

---

## Summary

### Files Modified

1. ✅ `lua/gopath/registry.lua` - Added identifier_locator to pipeline
2. ✅ `lua/gopath/resolvers/lua/identifier_locator.lua` - Enhanced with exists flag
3. ✅ `lua/gopath/commands.lua` - Enhanced debug output

### Files Verified (No Changes Needed)

1. ✅ `lua/gopath/resolvers/lua/binding_index.lua` - Already correct

### New Files

1. ✅ `tests/feature2_symbol_to_path.lua` - Comprehensive test suite

---

## Expected Behavior

```lua
local config = require("gopath.config")
--    ^^^^^^
-- Before: Nothing or LSP jump to variable definition
-- After: Opens lua/gopath/config.lua ✓

config.setup()
--     ^^^^^
-- Before: Works (symbol_locator)
-- After: Still works (symbol_locator has priority for chains) ✓
```

---

