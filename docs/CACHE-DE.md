# Filesystem-Cache & Auflösung abgeschnittener Pfade

> 🇬🇧 English version: [CACHE.md](./CACHE.md)

Dieses Dokument beschreibt den **Filesystem-Cache**, der die schnelle Auflösung
*abgeschnittener* (truncated) und *partieller* Pfade ermöglicht — also genau der
Pfade, die aus Fehlermeldungen, Stacktraces und Logs stammen:

```
...a/Local/nvim/lua/config/neotree/open/filemanager/win.lua:62
…/lua/config/init.lua
neo-tree/ui/renderer.lua
```

Der Cache beantwortet die Frage „welche echte Datei auf der Platte ist mit
diesem Fragment gemeint?" — **ohne den Editor einzufrieren**. Dazu wird das
Dateisystem einmal im Hintergrund gescannt und der vollständige absolute Pfad
aus dem sichtbaren Ende (Tail) rekonstruiert.

- Code: [`lua/gopath/truncated/cache.lua`](../lua/gopath/truncated/cache.lua),
  [`lua/gopath/truncated/finder.lua`](../lua/gopath/truncated/finder.lua),
  [`lua/gopath/truncated/init.lua`](../lua/gopath/truncated/init.lua)
- Lookup-Anbindung: [`lua/gopath/resolvers/common/tailsearch.lua`](../lua/gopath/resolvers/common/tailsearch.lua)

---

## Inhalt

