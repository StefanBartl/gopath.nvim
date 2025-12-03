# Dateisuche und Tokenverarbeitung in Neovim

## Table of content

  - [Übersicht](#bersicht)
  - [EBNF der Dateisuchsyntax (`{path}`-Ausdrücke)](#ebnf-der-dateisuchsyntax-path-ausdrcke)
  - [`findfile()`](#findfile)
    - [Zweck](#zweck)
    - [Aufruf](#aufruf)
    - [Ablauf der Suche](#ablauf-der-suche)
    - [Beispiel in Lua](#beispiel-in-lua)
  - [`matchstr()`](#matchstr)
    - [Zweck](#zweck-1)
    - [Beispiel](#beispiel)
  - [`fnameescape()`](#fnameescape)
    - [Zweck](#zweck-2)
    - [Beispiel](#beispiel-1)
  - [`includeexpr`](#includeexpr)
    - [Zweck](#zweck-3)
    - [Typischer Ablauf](#typischer-ablauf)
    - [Beispiel](#beispiel-2)
  - [`suffixesadd`](#suffixesadd)
    - [Zweck](#zweck-4)
    - [Beispiel](#beispiel-3)
    - [Beispiel in Lua](#beispiel-in-lua-1)
  - [Zusammenspiel der Komponenten](#zusammenspiel-der-komponenten)
  - [Literatur](#literatur)

---

## Übersicht

Dieser Artikel beschreibt zentrale Mechanismen der Dateisuche und Tokenaufbereitung in Neovim. Die folgenden Komponenten werden erläutert:

* `findfile()`
* `matchstr()`
* `fnameescape()`
* `includeexpr`
* `suffixesadd`
* EBNF-Formalisierung der Dateisuchsyntax

Alle Beispiele sind so formuliert, dass man sie in eigenen Plugins, Funktionen oder Mappings nutzen kann.

---

## EBNF der Dateisuchsyntax (`{path}`-Ausdrücke)

Die Syntax für `{path}`-Angaben (z. B. in `:find`, `findfile()` oder der Option `&path`) lässt sich wie folgt beschreiben:

```
Path           = PathEntry { "," PathEntry } ;
PathEntry      = UpwardEntry | RecursiveEntry | DirectoryEntry | CurrentDir ;
UpwardEntry    = DirectoryEntry ";" [ StopDirs ] ;
StopDirs       = Directory { "," Directory } ;
RecursiveEntry = "**" [ DirectoryTail ] ;
DirectoryEntry = DirectoryTail ;
DirectoryTail  = { DirectoryChar } ;
DirectoryChar  = ? any character except "," and ";" ? ;
CurrentDir     = "" | "." ;
```

Zusätzliche Anmerkungen:

* Ein leeres PathEntry bedeutet „aktuelles Verzeichnis“.
* `"**"` bedeutet rekursive Suche nach unten.
* Ein Eintrag mit Semikolon (`";"`) bedeutet Suche nach oben (Parent-Verzeichnisse).
* `DirectoryTail` repräsentiert einen normalen Pfad wie `src`, `foo/bar`, `./include`.

---

## `findfile()`

### Zweck

`findfile()` sucht eine Datei gemäß Neovims *file-searching rules*. Es ist die Kernfunktion, die auch für `:find` oder indirekt für `gf` entscheidend ist.

### Aufruf

```vim
:echo findfile({name}, {path})
```

### Ablauf der Suche

1. Man übergibt `{name}`, der unverändert als Suchstring genutzt wird.
2. `{path}` wird in Einträge zerlegt, getrennt durch Kommata.
3. Jeder Eintrag wird nach der oben definierten EBNF interpretiert:

   * Eintrag enthält `**` → rekursive Suche nach unten
   * Eintrag enthält `;` → Suche nach oben (Schritt für Schritt alle Parent-Verzeichnisse prüfen)
   * Normales Verzeichnis → direkte Suche
4. Falls kein Treffer gefunden wird, werden automatische Erweiterungen aus `&suffixesadd` genutzt.
5. Das erste gefundene Ergebnis wird zurückgegeben (oder eine Liste, falls `{count}` angegeben wird).

### Beispiel in Lua

```lua
---@module 'docs.findfile'
---Demonstrates how to call findfile() and open the result in Neovim.
local M = {}

function M.open_nearest_config()
  -- Find the nearest tsconfig.json, searching upward from current file
  local found = vim.fn.findfile("tsconfig.json", ".;")

  if found ~= "" then
    -- Safely open file using fnameescape()
    vim.cmd("edit " .. vim.fn.fnameescape(found))
  end
end

return M
```

---

## `matchstr()`

### Zweck

`matchstr()` extrahiert den Teil eines Strings, der einem Muster entspricht. Damit lassen sich Dateinamen, Suffixe oder Zeilenangaben aus Tokens herauslösen.

### Beispiel

```vim
:echo matchstr("foo/bar.lua:123", ".*\\.lua")
```

Beispiel in Lua:

```lua
---@module 'docs.matchstr'
---Shows how to extract filename portions using matchstr().
local M = {}

function M.extract_filename(raw)
  -- Extract only characters up to the extension
  return vim.fn.matchstr(raw, [[.*\.lua]])
end

return M
```

---

## `fnameescape()`

### Zweck

`fnameescape()` stellt sicher, dass Dateinamen korrekt an Vim-Befehle übergeben werden können, selbst wenn Leerzeichen oder Sonderzeichen enthalten sind (z. B. bei Projekten auf Windows oder bei Logs mit Sonderzeichen).

### Beispiel

```vim
:execute 'edit ' . fnameescape('my file (copy).txt')
```

Beispiel in Lua:

```lua
---@module 'docs.fnameescape'
---Demonstrates safe command execution for filenames.
local M = {}

function M.safe_open(path)
  local escaped = vim.fn.fnameescape(path)
  vim.cmd("edit " .. escaped)
end

return M
```

---

## `includeexpr`

### Zweck

`includeexpr` ist ein Ausdruck, der während der Verarbeitung von `<cfile>` oder bei Dateisuche-Operationen ausgeführt wird, um Dateinamen zu transformieren. Dies ist typisch in C/C++-Projekten, Makefiles oder bei benutzerdefinierten Suchregeln.

### Typischer Ablauf

1. Der Token unter dem Cursor wird mit `<cfile>` extrahiert.
2. Wenn `includeexpr` gesetzt ist, wird der Ausdruck evaluiert.
3. Das Ergebnis ersetzt den ursprünglichen Dateinamen für die anschließende Suche.

### Beispiel

Angenommen:

```vim
:set includeexpr=substitute(v:fname,'^<\(.*\)>$','\1','')
```

Dies würde `<stdio.h>` → `stdio.h` umwandeln.

Beispiel in Lua:

```lua
---@module 'docs.includeexpr'
---Applies 'includeexpr' manually to a filename token.
local M = {}

function M.apply_includeexpr(token)
  local expr = vim.o.includeexpr
  if expr == "" then
    return token
  end

  -- Replace v:fname references with quoted token
  local prepared = expr:gsub("v:fname", vim.fn.string(token))
  local ok, result = pcall(vim.fn.eval, prepared)

  if ok and type(result) == "string" then
    return result
  end
  return token
end

return M
```

---

## `suffixesadd`

### Zweck

`suffixesadd` enthält eine Liste von Dateiendungen, die automatisch probiert werden, wenn `findfile()` oder `:find` keinen exakten Treffer findet. Dies ist besonders nützlich für Sprachen, die implizite Endungen besitzen (C, C++, Go, Header-Dateien).

### Beispiel

```vim
:set suffixesadd=.c,.h
```

Dadurch wird aus einem Token wie `foo` automatisch `foo.c`, `foo.h` usw., wenn die Suche keinen Treffer ergibt.

### Beispiel in Lua

```lua
---@module 'docs.suffixesadd'
---Demonstrates how findfile() interacts with suffixesadd to locate files.
local M = {}

function M.search_with_suffixes(name)
  local found = vim.fn.findfile(name)

  -- If direct match fails, findfile() tries automatically:
  -- name .. ".c", name .. ".h", etc., depending on &suffixesadd.

  return found
end

return M
```

---

## Zusammenspiel der Komponenten

Typischer Ablauf in einem realen Workflow:

1. Man extrahiert den Token unter dem Cursor:
   `expand("<cfile>")`
2. Falls notwendig, wird der Token mittels `matchstr()` gereinigt (z. B. Entfernen von `:line` Suffixen).
3. Der Dateiname wird mit `includeexpr` weiterverarbeitet.
4. Man ruft `findfile()` auf, welches:

   * `path`-Einträge parst,
   * rekursiv und/oder nach oben sucht,
   * `suffixesadd` nutzt.
5. Der finale Pfad wird mit `fnameescape()` an einen Befehl übergeben.

Dieser Pipeline-Ansatz erklärt das Verhalten von `gf`, `:find` und vielen Jump-Mechanismen in Neovim.

---

## Literatur

* `:help findfile()`
* `:help file-searching`
* `:help matchstr()`
* `:help fnameescape()`
* `:help includeexpr`
* `:help 'suffixesadd'`
