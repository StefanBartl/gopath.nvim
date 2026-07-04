# Architektur- und Codierungsrichtlinien

**Diese Richtlinien sind lebendig und sollten mit gewonnener Erfahrung erweitert werden.**

---

## Table of content

- [Architektur- und Codierungsrichtlinien](#architektur-und-codierungsrichtlinien)
  - [1. Sicherheitsprinzipien & Fehlerbehandlung](#1-sicherheitsprinzipien-fehlerbehandlung)
  - [2. Modularisierung & Strukturprinzipien](#2-modularisierung-strukturprinzipien)
  - [3. Buffer- & Window-Management](#3-buffer-window-management)
  - [4. Methoden, Metatables & Datenmodelle](#4-methoden-metatables-datenmodelle)
  - [5. Dokumentation & Annotationen](#5-dokumentation-annotationen)
  - [6. Testbarkeit & Lesbarkeit](#6-testbarkeit-lesbarkeit)
  - [7. Fehlerbehandlung & Validierung (Sicherheit)](#7-fehlerbehandlung-validierung-sicherheit)
  - [8. Performance & Speicher](#8-performance-speicher)
  - [9. Cache hitting](#9-cache-hitting)
  - [10. Schwache Tabellen & Memoisierung](#10-schwache-tabellen-memoisierung)
  - [11. Spezialfälle](#11-spezialflle)
  - [MISC](#misc)
    - [NVIM-Config spezifisch](#nvim-config-spezifisch)
  - [Annotations Regeln](#annotations-regeln)
  - [(Direkt-) Importe vs Alias](#direkt-importe-vs-alias)
    - [Table Field Lookup](#table-field-lookup)
    - [2. `vim.fn` & `vim.api`](#2-vimfn-vimapi)
    - [3. `require("mod").fn` vs gespeicherte Referenz](#3-requiremodfn-vs-gespeicherte-referenz)
    - [4. Lokale Aliase bei simplen Lua-Funktionen (nur 1.000 Aufrufe)](#4-lokale-aliase-bei-simplen-lua-funktionen-nur-1000-aufrufe)
  - [Importreihung](#importreihung)
  - [tables](#tables)
    - [Codebeispiele (Vergleich)](#codebeispiele-vergleich)
      - [Langsamste Methode: `table.insert` ohne Reserve](#langsamste-methode-tableinsert-ohne-reserve)
      - [Mittelfeld: `t[#t+1] = v` mit Reserve via Funktion](#mittelfeld-tt1-v-mit-reserve-via-funktion)
      - [Schnellste Methode: `t[i] = v` mit Inline-Reserve](#schnellste-methode-ti-v-mit-inline-reserve)
    - [Reserve-Funktion](#reserve-funktion)
    - [Empfehlungen](#empfehlungen)
  - [Strings](#strings)
    - [Zusammengefasst: Do & Don't](#zusammengefasst-do-dont)
  - [Reduce, Reuse und Recycle](#reduce-reuse-und-recycle)
    - [🔹 GC-Steuerung mit `collectgarbage`](#gc-steuerung-mit-collectgarbage)
  - [CPU-Operationen und deren relative Kosten in Lua](#cpu-operationen-und-deren-relative-kosten-in-lua)
    - [1. Register-Register-Operationen (ADD, OR, etc.)](#1-register-register-operationen-add-or-etc)
    - [2. Speicheroperationen (Memory Write)](#2-speicheroperationen-memory-write)
    - [3. Funktionsaufrufe (Direct Function Calls)](#3-funktionsaufrufe-direct-function-calls)
    - [4. Bedingte Anweisungen („if“)](#4-bedingte-anweisungen-if)
    - [5. Tabellenzugriffe (Table Access)](#5-tabellenzugriffe-table-access)
    - [6. Gleitkomma-Berechnungen (Floating-Point Calculations)](#6-gleitkomma-berechnungen-floating-point-calculations)
    - [7. String-Operationen](#7-string-operationen)
    - [8. Tabellenmanipulation (Table Manipulation)](#8-tabellenmanipulation-table-manipulation)
    - [9. Lua Metamethoden (Virtual Function Calls)](#9-lua-metamethoden-virtual-function-calls)
    - [10. Garbage Collection (GC)](#10-garbage-collection-gc)
    - [11. Thread Context Switch (Coroutines)](#11-thread-context-switch-coroutines)
    - [12. Error Handling (pcall/xpcall)](#12-error-handling-pcallxpcall)
  - [types-file demo](#types-file-demo)
  - [end](#end)

---

## 1. Sicherheitsprinzipien & Fehlerbehandlung

| Regel                             | Beschreibung                                                                               |
| --------------------------------- | ------------------------------------------------------------------------------------------ |
| `pcall()` bevorzugt               | Immer `pcall(...)` verwenden – lieber einmal zu viel als zu wenig                          |
| Type Guards & Literal Checks      | Immer `type(...)`, `== nil`, `~=` etc. prüfen, vor allem vor API-Zugriffen                 |
| Explizite Rückgaben               | Relevante Funktionen geben `true/false` + evtl. Fehlerobjekt zurück, keine stillen Fehler  |
| Kein `notify()` in Low-Level-Code | Nur UI-Schichten sollen Nutzer benachrichtigen                                             |
| Standardisiertes Error-Wrapping   | Verwende z. B. `safe_call(fn, args)` → `{ ok = true, result = ..., err = nil }`            |
| Strukturierte Fehlertypen         | Definiere klar unterscheidbare Fehler (z. B. `InvalidStateError`) für robustere Auswertung |
| `@error` & `@raises` Tags         | Dokumentiere erwartbare Fehler in der Annotation (`@raises`, `@error`)                     |

- Funktionen, die nur in der Datei verwendet werden in der die deklariert wurden, sollten privat bleiben (forward declaration for private functions)
- In jeder funktion müssen die Argumente übergeben werden (lua erlaubt auch auszulassen) -> type check gleich mitmachen bzw. assert

---

## 2. Modularisierung & Strukturprinzipien

| Regel                           | Beschreibung                                                          |
| ------------------------------- | --------------------------------------------------------------------- |
| Modul = eine Verantwortung      | z. B. `core/undo.lua`, `ui/preview_window.lua`, `tools/live_grep.lua` |
| Reine Funktionen bevorzugen     | Möglichst keine Seiteneffekte → besser testbar                        |
| Lokale statt globale Funktionen | Interne Hilfsfunktionen lokal halten, nicht im Modul exportieren      |
| Entwurfsmuster                  | Wenn sinnvoll Patterns wie Singleton, Factory, Observer,... nutzen    |
| Tools via Registry              | Tools über `registry.lua` zentral registrieren                        |
| Keine globalen States           | Alle Zustände explizit via Argumente übergeben (`ToolState`, etc.)    |
| Pure Functions                  | Wann immer möglich reine Funktionen ohne Seiteneffekte definieren     |

---

## 3. Buffer- & Window-Management

| Regel                                         | Beschreibung                                                                  |
| --------------------------------------------- | ----------------------------------------------------------------------------- |
| Zuerst `local win/buf = ...`                  | Erst zuweisen, dann prüfen                                                    |
| Immer prüfen: `~= nil` & `nvim_*_is_valid()`  | Gilt für Fenster und Buffer gleichermaßen                                     |
| Keine API-Calls ohne Prüfung                  | Jeder Zugriff auf `vim.api.nvim_*` mit Guard versehen                         |
| Einheitliche UI-Methoden                      | z. B. `open_window()`, `close_window()`, `configure()`, `apply_layout()`      |
| Zustand zentralen via `ui_state`-Modul halten | Fenster-/Buffer-Handles nur über Getter/Setter aus `ui_state` lesen/schreiben |
| automatische `cleanup_all()`-Funktion         | Schließt Fenster, löscht temporäre Buffer                                     |

---

## 4. Methoden, Metatables & Datenmodelle

| Regel                                              | Beschreibung                                            |
| -------------------------------------------------- | ------------------------------------------------------- |
| Metatables für Methoden wenn sinnvoll, nicht immer | z. B. `.add()`, `.clear()` bei `UndoStack`, `ToolState` |
| Getter/Setter für Zustand                          | Statt direktem Zugriff lieber `get_buf()`, `set_buf()`  |
| Ringbuffer-Strukturen                              | bei Bedarf, zb.: FIFO-Verhalten mit Limitierung         |
| `__index` via Shared Metatables                    | Für geteilte Default-Logik und Memoization              |

---

## 5. Dokumentation & Annotationen

| Regel                                  | Beschreibung                                                                |
| -------------------------------------- | --------------------------------------------------------------------------- |
| Einheitliche Datei-Tags                | Jede Datei beginnt mit `@module`, `@class`, `@brief`, `@description`        |
| Kommentare pro Funktion                | `@param`, `@return`, `@private`, `@async`, `@error`, `@raises` |
| Konsistentes Naming                    | Nur englische Namen in camelCase oder snake\_case (aber konsistent)         |
| Explizite Typisierungen                | z. B. `---@alias ToolState`, `---@field undo UndoEntry[]`                   |
| Modulverlinkung via `@see`             | z. B. `@see custom.live_grep_memory.core.preview`                           |
| Zusätzliche Tags wie @error, @raises   | Z. B. @raises InvalidQueryError if input is not valid                       |
| Verlinkung zu anderen Modulen via @see | Z. B. @see custom.live_grep_memory.core.preview                             |
| Subverzeichnis -> '/types'-ordner      | Jede Ebene mind. eine [types-file](#types-file-demo)  |

- Fü Module der `nvim/config` gilt: Jedes Modul braucht eine README.md in deutscher, /doc/MODULENAME.txt (für die nvim `:h`) in englischer Sprache!

---

## 6. Testbarkeit & Lesbarkeit

| Regel                                | Beschreibung                                                              |
| ------------------------------------ | ------------------------------------------------------------------------- |
| Klein & fokussiert (SRP)             | Funktionen sollen nur eine Aufgabe erfüllen                               |
| Klarheit vor Kürze                   | Kein "cleverer" Code auf Kosten der Lesbarkeit                            |
| Testbarkeit durch Design             | Keine Hardcoded States, globale Mutationen oder versteckte Abhängigkeiten |
| Snapshot-/Restore-Funktion           | Für `ToolState` – hilfreich für Tests & Vergleich                         |
| Separater Test-Entry (`tools/_test`) | Ermöglicht Dry-Runs z. B. via `require(...).test("toolname")`             |

---

## 7. Fehlerbehandlung & Validierung (Sicherheit)

| Erweiterung                                     | Beschreibung                                                                                                             |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| **Standardisierter Error-Wrapping-Mechanismus** | z. B. `safe_call(fn, args)` → gibt `{ ok = true, result = ..., err = nil }` zurück, um Fehler systematisch zu handhaben  |
| **Fehlertypen strukturieren**                   | z. B. `InvalidQueryError`, `InvalidStateError` – als Tags in Errors nutzen oder eigene Error-Wrapping-Funktion schreiben |

---

## 8. Performance & Speicher

| Regel                                                 | Beschreibung                                                               |
| ----------------------------------------------------- | -------------------------------------------------------------------------- |
| Debounced Save                                        | Schreibvorgänge z. B. bei `save()` sammeln und zeitverzögert durchführen   |
| Weak References in Caches                             | Speicherfreigabe durch `setmetatable(tbl, { __mode = "v" })` oder `"kv"`   |
| Async-Utils statt Blocking                            | Für Hintergrund-Tasks wie Preview oder History-Zählung → `vim.loop` nutzen |
| Memoization via Weak-Table oder Funktion              | z. B. Code via `load()` nur einmal auswerten                               |
| Memoization mit geteilten Metatables (Weak Values)    |                                                                            |
| Speichernahe Datenstrukturierung                      | Zusammengehörige Werte gemeinsam halten → besseres Cache-Verhalten         |
| Objektattribute                                       | mit `mode = "k"`                                                           |
| Defaultwerte mit Weak-Tables                          |                                                                            |
| Verwende **lokale Variablen**, wann immer möglich     | `local sin = math.sin` statt `math.sin(x)`                                 |
| Loop-unrolling nur wenn cpu intensiv, numeric nutzen! |                                                                            |

- Closures verwenden statt globale Zugriffe
- Tabellen mit bekannten Längen „vorfüttern“
   `local a = {[1] = false, [2] = false, [3] = false}` statt `local a = {}; a[1] = 0, a[2] = 1, a[3] = 2`
- nutze `table.clear(t)` oder einen Tabellenpool mit Vorinitialisierung.
- `collectgarbage()` explizit aufrufen, wenn man sicher ist, dass eine große Tabelle oder viele Objekte nicht mehr gebraucht werden.||
   ```lua
   t = nil
   collectgarbage("collect")
   ```
   nur wenn man weiß, dass:
   - man große Objekte wie Tabellen aktiv entfernt hat,
   - sofort Speicher freigegeben werden soll,
   - und man weiß, dass das Programm dadurch nicht verlangsamt wird.

**Strings:**
| Vermeiden                        | Stattdessen                             |
| -------------------------------- | --------------------------------------- |
| `s = s .. line` in Schleifen     | `table.concat` mit Buffer-Tabelle       |
| häufige `string.sub(...)`        | arbeite mit Rückgabe-Indices von `find` |
| viele große Strings ad hoc bauen | vordefinierte Bausteine / Templates     |
| mehrfach gleiche Strings         | interniert Lua automatisch              |

**Reduce, Reuse & Recycling**
| Ziel                         | Empfehlung                          |
| ---------------------------- | ----------------------------------- |
| Speicher sparen              | Arrays statt Records nutzen         |
| GC-Last reduzieren           | Objekte wiederverwenden             |
| Closures vermeiden           | Wiederverwendbare Funktionen nutzen |
| Speicher zurückgeben         | `t = nil; collectgarbage()`         |
| Coroutine-Aufwand reduzieren | eigene Coroutine mit Job-Schleife   |

## 9. Cache hitting

| Regel          | Beschreibung                                                  |
| -------------- | ------------------------------------------------------------- |
| **Tool-Cache** | Queries mit hohem Match-Count zwischenspeichern (memory-only) |

  - Vermeide große Tabellen mit gemischten Datentypen
  - Führe Berechnungen in Schleifen direkt aus, anstatt Funktionen zu verwenden
  - Vermeide unnötige Schleifen und reduziere die Anzahl der Speicherzugriffe innerhalb von Schleifen
  - Verwende numerische Indizes statt String-Keys für Tabellen
  - Strukturiere Daten so, dass zusammenhängende Werte auch im Speicher benachbart liegen

---

## 10. Schwache Tabellen & Memoisierung

| Regel                               | Beschreibung                                                           |
| ----------------------------------- | ---------------------------------------------------------------------- |
| Schwache Werte (`__mode = "v"`)     | Entfernt nicht mehr referenzierte Werte automatisch aus dem Cache      |
| Schwache Schlüssel (`__mode = "k"`) | Z. B. bei Default-Werten für Tabellen → `defaults[tab] = default`      |
| Shared Metatables mit Memoization   | Für wiederverwendete Strukturen oder Methoden (z. B. `.get_default()`) |

---

## 11. Spezialfälle

| Thema                           | Beschreibung                                                                |
| ------------------------------- | --------------------------------------------------------------------------- |
| Dual Representation             | Trennung von Daten und zugehörigen Zusatzwerten via separate Weak-Tables    |
| Defaultwerte über Metatable     | `__index = function(t) return defaults[t] end` bei mehreren Tabellen        |
| Strukturierte Favoriten/History | Bei Einträgen mit begrenzter Anzahl: FIFO mit Limits und speicherfreundlich |
| Geteilte Logik durch `__index`  | Z. B. bei Tools mit gemeinsamer Basisfunktionalität                         |

---

## MISC

1. Soweit möglich immer so entwickeln, dass POSIX (Linux/MacOS) als auch Windows mit der Software verwendbar sind (Cross-Plattform).

---

### NVIM-Config spezifisch

1. Verwende die custom `/nvim/lua/lib/**/**.lua`-Library, insbesondere:
    - `lib.notify` anstatt `vim.notify()` oder `print()`
    - `lib.map` anstatt `vim.keymap.set`; respektive `lib.usercmd`, `lib.autocmd`, `lib.augroup`
    - `lib.cross_plattform` / `lib.cross`: Alle Module müssen entweder Cross-Plattform sein oder eine alternative innerhalb des Moduls bereitstellen
    - `lib.hover_select`: Ein wrapper der vim.select ersetzt und bei kontinuierlicher Verwendung eine konsequente UI ermöglicht
    - `lib.lazy` ermöglich die Vermeidung unnötiger Ladelast
    - `lib.memo` ermöglicht Standardisierte Memoization
    - uvm...

---

## Annotations Regeln

- Es wird in jedem Projekt eine /@types Ordner mit einsterechenden Typdateien angelegt, um den Source COde von viel Annotierungs-Text zu entlasten. zb: @types/terminal. @types/command, @types/ui usw...
- Die  `@types`-Dateimodule returnen alle eine leere table, also `return {}` als letzte Zeile
- Einheitliche Datei-Tags                - Jede Datei beginnt mit `@module`, `@class`, `@brief`, `@description`
- Kommentare pro Funktion                - `@param`, `@return`, `@private`, `@see`
  - ggf. `@async`, `@error`, `@raises` (Da Lua_ls diese nicht unterstützut, nur wenn es einen guten Grund dafür gibt)
  - Bei Funktionen darauf achten, das auch `@return nil` angegeben wird wenn nötig
- Konsistentes Naming                    - Nur englische Namen in camelCase oder snake\_case (aber konsistent)
- Explizite Typisierungen                - z. B. `---@alias ToolState`, `---@field undo UndoEntry[]`
- Modulverlinkung via `@see`             - z. B. `@see custom.live_grep_memory.core.preview`
- Zusätzliche Tags wie @error, @raises   - Z. B. @raises InvalidQueryError if input is not valid
- Verlinkung zu anderen Modulen via @see - Z. B. @see custom.live_grep_memory.core.preview
- `#`-Prefix bei Kommentaren:
| Kontext              | `# Kommentar` erlaubt/empfohlen?    | Alternativen                        |
| -------------------- | ----------------------------------- | ----------------------------------- |
| `---@alias` Einträge | ✅ Ja – standardkonform              | Kommentar in gleicher Zeile         |
| `---@return` Zeilen  | ✅ Ja – empfohlen laut Lua LS        | alternativ hinter dem Typ           |
| `---@field` Zeilen   | ⚠ Möglich, aber **nicht empfohlen** | lieber ohne `#`, normaler Kommentar |

```lua
---@alias CloneStrategy
---| "git"    # Full Git clone
---| "curl"   # Archive download via curl
-- oder
---@return string # The formatted result
```



```lua
---@module 'reposcope.config'
---@brief Handles the dynamic configuration setup and access for Reposcope.
---@description
--- This module manages the active configuration of Reposcope. It merges user-provided options
--- (via `.setup({ ... })`) with default values from `reposcope.defaults` and provides a unified
--- interface to access configuration values during runtime.
---
--- Key responsibilities:
--- - Validating and sanitizing `ConfigOptions`
--- - Providing a `setup()` entry point for user configuration
--- - Resolving nested default structures like `clone`, `keymaps`, etc.
--- - Allowing access to values via `get_option(key)` abstraction
--- - Computing fallback paths like `cache_dir` and `logfile_path`
---
--- The resulting `M.options` table is always fully populated and safe to use across modules.
--- Use `get_option(key)` instead of accessing `M.options` directly to preserve fallback logic.

---@class ReposcopeConfig : ReposcopeConfigModule
local M = {}

-- Utilities and Debugging
local notify = require("reposcope.utils.debug").notify
-- Application State
local ui_state = require("reposcope.state.ui.ui_state")
-- Preview-Specific Configuration and Banner
local preview_config = require("reposcope.ui.preview.preview_config")
local banner = require("reposcope.ui.preview.preview_banner").get_banner
-- Cache Access
local readme_cache = require("reposcope.cache.readme_cache")


--- Injects arbitrary content into the specified buffer and applies the given filetype.
---@param buf integer The buffer handle to inject content into
---@param lines string[] The lines to insert
---@param filetype string Filetype to apply to the buffer (e.g. "markdown", "text")
---@return nil
function M.inject_content(buf, lines, filetype)
....
....
```

## (Direkt-) Importe vs Alias

| Thema                     | Methode                     | Aufrufe   | Zeitunterschied                    |
| ------------------------- | --------------------------- | --------- | ---------------------------------- |
| 🔧 `table.field(x)`        | direkt vs `local fn`        | 1.000.000 | **\~23% schneller mit `local`**    |
| 🧰 `vim.fn` / `vim.api`    | direkt vs alias             | 1.000.000 | **kein signifikanter Unterschied** |
| 📦 `require(...)`          | direkt vs zwischenspeichern | 1.000.000 | **<1% Unterschied**                |
| ⚙️ einfache Lua-Funktionen | 1.000 Calls                 | 1.000     | **kein messbarer Effekt**          |

**Empfehlung:**

| Wenn...                                          | Dann...                                              |
| ------------------------------------------------ | ---------------------------------------------------- |
| du Code in **tight loops** schreibst             | nutze `local fn = mod.fn`                            |
| du Neovim-Funktionen (`vim.fn`, `vim.api`) nutzt | direkt oder indirekt – egal, Hauptsache nicht zu oft |
| du nur einmal aufrufst                           | verwende einfach `mod.fn()`                          |

### Table Field Lookup

```lua
-- Direkt (langsamer)
for i = 1, N do
  local _ = mod.do_something(i)
end

-- Indirekt via lokale Referenz (schneller)
local fn = mod.do_something
for i = 1, N do
  local _ = fn(i)
end
```

**Benchmark-Ergebnis**

| Zugriff               | Zeit (ms) für 1M Calls |
| --------------------- | ---------------------- |
| `mod.do_something(i)` | 20.88 ms               |
| `local fn = ...`      | **16.03 ms**           |

**👉 Fazit:** lokale Referenz reduziert `table`-Zugriffe – lohnt sich bei vielen Calls.

---

### 2. `vim.fn` & `vim.api`

```lua
-- Direkt
vim.fn.expand("%")

-- Indirekt
local expand = vim.fn.expand
expand("%")
```

| Zugriff           | Zeit (ms) |
| ----------------- | --------- |
| Direkt            | 177.69    |
| Lokal gespeichert | 178.93    |

**👉 Fazit:** Unterschied vernachlässigbar – `vim.fn` ist **immer langsam**, egal wie.

---

### 3. `require("mod").fn` vs gespeicherte Referenz

```lua
-- Direkt
require("debug").notify("bench", 1)

-- Indirekt
local notify = require("debug").notify
notify("bench", 1)
```

| Zugriff  | Zeit (ms, 1M Calls) |
| -------- | ------------------- |
| direkt   | 676.61              |
| indirekt | **672.60**          |

**👉 Fazit:** Mini-Vorteil (\~0.6%), aber nicht spürbar.

---

### 4. Lokale Aliase bei simplen Lua-Funktionen (nur 1.000 Aufrufe)

```lua
-- Direkt
for i = 1, 1000 do schedule(fn) end

-- Indirekt
local sched = schedule
for i = 1, 1000 do sched(fn) end
```

| Zugriff  | Zeit (ms) |
| -------- | --------- |
| direkt   | 0.04      |
| indirekt | 0.04      |

**👉 Fazit:** Für kleine Schleifen **irrelevant**

---

## Importreihung

Folgende Import Reihenfolge einhalten:

1. System- und Kernmodule (Standardbibliothek)
   * Zuerst Module, die aus der Standard-Lua-Bibliothek oder der Neovim-API stammen (`vim`, `uv`, etc.).

2. Debug, Metric oder Notify Module

3. Projektspezifische Config- und Utility-Module
   * Module, die für die Konfiguration und grundlegende Utility-Funktionen zuständig sind.

4. State-Module (Zustandsverwaltung)
   * Module, die den Zustand des Projekts (State Management) verwalten.

5. UI-Komponenten (Komponenten, Fenster, Layouts)
   * Module, die UI-Elemente oder Layouts erstellen und verwalten.

6. UI-spezifische Funktionen und Submodule

7. Controller und Logik
   * Controller-Module, die für die Geschäftslogik und zentrale Steuerung der UI verantwortlich sind.

8. Keymaps und Benutzereingaben
   * Module, die Tastenkombinationen und Benutzereingaben festlegen.

--

## tables

Effizientes **Befüllen von Tabellen** in Lua mit unterschiedlicher Speicherstrategie:

* `table.insert(t, v)`
* `t[#t + 1] = v`
* `t[i] = v`

Jeweils getestet:

* **ohne Reservierung** (`plain`)
* **mit Reservierung über Funktion** (`reserve(n, "number")`)
* **inline reserviert** (`{ [n] = 0 }`)

**Benchmark-Ergebnisse**

| Size      | insert | insert\_fn | insert\_inline | #+1   | #+1\_fn | #+1\_inline | t\[i]    | t\[i]\_fn | t\[i]\_inline |
| --------- | ------ | ---------- | -------------- | ----- | ------- | ----------- | -------- | --------- | ------------- |
| 1.000     | 0.04   | 0.03       | 0.03           | 0.02  | 0.02    | 0.01        | 0.01     | 0.01      | 0.01          |
| 10.000    | 0.45   | 0.36       | 0.30           | 0.13  | 0.13    | 0.14        | 0.08     | 0.08      | 0.08          |
| 100.000   | 3.73   | 3.58       | 3.36           | 1.36  | 1.32    | 1.33        | 0.83     | 0.79      | 0.90          |
| 1.000.000 | 36.65  | 33.23      | **30.59**      | 13.34 | 13.07   | 13.16       | **7.96** | 8.23      | 8.40          |

| Beobachtung                               | Erklärung                                                    |
| ----------------------------------------- | ------------------------------------------------------------ |
| `t[i]` ist **konstant am schnellsten**    | keine Berechnung wie bei `#t`, keine Funktion wie `insert()` |
| `#+1` ist schneller als `insert()`        | `#t+1` ist schneller als interner Insert-Verschiebeaufwand   |
| `inline reserve` ist minimal schneller    | spart Funktionsaufruf auf dem kritischen Pfad                |
| Reservierung bringt **merkbare Vorteile** | besonders bei `insert()` (reduziert Rehashes/Reallokationen) |

### Codebeispiele (Vergleich)

#### Langsamste Methode: `table.insert` ohne Reserve

```lua
local t = {}
for i = 1, N do
  table.insert(t, i)
end
```

#### Mittelfeld: `t[#t+1] = v` mit Reserve via Funktion

```lua
local t = reserve(N, "number")
for i = 1, N do
  t[#t + 1] = i
end
```

#### Schnellste Methode: `t[i] = v` mit Inline-Reserve

```lua
local t = { [N] = 0 }  -- reserviert Speicherplatz
for i = 1, N do
  t[i] = i
end
```

---

### Reserve-Funktion

```lua
---Reserves a table with a dummy value at index [n]
---@param n integer
---@param value_type "number"|"string"|"boolean"
function reserve(n, value_type)
  local dummy = value_type == "number" and 0 or ""
  return { [n] = dummy }
end
```

### Empfehlungen

| Wenn du...                              | Dann verwende...              |
| --------------------------------------- | ----------------------------- |
| maximale Performance brauchst           | `t[i] = v` mit Inline-Reserve |
| dynamisch anhängst, Länge unbekannt     | `t[#t+1] = v`                 |
| Lesbarkeit bevorzugst, Performance egal | `table.insert()`              |

---

## Strings

1. **Vermeide Verkettung in Schleifen**

```lua
local s = ""
for i = 1, N do
  s = s .. "..."  -- ❌ sehr ineffizient!
end
```

**Problem:** Jeder Schritt erzeugt eine **neue Kopie**, da Strings in Lua **unveränderlich** sind.
**Komplexität:** *quadratisch (O(n²))* bei großen Strings.

**Stattdessen:**

```lua
local t = {}
for i = 1, N do
  t[#t+1] = "..."
end
local s = table.concat(t)
```

> `table.concat()` ist **schnell**, weil es den Speicher **nur einmal allokiert**.

---

2. **Nutze Lua-String-Internalisierung bewusst aus**

```lua
local a = "status"
local b = "status"
print(a == b)  -- schnell, da interniert
```

* Gleichlautende Literale werden automatisch **gemeinsam** gespeichert.
* **String-Vergleiche und Table-Keys** sind dadurch extrem schnell (nur Pointer-Vergleich).

---

3. **Vermeide unnötige String-Kopien**

```lua
local a = "großer block"
local b = a  -- ✅ nur Referenzkopie (schnell)
```

* Lua kopiert keine Inhalte bei Zuweisung.
* Anders als z. B. in PHP oder Perl → dort entstehen Kopien → teuer.

---

4. **Verwende `string.sub` statt neue Teilstrings**

Beispiel:

```lua
local i, j = string.find(str, pattern)
local sub = string.sub(str, i, j)
```

> Besser: Arbeite direkt mit den **Indizes**, wenn du nur prüfen willst!

Schneller, da **keine neue Zeichenkette** erstellt wird.

---

**Reduziere String-Garbage**

* Jeder neue String belastet den Garbage Collector.
* Häufige `..`-Operationen → sehr viele temporäre Strings → GC-Last steigt.

Verwende Stringbuffer mit `table.concat` zur **Minimierung von String-Garbage**.

---

6. **Tools: Verwende eigene Buffer-Wrapper**

Du kannst einfache Hilfsfunktionen bauen:

```lua
function make_string_buffer()
  local t = {}
  return {
    add = function(s) t[#t+1] = s end,
    result = function() return table.concat(t) end
  }
end
```

---

### Zusammengefasst: Do & Don't

| ❌ Vermeiden                      | ✅ Besser machen                         |
| -------------------------------- | --------------------------------------- |
| `s = s .. line` in Schleifen     | `table.concat` mit Buffer-Tabelle       |
| häufige `string.sub(...)`        | arbeite mit Rückgabe-Indices von `find` |
| viele große Strings ad hoc bauen | vordefinierte Bausteine / Templates     |
| mehrfach gleiche Strings         | interniert Lua automatisch              |

---

## Reduce, Reuse und Recycle

**REDUCE – Weniger Objekte erzeugen**

🔹 Tabellen effizient darstellen

| Statt            | Besser                                 |
| ---------------- | -------------------------------------- |
| `{ {x=1, y=2} }` | `{ {1, 2} }` oder `{x={...}, y={...}}` |

→ Reduziert Speicherbedarf um bis zu **75 %** bei großen Datenmengen.

---

🔹 Tabellen außerhalb von Schleifen erzeugen

```lua
-- schlecht:
for i = 1, n do
  local t = {1,2,3}
end

-- besser:
local t = {1,2,3}
for i = 1, n do
  -- t wiederverwenden
end
```

→ Vermeidet viele kleine Speicherallokationen und GC-Last.

---

🔹 Closures nicht im Loop erzeugen

```lua
-- schlecht:
gsub(str, "%d+", function(n) return n end)

-- besser:
local f = function(n) return n end
gsub(str, "%d+", f)
```

---

**REUSE – Wiederverwenden statt Neuanlegen**

🔹 Tabellen-Instanzen recyceln

```lua
-- statt:
for y = ... do
  t[y] = os.time({year=y, month=6})
end

-- besser:
local base = {month=6}
for y = ... do
  base.year = y
  t[y] = os.time(base)
end
```

---

🔹 Memoization mit Weak Tables

```lua
function memoize(f)
  local mem = setmetatable({}, {__mode = "kv"})
  return function(x)
    local r = mem[x]
    if not r then
      r = f(x)
      mem[x] = r
    end
    return r
  end
end
```

→ Spart teure Berechnungen (z. B. `loadstring`, LPeg-Muster, Parser etc.)

---

**RECYCLE – Lua's Garbage Collector gezielt nutzen**

🔹 Coroutine-Recycling

```lua
co = coroutine.create(function(f)
  while f do
    f = coroutine.yield(f())
  end
end)
```

→ Eine Coroutine, viele Jobs.

---

### 🔹 GC-Steuerung mit `collectgarbage`

| Befehl            | Wirkung                              |
| ----------------- | ------------------------------------ |
| `"stop"`          | pausiert GC                          |
| `"restart"`       | aktiviert GC wieder                  |
| `"collect"`       | sofortige Vollsammlung               |
| `"count"`         | aktuellen Speicherverbrauch (in KB)  |
| `"setpause", X`   | pausiert länger (größer = später)    |
| `"setstepmul", X` | erhöht Arbeitsintensität pro Schritt |

> GC gezielt **in Leerlaufzeiten ausführen** oder bei speicherintensiven Phasen feinjustieren.

| Ziel                         | Empfehlung                          |
| ---------------------------- | ----------------------------------- |
| Speicher sparen              | Arrays statt Records nutzen         |
| GC-Last reduzieren           | Objekte wiederverwenden             |
| Closures vermeiden           | Wiederverwendbare Funktionen nutzen |
| Speicher zurückgeben         | `t = nil; collectgarbage()`         |
| Coroutine-Aufwand reduzieren | eigene Coroutine mit Job-Schleife   |

---

## CPU-Operationen und deren relative Kosten in Lua

![CPU operation costs](./CPU_Operations.png)

| Kategorie                     | Kosten (Zyklen) | Beispiel                          |
| ----------------------------- | --------------- | --------------------------------- |
| Register-Register-Operationen | < 1             | `local a = 5 + 3`                 |
| Speicheroperationen           | \~1             | `local value = 42`                |
| Funktionsaufrufe              | 15–30           | `local result = greet()`          |
| Bedingte Anweisungen          | 1–20            | `if x > 5 then ... end`           |
| Tabellenzugriffe              | 3–21            | `local value = tbl.key`           |
| Gleitkomma-Berechnungen       | 10–40           | `local result = 10.0 / 3.0`       |
| String-Manipulationen         | 15–50           | `local str = "Hello" .. " World"` |
| Lua Metamethoden              | 30–60           | `setmetatable`                    |
| Garbage Collection            | 100–500         | `collectgarbage("collect")`       |
| Coroutines (Threads)          | 1000–10.000     | `coroutine.resume(co)`            |
| Error Handling                | 2000–5000       | `pcall` / `xpcall`                |

---

### 1. Register-Register-Operationen (ADD, OR, etc.)

* **Kosten:** < 1 Zyklus (sofortige Operationen)
* **Lua-Beispiele:**

```lua
-- Addition (direkt in Registern)
local a = 5 + 3

-- Logische Operation (OR)
local result = true or false
```

* **Erläuterung:** Diese Operationen werden direkt in den CPU-Registern ausgeführt und sind extrem schnell. Sie werden direkt als CPU-Maschinenbefehle übersetzt.

---

### 2. Speicheroperationen (Memory Write)

* **Kosten:** \~1 Zyklus (direkter Speicherzugriff)
* **Lua-Beispiele:**

```lua
-- Wert in eine Variable schreiben (Speicheroperation)
local value = 42

-- Element in einer Tabelle schreiben (Speicherzugriff)
local tbl = {}
tbl[1] = "Hello"
```

* **Erläuterung:** Das Zuweisen eines Wertes an eine Variable oder das Ändern eines Werts in einer Tabelle entspricht einem direkten Speicherzugriff.

---

### 3. Funktionsaufrufe (Direct Function Calls)

* **Kosten:** 15–30 Zyklen (direkter Funktionsaufruf)
* **Lua-Beispiele:**

```lua
-- Direkter Funktionsaufruf
local function greet()
    return "Hello, World!"
end

local message = greet()
```

* **Erläuterung:** Ein direkter Funktionsaufruf in Lua ist sehr schnell, da die Zieladresse der Funktion direkt bekannt ist.

---

### 4. Bedingte Anweisungen („if“)

* **Kosten:** 1–2 Zyklen für „richtigen“ Pfad, 10–20 Zyklen für „falschen“ Pfad (Branch Misprediction)
* **Lua-Beispiele:**

```lua
-- Bedingte Anweisung (richtiger Pfad)
local x = 10
if x > 5 then
    print("Greater than 5")
end

-- Bedingte Anweisung (falscher Pfad)
local y = 2
if y > 5 then
    print("Greater than 5")
end
```

* **Erläuterung:** Wenn die Bedingung richtig vorhergesagt wird (CPU Branch Prediction), ist die Ausführung schnell. Bei falscher Vorhersage (Branch Misprediction) muss die CPU die Pipeline neu laden.

---

### 5. Tabellenzugriffe (Table Access)

* **Kosten:** 3–4 Zyklen (Cache-Hit), 7–21 Zyklen (Cache-Miss)
* **Lua-Beispiele:**

```lua
-- Zugriff auf eine Tabelle (schnell, wenn im Cache)
local tbl = { key = "value" }
local value = tbl.key

-- Zugriff auf eine Tabelle, die im Speicher neu geladen wird (langsamer)
local tbl = {}
for i = 1, 1000000 do
    tbl[i] = i
end
local val = tbl[999999]
```

* **Erläuterung:** Der erste Zugriff auf eine Tabelle ist schnell (L1-Cache). Wiederholte Zugriffe können je nach Cache-Hierarchie langsamer sein.

---

### 6. Gleitkomma-Berechnungen (Floating-Point Calculations)

* **Kosten:** 10–40 Zyklen
* **Lua-Beispiele:**

```lua
-- Gleitkomma-Division
local result = 10.0 / 3.0

-- Gleitkomma-Multiplikation
local result = 3.1415 * 2.718
```

* **Erläuterung:** Gleitkommaoperationen sind komplexer als Ganzzahlarithmetik und erfordern mehr CPU-Ressourcen.

---

### 7. String-Operationen

* **Kosten:** 15–50 Zyklen (je nach Länge und Speicherort)
* **Lua-Beispiele:**

```lua
-- String-Konkatenation (relativ langsam)
local str = "Hello" .. " World"

-- String-Manipulation (Substring)
local part = string.sub("Hello World", 1, 5)
```

* **Erläuterung:** String-Konkatenation in Lua erzeugt oft neue Speicherbereiche, was zusätzliche Kosten verursacht.

---

### 8. Tabellenmanipulation (Table Manipulation)

* **Kosten:** 15–50 Zyklen (je nach Komplexität)
* **Lua-Beispiele:**

```lua
-- Hinzufügen eines Elements in eine Tabelle
local tbl = {}
table.insert(tbl, "new item")

-- Entfernen eines Elements
table.remove(tbl, 1)
```

* **Erläuterung:** Das Einfügen und Entfernen von Elementen aus einer Tabelle ist relativ kostspielig, da Speicher neu organisiert werden muss.

---

### 9. Lua Metamethoden (Virtual Function Calls)

* **Kosten:** 30–60 Zyklen
* **Lua-Beispiele:**

```lua
-- Definieren eines Metatable (Metamethode)
local mt = {
    __index = function(tbl, key)
        return "Default Value"
    end
}

local myTable = setmetatable({}, mt)
print(myTable.nonexistent)
```

* **Erläuterung:** Der Zugriff auf eine Metamethode erfordert zusätzliche Berechnungen und Adressauflösungen.

---

### 10. Garbage Collection (GC)

* **Kosten:** 100–500 Zyklen (abhängig vom Speicher und den Objekten)
* **Lua-Beispiele:**

```lua
-- Manuelle Garbage Collection (sehr teuer)
collectgarbage("collect")
```

* **Erläuterung:** Die Garbage Collection in Lua ist relativ kostspielig, insbesondere wenn viele Objekte freigegeben werden müssen.

---

### 11. Thread Context Switch (Coroutines)

* **Kosten:** 1000–10.000 Zyklen (je nach Kontext)
* **Lua-Beispiele:**

```lua
-- Einfache Coroutine (geringer Overhead)
local co = coroutine.create(function()
    print("Hello from Coroutine")
end)
coroutine.resume(co)
```

* **Erläuterung:** Einfache Coroutines sind relativ günstig. Komplexe Coroutines mit vielen Zuständen können jedoch sehr teuer sein.

---

### 12. Error Handling (pcall/xpcall)

* **Kosten:** 2000–5000 Zyklen (je nach Fehler und Aufrufstruktur)
* **Lua-Beispiele:**

```lua
-- Fehlerbehandlung mit pcall (Fehler abfangen)
local success, err = pcall(function()
    error("This is an error")
end)

-- Detaillierte Fehlerbehandlung mit xpcall
local success, err = xpcall(function()
    error("This is another error")
end, debug.traceback)
```

* **Erläuterung:** Die Fehlerbehandlung ist teuer, da sie Stack-Traces und Debugging-Informationen beinhaltet.

---

## types-file demo

**Ziel ist,** den **Source Code nicht mit Annotationen zu fluten** und damit schlechter lesbarer zu machen und dennoch frei zu sein, **freizügig und detailliert Annotationen zu schreiben** und somit den **Umgang mit den Source Code** in Zukunft durch z.B.: LSP-Unterstützung **angenehmer zu gestalten**.

- Jedes Subverzeichnis soll seinen eigene '/types'-Folder haben, der mindestens eine 'init.lua'-Datei enthält
- In einer `.../types/init.lua` Grupperiungen nach Datei in folgenden Stil vornehmen:

```lua
--- #####################################################################
--- Xy.lua
```

- Wenn eine Datei zahlreiche eigene Annotationen enthält -> separate Datei erstellen
- Jede `class`, `field`, `alias` - Felder detaillreich beschreiben!


```lua
---@module 'xxx.types'

-- #####################################################################
-- Xy.lua

---@alias PathMode_t
--- Controls the reference frame used to render the buffer path.
--- Behavior details:
---| '"auto"' : Try repo root (fast upward scan for ".git"; if worktree, use the worktree top). If no repo,
---             use cwd-relative. If still identical, emit absolute (canonicalized).
---| "repo": Always compute relative to repo root; if no repo is detected, emit absolute (canonicalized).
---| "cwd":  Always compute relative to current working directory (vim.fn.getcwd()).
---| "absolute": Emit absolute (canonicalized) path; no relativization is attempted.
---| "home": Emit absolute path but replace $HOME prefix with "~" (if path is inside $HOME).
--- Edge cases:
---   • Unnamed/empty buffer names yield "[No Name]".
---   • Non-existing paths are still normalized syntactically; realpath resolution is best-effort.
---   • Symlinks: If uv.fs_realpath succeeds, the canonical target is shown; otherwise the expanded absolute path.
---   • Git worktrees: If ".git" is a file containing "gitdir: ...", the enclosing directory is treated as the repo root.

---@alias Path_home_tilde_t boolean
--- Whether to shorten the user's home directory prefix to "~" in absolute-style outputs.
--- Applies to:
---   • "absolute" and "home" modes directly.
---   • "auto" mode when it falls back to absolute output (i.e., no repo and cwd-relative equals absolute).
--- Does not affect:
---   • Purely relative outputs ("repo"/"cwd"), unless those modes fall back to absolute as described.
--- Rationale:
---   • Improves readability by reducing long, stable prefixes ("/Users/alice/", "/home/alice/") to "~/".
---   • Never alters genuinely relative strings like "src/module/file.lua".
--- Notes:
---   • Only applied if the absolute path begins with the user's home directory as returned by uv.os_homedir().
---   • On systems without a valid home directory, this option is effectively a no-op.

---@class LspStlPathCfg
---@field path_mode PathMode_t
---@field path_home_tilde Path_home_tilde_t


-- #####################################################################
-- short_ex.lua

---@class ShortExInfo
---@field label string        -- canonical display of the command (e.g. ":w", ":w!")
---@field help  string|nil    -- help tag to try (e.g. ":w", ":quit", ":bdelete")
---@field desc  string        -- concise human-readable explanation


-- #####################################################################
-- some.lua

---@class HighlightColors
--- Global highlight for the active line in a window when cursorline is enabled.
--- Applied via `vim.api.nvim_set_hl(0, "CursorLine", spec)` and then referenced by
--- `winhighlight` for active windows. Typical keys: `bg`, `fg`, `bold`, `italic`, `underline`, `sp`.
--- Side-effects: none; if `color_persist = true`, it is reapplied after colorscheme changes.
---
---@field CursorLine table
---
--- Highlight for the line number of the cursor row. Mapped in `winhighlight` as `CursorLineNr:CursorLineNr`.
--- Typical keys: `fg`, `bg`, `bold`. Should contrast against the normal line numbers.
--- Side-effects: modifies perceived focus and line-number contrast in the active window.
---@field CursorLineNr table
---
--- Highlight for a vertical cursor column guide (when enabled). Applied through `winhighlight` mapping
--- `CursorColumn:CursorColumn`. Typical keys: `bg` (avoid high-contrast to reduce distraction).
--- Performance: disabled for large files if `min_colored_file_kb` threshold is exceeded.
---@field CursorColumn table
---
--- Synthetic cursor highlight group used by `guicursor` mapping when `map_cursor_to_hl = true`.
--- Typical keys: `bg`, `fg` for block/bar/underline styles. If per-mode mapping is disabled,
--- all modes may share this single group.
---@field Cursor table
---
--- Per-mode CursorLine tint used only when `enable_insert_submode_colors = true`.
--- `CursorLineN` is the tint for Normal-like modes. Applied via dynamic `winhighlight`.
```

## end
