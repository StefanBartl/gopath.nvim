# Lua-Symbol- & Require-Auflösung

> 🇬🇧 English version: [LUA-SYMBOLS.md](./LUA-SYMBOLS.md)

Dieses Dokument behandelt gopaths **Lua-spezifische** Resolver: `require(...)`-
Aufrufe, bloße Identifier, die ein required Modul halten, sowie Methoden-/Feld-
Ketten in die Datei (und oft das exakte Symbol) zu übersetzen, auf die sie sich
beziehen. Es ist die Sprach-Ebene der
[Auflösungs-Pipeline](./RESOLUTION-DE.md) (Phase 4).

Code: [`lua/gopath/resolvers/lua/`](../lua/gopath/resolvers/lua),
Pipeline-Verdrahtung in [`lua/gopath/registry.lua`](../lua/gopath/registry.lua).

---

## Inhalt

- [Was aufgelöst wird](#was-aufgelöst-wird)
- [Die Lua-Resolver](#die-lua-resolver)
- [Provider-Pipelines & Reihenfolge](#provider-pipelines--reihenfolge)
- [Unterstützte Muster](#unterstützte-muster)
- [Edge Cases](#edge-cases)
- [Konfiguration](#konfiguration)

---

## Was aufgelöst wird

```lua
local config = require("gopath.config")   -- Cursor auf `require`/String → config.lua
--    ^^^^^^                               -- Cursor auf `config`         → config.lua (identifier_locator)
config.setup()                            -- Cursor auf `setup`           → die setup-Definition (symbol_locator)
config.get().value                        -- Kette → bis zur Quelle verfolgt (value_origin / chain)
```

Reine Modulnamen wie `require("a.b.c")` werden zu `lua/a/b/c.lua`; an ein require
gebundene Identifier werden zum Modul zurückverfolgt; und Feldketten werden bis
zum definierenden Symbol durchlaufen.

---

## Wo Modulnamen gesucht werden

Alle Lua-Resolver teilen sich eine Suchkette, `path.search_module`:

| # | Schritt | Findet |
|---|---------|--------|
| 1 | `runtimepath` | Module geladener Plugins und der eigenen Config |
| 2 | `package.path` | luarocks und alles andere auf dem Lua-Pfad |
| 3 | **`lua/`-Bäume installierter Plugins** | Plugins, die der Manager kennt, aber **noch nicht geladen** hat |

Schritt 3 ist der entscheidende:

```lua
require("open_nvim.integrations.urlview").setup()
--      ^ gF löst hier auf, obwohl open.nvim lazy über `cmd = "Open"` geladen wird
```

Ein installiertes, aber noch nicht geladenes Plugin liegt weder im runtimepath
noch in `package.path` — Schritt 1 und 2 greifen also beide daneben. Schritt 3
liest die Plugin-Verzeichnisse direkt vom Manager: [lazy.nvim]
(`lazy.core.config`) und Neovims eingebautes `vim.pack` werden unterstützt; ein
fehlender oder umgebauter Manager führt zu "keine zusätzlichen Treffer" statt zu
einem Fehler.

Der Schritt läuft bewusst **zuletzt**: ein tatsächlich geladenes Modul gewinnt
immer gegen ein nur installiertes. Das `lua/`-Verzeichnis jedes Plugins wird
einmalig nach Top-Level-Modulnamen indiziert — ein gepunktetes Token, das gar
kein Modul ist (der Normalfall), kostet damit einen Hash-Lookup statt eines
Dateisystem-Zugriffs pro Plugin.

[lazy.nvim]: https://github.com/folke/lazy.nvim

---

## Die Lua-Resolver

| Resolver | Rolle |
|----------|-------|
| `require_path` | `require("a.b.c")` → `lua/a/b/c.lua` (pfadbasiert, ohne LSP/TS) |
| `chain` | Baut die Methoden-/Feldkette unter dem Cursor (`a.b.c()` → `{a,b,c}`) |
| `binding_index` | Mappt datei-globale Identifier → das von ihnen `require()`-te Modul |
| `alias_index` | Verfolgt aliasierte requires (`local x = require(...)`, dann `x.y`) |
| `identifier_locator` | Bloßer Identifier, der ein require hält → öffnet dieses Modul |
| `symbol_locator` | Löst eine Kette zur **Symbol-Definition** auf (via LSP oder Treesitter) |
| `value_origin` | Verfolgt einen Config-Tabellen-Wert (`cfg.*` / `M.cfg.*`) zur Quelle |
| `local_to_module` | Schreibt einen LSP-Treffer auf einer `require()`-Zeile zur Moduldatei um |
| `table_locator` | Lokalisiert ein Feld innerhalb einer zurückgegebenen Tabelle/eines Moduls |

---

## Provider-Pipelines & Reihenfolge

Die Sprach-Ebene läuft unter einem von drei Providern, gewählt über `mode`
(`hybrid` probiert sie in `order`, Default `lsp → treesitter → builtin`). Jede
Pipeline liegt in [`registry.lua`](../lua/gopath/registry.lua):

**`lsp`** — `:help` → `symbol_locator.via_lsp` → `require_path`.

**`treesitter`** — `:help` → `value_origin` → `chain` + `binding_index` bauen →
**`identifier_locator`** → `symbol_locator.via_treesitter` → `require_path`.

**`builtin`** — nur pfadbasiert: `require_path` (plus der generische `filetoken`,
den `resolve.lua` ohnehin vor der Sprach-Ebene ausführt).

> **Reihenfolge zählt:** `identifier_locator` läuft **vor** `symbol_locator`,
> damit ein bloßer Identifier (`config`) sein *Modul* öffnet, während eine Kette
> (`config.setup`) weiterhin zum *Symbol* via `symbol_locator` auflöst.

---

## Unterstützte Muster

```lua
-- ✅ Unterstützt
local config = require("gopath.config")   -- bloßer Identifier → Modul
local cfg    = require("gopath.config")   -- Alias funktioniert
config       = require("gopath.config")   -- nicht-local funktioniert
require("gopath.config")                  -- direkter require-String/-Aufruf
config.setup()                            -- Kette → Symbol-Definition
config.get().value                        -- Value-Origin / Ketten-Verfolgung

-- ❌ Nicht unterstützt
local config = require(eine_variable)     -- dynamisches require (kein Literal)
local config = req("gopath.config")       -- aliasierte require-*Funktion*
```

---

## Edge Cases

**Scope-Shadowing.** `identifier_locator` arbeitet auf datei-globaler
Bindungs-Ebene:

```lua
local config = require("gopath.config")   -- äußere Bindung

function test()
  local config = {}                       -- innere, überdeckt die äußere
  print(config)                           -- identifier_locator öffnet das Modul
  --    ^^^^^^                             -- LSP würde auf das innere local zeigen
end
```

Für präzisen lexikalischen Scope ist `lsp`-Modus vorzuziehen (in `hybrid` hat er
Priorität).

**Aliasierte requires** (`local x = require("m"); x.field`) werden über
`alias_index` + `binding_index` behandelt. **Dynamische requires** (nicht-
literales Argument) lassen sich statisch nicht auflösen und fallen auf die
generischen Fallbacks zurück.

---

## Konfiguration

```lua
require("gopath").setup({
  mode  = "hybrid",                       -- oder "lsp" | "treesitter" | "builtin"
  order = { "lsp", "treesitter", "builtin" },
  lsp_timeout_ms = 200,
  languages = {
    lua = {
      enable           = true,
      resolvers        = nil,             -- nil = alle; oder Whitelist von Resolver-Namen
      custom_resolvers = nil,             -- eigene Resolver, laufen vor den eingebauten
    },
  },
})
```

`languages.lua.resolvers` auf eine Whitelist zu setzen (z. B. `{ "require_path" }`)
beschränkt, welche Lua-Resolver laufen; `custom_resolvers` schiebt eigene vor die
eingebauten. Siehe die [Auflösungs-Pipeline](./RESOLUTION-DE.md), wie diese Ebene
zwischen den universellen Resolvern sitzt.