- [Warum ein Cache?](#warum-ein-cache)
- [Das Gesamtbild](#das-gesamtbild)
- [Was wird gescannt, und wann](#was-wird-gescannt-und-wann)
- [Wie der Scan funktioniert (nicht-blockierend)](#wie-der-scan-funktioniert-nicht-blockierend)
- [Speicherung: In-Memory + auf Disk](#speicherung-in-memory--auf-disk)
- [Matching: den vollen Pfad aus dem Tail rekonstruieren](#matching-den-vollen-pfad-aus-dem-tail-rekonstruieren)
- [Live-Fallback-Suche](#live-fallback-suche)
- [Refresh-Lebenszyklus](#refresh-lebenszyklus)
- [Konfiguration](#konfiguration)
- [Befehle](#befehle)
- [Tuning & Fehlersuche](#tuning--fehlersuche)
- [Design-Notizen & Ideen](#design-notizen--ideen)

---

## Warum ein Cache?

Einen abgeschnittenen Pfad aufzulösen bedeutet, im Dateisystem eine Datei zu
suchen, deren Pfad *auf das sichtbare Fragment endet*. Macht man diese Suche
live im Main-Thread (z. B. mit `vim.fs.find`), werden große Verzeichnisbäume
synchron durchlaufen und **die UI friert mehrere Sekunden ein** (ein gut
gefülltes `nvim-data`-Verzeichnis unter Windows reicht schon für einen
mehrsekündigen Freeze).

Der Cache löst das, indem die Traversierung **einmal im Hintergrund** bezahlt
wird; jeder weitere Lookup wird dann in deutlich unter 10 ms aus dem Speicher
beantwortet.

---

## Das Gesamtbild

```
                         ┌──────────────────────────────┐
   setup() ───────────▶  │  build_async()  (Hintergrund) │
                         │  bounded libuv scandir-Walk   │
                         └───────────────┬──────────────┘
                                         │ Dateipfade
                                         ▼
   JSON auf Disk  ◀────────────  In-Memory-Index  (state.paths)
   (stdpath cache)                       ▲
                                         │ M.search(tail)
   Cursor auf truncated Pfad ──▶ cache_lookup(tail)  ──▶ voller absoluter Pfad
                                         │ (Miss)
                                         ▼
                              async Live-Finder-Walk
                              („Dateisuche läuft…")
```

1. Beim Start wird der Cache **von Disk geladen** (instant) und, falls veraltet,
   **im Hintergrund neu gebaut**.
2. Landet der Cursor auf einem truncated/partiellen Pfad, fragt der Resolver
   zuerst den **In-Memory-Cache** (instant).
3. Bei einem Cache-Miss folgt eine **asynchrone Live-Suche**, die eine
   Fortschrittsmeldung zeigt und die Datei öffnet, sobald sie gefunden ist.

---

## Was wird gescannt, und wann

Die Scan-Roots werden in [`cache.setup()`](../lua/gopath/truncated/cache.lua)
gewählt. Wird `truncated.cache_roots` nicht gesetzt, werden sie automatisch
erkannt (bewusst konservativ — es wird **kein** ganzes Laufwerk standardmäßig
indexiert):

| Root | Quelle |
|------|--------|
| Arbeitsverzeichnis | `vim.fn.getcwd()` |
| Neovim-Config | `vim.fn.stdpath("config")` |
| Neovim-Data (Plugins) | `vim.fn.stdpath("data")` |
| Neovim-Cache | `vim.fn.stdpath("cache")` |
| Git-Repository-Root | `git rev-parse --show-toplevel` (falls im Repo) |

Jeder Root wird bis zu `truncated.max_depth` Ebenen tief durchlaufen (Default
**6**), wobei `truncated.excluded_dirs` (`.git`, `node_modules`, `target`,
`build`, `.cache`, …) übersprungen werden.

Ein Build wird ausgelöst:

- **Einmal beim Setup**, ~2 s verzögert, nur wenn der Cache fehlt oder veraltet
  ist (siehe [Refresh-Lebenszyklus](#refresh-lebenszyklus)).
- **Periodisch**, alle `cache_refresh_interval` Sekunden, wenn veraltet.
- **Beim Speichern** (optional), wenn `auto_rebuild_on_save = true`, entprellt.
- **Manuell**, über `:Gopath cache build`.

> ⚠️ Der Build wird in [`lua/gopath/init.lua`](../lua/gopath/init.lua) per
> `cache.setup{…}` verdrahtet. Ohne diesen Aufruf bleiben die Scan-Roots leer
> und der Cache indexiert nichts — der Cache ist also nur aktiv, wenn
> `truncated.enable = true` (Default).

---

## Wie der Scan funktioniert (nicht-blockierend)

Die Traversierung ist eine **Work-Queue mit begrenzter Nebenläufigkeit** über
libuvs asynchrones `fs_scandir` (`scan_roots_bounded` in `cache.lua`):

- Eine Queue hält `{ dir, depth }`-Einträge; maximal `max_concurrency` (Default
  **16**) `fs_scandir`-Operationen sind gleichzeitig aktiv.
- Unterverzeichnisse werden zurück in die Queue gelegt statt sofort rekursiv
  betreten zu werden, sodass die Zahl offener Verzeichnis-Handles unabhängig von
  der Baumgröße begrenzt bleibt. Das verhindert `EMFILE`/Threadpool-Erschöpfung
  bei riesigen Bäumen.
- Der gesamte Walk läuft außerhalb des Main-Loops — Neovim bleibt während des
  Baus reaktionsfähig.

Der Live-Fallback-Finder nutzt **denselben** bounded libuv-Walk
(`finder.find_async`) mit Early-Exit, sobald genug Treffer gefunden sind, und
braucht daher keine externen Tools (`fd`/`rg` werden nur vom synchronen
`finder.find` verwendet).

---

## Speicherung: In-Memory + auf Disk

- **In-Memory:** `state.paths` — ein flaches Array aller gefundenen absoluten
  Dateipfade. Darin wird beim Lookup gesucht.
- **Auf Disk:** eine versionierte JSON-Datei unter
  `stdpath("cache") .. "/gopath_fs_cache.json"` mit `paths`, `last_built`,
  `scan_roots` und `version`. Sie wird nach jedem Build neu geschrieben und beim
  Start geladen, sodass schon der erste Lookup einer Sitzung schnell ist.

---

## Matching: den vollen Pfad aus dem Tail rekonstruieren

Das ist das Herzstück und setzt genau deine Idee um: *„finde, wo genug vom Pfad
übereinstimmt, und baue den fehlenden linken Teil wieder auf."*

Ein truncated Token wird zunächst auf einen sauberen **Tail** reduziert
(Ellipsis/Quotes/`:line` entfernt, Separatoren zu `/` normalisiert). Der Lookup
probiert dann zunehmend kürzere **Suffix-Kandidaten**, längster zuerst
(`tailsearch.cache_lookup` → `suffix_candidates`):

```
tail = "...a/Local/nvim/lua/config/neotree/open/filemanager/win.lua"

Kandidaten (längster → kürzester, bis max_components):
  lua/config/neotree/open/filemanager/win.lua
  config/neotree/open/filemanager/win.lua
  neotree/open/filemanager/win.lua
  open/filemanager/win.lua
  filemanager/win.lua
  win.lua
```

Für jeden Kandidaten matcht `cache.search` jeden indexierten Pfad mit zwei
Strategien (case-insensitive, `\`→`/` normalisiert):

1. **Exaktes Tail-(Suffix-)Match** — der indexierte Pfad *endet auf* den
   Kandidaten. Genau das rekonstruiert den absoluten linken Teil: der volle
   Treffer `C:/Users/me/AppData/Local/nvim/lua/config/.../win.lua` endet auf
   `lua/config/.../win.lua`, womit das fehlende Präfix
   `C:/Users/me/AppData/Local/nvim` wiederhergestellt ist.
2. **Sequentielles Segment-Match** — jedes Segment des Kandidaten kommt **in
   Reihenfolge** im indexierten Pfad vor (nicht zwingend zusammenhängend). Das
   ist die „≥ N aufeinanderfolgende Ordner"-Heuristik: sie toleriert ein
   partielles führendes Segment (z. B. das `...a`-Fragment links von `AppData`).

Der **längste** Kandidat mit Treffern gewinnt, damit das Ergebnis so spezifisch
wie möglich ist und wir nie auf ein bloßes `win.lua` zurückfallen, das die halbe
Platte matcht. Matchen mehrere Dateien den Sieger-Kandidaten, wird der
**kürzeste** absolute Pfad bevorzugt (`pick_best`), und Befehle können einen
`vim.ui.select`-Picker zeigen (`ask_on_ambiguous`).

Für die interaktive Auswahl werden Kandidaten zusätzlich nach
Dateinamen-Ähnlichkeit sortiert (Levenshtein, `truncated.similarity_threshold`)
— siehe [`alternate/helpers/matcher.lua`](../lua/gopath/alternate/helpers/matcher.lua).

---

## Live-Fallback-Suche

Bei einem Cache-Miss (Kaltstart, Datei außerhalb der gescannten Roots oder tiefer
als `max_depth`) blockiert die Auflösung **nicht**. Der Command-Layer:

1. zeigt `"[gopath] Dateisuche läuft…"`,
2. startet `finder.find_async` (async libuv-Walk, außerhalb des Main-Loops),
3. öffnet den Buffer, sobald ein Treffer da ist, oder meldet „kein Treffer".

Siehe [RESOLUTION-DE.md](./RESOLUTION-DE.md) für die Einbettung in die volle
Pipeline.

---

## Refresh-Lebenszyklus

| Zustand | Prüfung | Aktion |
|---------|---------|--------|
| Nie gebaut | `last_built == nil` | Build beim Setup (~2 s verzögert) |
| Veraltet | `os.time() - last_built > max_cache_age` | Hintergrund-Rebuild |
| Periodisch | alle `cache_refresh_interval` s | Rebuild falls veraltet |
| Beim Speichern | `auto_rebuild_on_save` | entprellter Rebuild |

`needs_refresh(max_age)` und `start_periodic_refresh(interval)` setzen das um.
Gleichzeitige Builds werden durch ein `state.building`-Guard verhindert.

---

## Konfiguration

```lua
require("gopath").setup({
  truncated = {
    enable                 = true,   -- Hauptschalter für Cache + Truncated-Auflösung
    use_cache              = true,   -- In-Memory-Cache vor der Live-Suche befragen
    cache_refresh_interval = 600,    -- Sekunden zwischen periodischen Prüfungen
    max_cache_age          = 3600,   -- Sekunden, bis der Cache als veraltet gilt
    live_search_fallback   = true,   -- Live-Suche als Fallback bei Cache-Miss
    similarity_threshold   = 75,     -- 0–100; Dateinamen-Ähnlichkeit zur Auswahl
    cache_roots            = nil,    -- nil = Auto-Erkennung (cwd, stdpaths, git root)
    max_depth              = 6,      -- maximale Verzeichnistiefe pro Root
    excluded_dirs          = { ".git", "node_modules", "target", "build", ".cache" },
    auto_rebuild_on_save   = false,  -- (entprellter) Rebuild bei BufWritePost
  },
})
```

Verwandte Stellschrauben liegen unter `tailsearch` (Suffix-Länge,
Ambiguitäts-Prompt, Ergebnis-Limit) — siehe die
[Haupt-README](../README.md#configuration).

---

## Befehle

| Befehl | Alias | Wirkung |
|--------|-------|---------|
| `:Gopath cache build` | `:GopathCacheBuild` | Cache jetzt neu bauen (Hintergrund) |
| `:Gopath cache info` | `:GopathCacheInfo` | Anzahl indexierter Dateien, letzter Build, Veraltung |
| `:Gopath cache add-root <dir>` | `:GopathCacheAddRoot <dir>` | Scan-Root hinzufügen und neu bauen |

`g?` (`:GopathDebug`) gibt zusätzlich Cache-Statistiken für den Pfad unter dem
Cursor aus.

---

## Tuning & Fehlersuche

- **Truncated Pfad löst nicht auf.** `:Gopath cache info` ausführen. Ist die
  Dateizahl 0, ist der Cache noch nicht gebaut (kurz nach dem Start warten oder
  `:Gopath cache build`). Liegt die Datei außerhalb der Default-Roots, mit
  `:Gopath cache add-root <dir>` ergänzen oder `truncated.cache_roots` setzen.
- **Auflösung findet die falsche Datei.** `tailsearch.max_components` erhöhen,
  damit zuerst ein längeres, spezifischeres Suffix probiert wird, und/oder
  `similarity_threshold` anheben.
- **Build fühlt sich schwer an.** `max_depth` senken, `excluded_dirs` erweitern
  oder `cache_roots` auf die wirklich relevanten Verzeichnisse festlegen.
- **Weiteres Netz gewünscht.** `cache_roots` explizit setzen (z. B. ein ganzes
  Projektlaufwerk) — ein größerer Index bedeutet aber langsamere Builds und eine
  größere JSON-Datei.

---

## Design-Notizen & Ideen

- Der Cache ist bewusst eine **flache Pfadliste** mit String-Matching statt
  Trie/DB: trivial zu serialisieren, schnell genug für Zehntausende Einträge und
  leicht nachvollziehbar.
- Der Zwei-Strategien-Matcher setzt die Idee „genug Überlappung → linken Teil
  rekonstruieren" bereits um. Eine natürliche Erweiterung wäre ein expliziter
  **Überlappungs-Score** (z. B. *N aufeinanderfolgende Segmente* oder *1 Segment
  + Laufwerksname*) mit konfigurierbarem Minimum, etwa als
  `truncated.min_overlap`. Die Suffix-/Sequenz-Strategien sind die aktuelle
  Annäherung daran.
