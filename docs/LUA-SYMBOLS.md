# Lua Symbol & Require Resolution

> 🇩🇪 Deutsche Version: [LUA-SYMBOLS-DE.md](./LUA-SYMBOLS-DE.md)

This document covers gopath's **Lua-specific** resolvers: turning `require(...)`
calls, bare identifiers that hold a required module, and method/field chains into
the file (and often the exact symbol) they refer to. It is the language layer of
the [Resolution Pipeline](./RESOLUTION.md) (phase 4).

Code: [`lua/gopath/resolvers/lua/`](../lua/gopath/resolvers/lua),
pipeline wiring in [`lua/gopath/registry.lua`](../lua/gopath/registry.lua).

---

## Contents

- [What it resolves](#what-it-resolves)
- [The Lua resolvers](#the-lua-resolvers)
- [Provider pipelines & order](#provider-pipelines--order)
- [Supported patterns](#supported-patterns)
- [Edge cases](#edge-cases)
- [Configuration](#configuration)

---

## What it resolves

```lua
local config = require("gopath.config")   -- cursor on `require`/string → config.lua
--    ^^^^^^                               -- cursor on `config`        → config.lua (identifier_locator)
config.setup()                            -- cursor on `setup`          → the setup definition (symbol_locator)
config.get().value                        -- chain → followed to its source (value_origin / chain)
```

Plain module names like `require("a.b.c")` map to `lua/a/b/c.lua`; identifiers
bound to a require are followed back to that module; and field chains are walked
to the defining symbol.

---

## The Lua resolvers

| Resolver | Role |
|----------|------|
| `require_path` | `require("a.b.c")` → `lua/a/b/c.lua` (path-based, no LSP/TS needed) |
| `chain` | Builds the method/field chain under the cursor (`a.b.c()` → `{a,b,c}`) |
| `binding_index` | Maps file-level identifiers → the module they `require()` |
| `alias_index` | Tracks aliased requires (`local x = require(...)`, then `x.y`) |
| `identifier_locator` | A bare identifier holding a require → opens that module |
| `symbol_locator` | Resolves a chain to the **symbol definition** (via LSP or Treesitter) |
| `value_origin` | Follows a config-table value (`cfg.*` / `M.cfg.*`) to its source |
| `local_to_module` | Rewrites an LSP hit that lands on a `require()` line to the module file |
| `table_locator` | Locates a field within a returned table/module |

---

## Provider pipelines & order

The language layer runs under one of three providers, chosen by `mode`
(`hybrid` tries them in `order`, default `lsp → treesitter → builtin`). Each
pipeline lives in [`registry.lua`](../lua/gopath/registry.lua):

**`lsp`** — `:help` → `symbol_locator.via_lsp` → `require_path`.

**`treesitter`** — `:help` → `value_origin` → build `chain` + `binding_index` →
**`identifier_locator`** → `symbol_locator.via_treesitter` → `require_path`.

**`builtin`** — path-based only: `require_path` (plus the generic `filetoken`,
which `resolve.lua` already runs before the language layer).

> **Order matters:** `identifier_locator` runs **before** `symbol_locator` so a
> bare identifier (`config`) opens its *module*, while a chain (`config.setup`)
> still resolves to the *symbol* via `symbol_locator`.

---

## Supported patterns

```lua
-- ✅ Supported
local config = require("gopath.config")   -- bare identifier → module
local cfg    = require("gopath.config")   -- alias works
config       = require("gopath.config")   -- non-local works
require("gopath.config")                  -- direct require string/call
config.setup()                            -- chain → symbol definition
config.get().value                        -- value origin / chain following

-- ❌ Not supported
local config = require(some_variable)     -- dynamic require (non-literal)
local config = req("gopath.config")       -- aliased require *function*
```

---

## Edge cases

**Scope shadowing.** `identifier_locator` works at file-level binding scope:

```lua
local config = require("gopath.config")   -- outer binding

function test()
  local config = {}                       -- inner, shadows outer
  print(config)                           -- identifier_locator opens the module
  --    ^^^^^^                             -- LSP would point to the inner local
end
```

For precise lexical scope, prefer `lsp` mode (it has priority in `hybrid`).

**Aliased requires** (`local x = require("m"); x.field`) are handled via
`alias_index` + `binding_index`. **Dynamic requires** (non-literal argument)
cannot be resolved statically and fall through to the generic fallbacks.

---

## Configuration

```lua
require("gopath").setup({
  mode  = "hybrid",                       -- or "lsp" | "treesitter" | "builtin"
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,
  languages = {
    lua = {
      enable           = true,
      resolvers        = nil,             -- nil = all; or a whitelist of resolver names
      custom_resolvers = nil,             -- user resolvers, run before built-ins
    },
  },
})
```

Setting `languages.lua.resolvers` to a whitelist (e.g. `{ "require_path" }`)
restricts which Lua resolvers run; `custom_resolvers` injects your own ahead of
the built-ins. See the [Resolution Pipeline](./RESOLUTION.md) for how this layer
sits among the universal resolvers.
