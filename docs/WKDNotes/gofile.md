# gf

Man kann die interne Abfolge, die `gf` in Neovim ausführt, vollständig aufschlüsseln. Es handelt sich **nicht** um ein einzelnes Mapping, sondern um eine Kette aus C-Code, Vimscript-Hilfsfunktionen und Optionen, die zusammen das Verhalten ergeben.

## Table of content

  - [Interner Ablauf von `gf`](#interner-ablauf-von-gf)
    - [1. Tastatureingabe und Normal-Mode-Dispatch](#1-tastatureingabe-und-normal-mode-dispatch)
    - [2. Ermitteln des Dateinamens unter dem Cursor](#2-ermitteln-des-dateinamens-unter-dem-cursor)
    - [3. Auflösen des Dateipfads](#3-auflsen-des-dateipfads)
    - [4. Öffnen der Datei](#4-ffnen-der-datei)
  - [Zusammengefasst (präzise technische Pipeline)](#zusammengefasst-przise-technische-pipeline)
  - [Lua-Äquivalent zum internen Verhalten](#lua-quivalent-zum-internen-verhalten)

---

## Interner Ablauf von `gf`

### 1. Tastatureingabe und Normal-Mode-Dispatch

`gf` wird im Normalmode vom internen Dispatcher erkannt. Es ist ein **built-in Normalmode-Operator** und taucht deshalb nicht als Mapping in `:map` auf.

Intern ruft Neovim die C-Funktion auf:

```
nv_gotofile()
```

Diese liegt im ursprünglichen Vim-Code in `normal.c`.

### 2. Ermitteln des Dateinamens unter dem Cursor

`nv_gotofile()` ruft intern:

```
find_file_name_in_path()
```

Diese Funktion extrahiert den "cfile" – also denselben Wert, den man über

```vim
:echo expand('<cfile>')
```

bekommt.

Die Logik folgt exakt der Definition des `<cfile>`‐Tokens.

### 3. Auflösen des Dateipfads

Danach wird der gefundene Dateiname durch folgende Mechanismen aufgelöst:

1. **Direkt prüfen**, ob der Pfad existiert.
2. Falls nicht, wird mithilfe der Option:

```
:set path?
```

eine rekursive Suche ausgeführt.
Dies geschieht über die interne Funktion:

```
findfile()
```

oder bei mehreren möglichen Treffern:

```
find_file_in_path()
```

Beide nehmen Rücksicht auf:

* `path`
* `suffixesadd`
* `includeexpr`
* `isfname`

### 4. Öffnen der Datei

Wenn ein gültiger Pfad gefunden wurde, führt Neovim intern einen Editor-Befehl aus:

```
:edit {fname}
```

bzw. intern:

```
do_ecmd(cmd_edit, fname, ...)
```

Dies entspricht exakt:

```vim
execute 'edit' fnameescape(expand('<cfile>'))
```

---

## Zusammengefasst (präzise technische Pipeline)

```
gf
 → nv_gotofile()
   → find_file_name_in_path()           (Extrahiere <cfile>)
   → findfile() / find_file_in_path()   (Suche in cwd + 'path')
   → do_ecmd()                          (Durchführen von :edit)
```

---

## Lua-Äquivalent zum internen Verhalten

```lua
---@module 'my.gofile'
-- This module provides a Lua reimplementation of Neovim's gf behavior.
-- It resolves the file under the cursor and opens it similarly to gf.

local M = {}

---Open the file under the cursor as gf would do.
---@return nil
function M.go_file()
  -- Expand <cfile>, same token gf uses internally
  local raw = vim.fn.expand("<cfile>")

  -- Try to resolve using findfile() which respects 'path'
  local resolved = vim.fn.findfile(raw)

  -- Fallback to the raw file if nothing found through 'path'
  local target = resolved ~= "" and resolved or raw

  -- Open file with :edit
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end

return M
```

---

