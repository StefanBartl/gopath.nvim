# Auflösungs-Pipeline

> 🇬🇧 English version: [RESOLUTION.md](./RESOLUTION.md)

Dieses Dokument erklärt, wie gopath *das Ding unter dem Cursor* in *eine
geöffnete Datei an der richtigen Zeile* verwandelt — die geordnete Kette der
Resolver, den asynchronen Öffnen-Ablauf und die Fallbacks. Es ergänzt
[CACHE-DE.md](./CACHE-DE.md), das den Truncated-Pfad-Cache beschreibt, auf den
die Pipeline aufbaut.

- Orchestrator: [`lua/gopath/resolve.lua`](../lua/gopath/resolve.lua)
- Command-/Öffnen-Ablauf: [`lua/gopath/commands.lua`](../lua/gopath/commands.lua),
  [`lua/gopath/open/init.lua`](../lua/gopath/open/init.lua)
- Token-Extraktion: [`lua/gopath/providers/token.lua`](../lua/gopath/providers/token.lua)
- Separator-Behandlung: [`lua/gopath/util/cross.lua`](../lua/gopath/util/cross.lua)

---

## Inhalt

- [Der Result-Typ](#der-result-typ)
- [Phasen-Reihenfolge](#phasen-reihenfolge)
- [Token-Extraktion & Pfad-Normalisierung](#token-extraktion--pfad-normalisierung)
- [Synchroner Fast-Path vs. Async-Suche](#synchroner-fast-path-vs-async-suche)
- [Caching der Pfadsuche](#caching-der-pfadsuche)
- [Öffnen: Fensterplatzierung, Sprung, Externe](#öffnen-fensterplatzierung-sprung-externe)
- [Fallbacks bei „nicht gefunden"](#fallbacks-bei-nicht-gefunden)
- [Konfiguration & Einstiegspunkte](#konfiguration--einstiegspunkte)

---

## Der Result-Typ

Jeder Resolver liefert ein `GopathResult` (oder `nil`):

| Feld | Bedeutung |
|------|-----------|
| `path` | Absoluter Pfad, intern **forward-slash-kanonisch** |
| `range` | `{ line, col }` zum Anspringen, oder `nil` |
| `kind` | `"file"` / `"module"` / `"help"` |
| `source` | Welcher Resolver es erzeugt hat (Debugging) |
| `confidence` | `0–1`; höher gewinnt früher |
| `exists` | Ob der Pfad auf der Platte bestätigt wurde |

`confidence` und `exists` steuern die Orchestrierung: ein sicherer, existierender
Treffer wird sofort zurückgegeben; ein Ergebnis mit niedriger Konfidenz oder ohne
Existenz wird als Fallback gehalten, damit spätere Phasen es verbessern können.

---

## Phasen-Reihenfolge

`resolve_at_cursor` ([`resolve.lua`](../lua/gopath/resolve.lua)) probiert die
Resolver der Reihe nach und gibt den ersten Erfolg zurück:

| Phase | Resolver | Auslöser |
|-------|----------|----------|
| 1 | `:help`-Subjekt | Token sieht aus wie ein Vim-Help-Tag |
| 2 | `$VAR`-Env-Pfad | Token beginnt mit `$` oder `${` |
| 3 | **filetoken** | `<cfile>` unter Cursor; sucht `&path`, rtp, dann den **Cache** |
| 3.5 | **linepath** | scannt die ganze aktuelle Zeile (Stacktraces, Endung-getrieben, absolut) |
| 4 | Sprach-Pipeline | LSP → Treesitter → builtin (je Filetype, z. B. Lua `require`) |
| 5 | filetoken-Fallback | das aus Phase 3 gehaltene, unsichere/nicht-existente Ergebnis |
| 6 | rohes `<cfile>` | letzter Ausweg |

Phase 3 gibt **nur** dann sofort zurück, wenn sie eine bestätigte Datei findet
(`exists and confidence ≥ 0.6`); andernfalls hält sie das spekulative Ergebnis
zurück und lässt zuerst die Phasen 3.5–4 versuchen.

> **Wichtig:** Phasen 3 und 3.5 befragen den Truncated-Cache über
> `tailsearch.resolve_cached` — ein **reiner Cache-Lookup, nicht-blockierend**.
> Sie führen innerhalb dieser synchronen Pipeline **nie** einen Live-Walk im
> Dateisystem aus. Das hält die Pipeline instant; die (potenziell langsame)
> Live-Suche wird auf den Command-Layer verschoben (nächster Abschnitt).

---

## Token-Extraktion & Pfad-Normalisierung

Das Token unter dem Cursor kommt aus
[`providers/token.lua`](../lua/gopath/providers/token.lua) und ist schlauer als
ein bloßes `<cfile>`: es läuft über pfadartige Zeichen nach außen und bewahrt ein
abschließendes `:line:col` / `(line)`-Location-Suffix.

Plattformübergreifend wichtige Bereinigungen:

- Ein **führendes `(`**, das aus einem Markdown-Link `](pfad)` mitgezogen wird,
  wird entfernt (es ist Teil der erlaubten Zeichen, damit `path(10)`
  funktioniert — ein führendes muss daher explizit weg).
- Ein führender **Chain-Punkt** (`.foo` → `foo`) wird entfernt, aber `./`, `.\`
  (relativ) und `...` (truncated) Präfixe bleiben **erhalten**.
- Separatoren werden für alles interne Matching zu **Forward-Slashes**
  normalisiert (via [`util/cross.lua`](../lua/gopath/util/cross.lua)), und der
  finale öffenbare Pfad wird direkt vor `:edit` zurück auf **OS-native**
  Separatoren (Backslashes unter Windows) gebracht. Beide Richtungen stützen sich
  auf **lib.nvim** (`lib.nvim.cross.separators`), mit eingebauten Fallbacks,
  falls lib.nvim fehlt.

Deshalb löst ein Markdown-Link wie `[x](.\spickzettel/Learn.md)` — gemischte
Separatoren, führende Klammer, `.\`-Präfix — korrekt auf.

---

## Synchroner Fast-Path vs. Async-Suche

`commands.resolve_and_open(kind)`
([`commands.lua`](../lua/gopath/commands.lua)) orchestriert das nutzerseitige
Öffnen:

```
resolve_at_cursor()            -- schnell: nur help/env/rtp/&path/Cache
   │
   ├─ exists ≠ false ─────────▶ sofort öffnen               (Fast-Path)
   │
   └─ keine bestätigte Datei
          │ Such-Tail ableiten (aus spekulativem Pfad oder <cfile>)
          ▼
      vim.notify("Dateisuche läuft…")
      tailsearch.resolve_async(tail, …)   -- async libuv-Walk, off main loop
          │
          ├─ gefunden ───────▶ öffnen
          └─ Miss ───────────▶ Nicht-gefunden-Fallbacks
```

- Der **Fast-Path** deckt die überwältigende Mehrheit der Sprünge ab
  (existierende Dateien, rtp/`&path`-Treffer, warmer Cache) und öffnet mit
  **null Latenz und ohne Meldung**.
- Nur wenn nichts bestätigt ist, springt die **asynchrone Live-Suche** an. Sie
  zeigt eine einzelne Fortschrittsmeldung *nur dann, wenn der langsame Walk
  tatsächlich startet* (ein `on_live_start`-Hook — ein warmer Cache-Treffer
  überspringt sie) und öffnet den Buffer, sobald ein Treffer eintrifft. Die UI
  friert nie ein.

`tailsearch.resolve_async` ist selbst cache-first (instant) und durchläuft das
Dateisystem nur bei einem Miss — siehe
[CACHE-DE.md](./CACHE-DE.md#live-fallback-suche).

Der Visual-Selection-/Cursor-**Probe** (`:GopathProbe`, `<leader>pp`) nutzt
dieselbe async-Maschinerie und zeigt bei Mehrdeutigkeit einen
`vim.ui.select`-Picker.

---

## Caching der Pfadsuche

`gF` ist ein Tastendruck, deshalb ist [`util/path.lua`](../lua/gopath/util/path.lua)
darauf ausgelegt, das Dateisystem zu meiden. Die naive Suche — jeden Kandidaten
unter jedem runtimepath-Eintrag stat'en — kostet ~200 `fs_stat`-Aufrufe pro
Lookup; unter Windows (besonders mit AV/EDR-Scanning) gemessene **~9,7 ms pro
Miss** bei 50 runtimepath-Einträgen.

Misses sind der Normalfall: jedes gepunktete Token unter dem Cursor läuft in die
Kette, die meisten Aufrufe lösen also nichts auf und zahlten diesen Walk voll.

Stattdessen wird jede Suchwurzel **einmalig** per `fs_scandir` gelesen und nach
den direkt darin liegenden Namen indiziert. Ein Kandidat wird nur in einer
Wurzel gestat'et, deren Index sein erstes Pfadsegment enthält — ein unbekanntes
Token wird also allein per Hash-Lookup verworfen:

| Lookup | ohne Cache | indiziert |
| --- | --- | --- |
| Modul-Miss (2 Kandidaten) | 9,7 ms | 0,09 ms |
| Filetoken-Miss | 5,3 ms | 0,05 ms |
| volle `search_module`-Kette, Miss | 11,3 ms | 0,31 ms |

Die **Suchreihenfolge bleibt unverändert** — der Index überspringt nur Proben,
die ohnehin nicht hätten treffen können; die Ergebnisse sind identisch zum
ungecachten Walk.

Da nur das *erste* Segment indiziert wird, braucht eine neue Datei in einem
bereits bekannten Verzeichnis gar keine Invalidierung. Nur ein brandneuer
Top-Level-Eintrag kann von einem veralteten Index verdeckt werden, und dafür
greifen vier Signale:

- Installieren/Laden eines Plugins ändert den runtimepath, auf den die Caches
  schlüsseln
- gopaths Create-on-missing ruft `path.invalidate_caches()` direkt auf
- ein `BufWritePost`-Autocmd tut dasselbe für in dieser Session geschriebene
  Buffer (siehe [BINDINGS.md](./BINDINGS.md#autocommands))
- eine TTL von 30 s fängt Änderungen ab, die komplett außerhalb von Neovim
  passieren

---

## Öffnen: Fensterplatzierung, Sprung, Externe

[`open/init.lua`](../lua/gopath/open/init.lua) übernimmt das eigentliche Öffnen:

1. **Externe Dateien** (Bilder, PDFs, …) werden über `gopath.external` an den
   System-Opener übergeben.
2. Ein nicht existierender Pfad wird zur Anlage angeboten via
   [`gopath.create`](../lua/gopath/create.lua) (`create_on_missing`, siehe
   unten), statt nur `File not found` zu melden. Bei Bestätigung wird die
   Datei (+ übergeordnete Verzeichnisse) angelegt und `M.open` ruft sich mit
   `exists = true` erneut auf.
3. Zuerst die Fensterplatzierung — `edit` / `split` / `vsplit` / `tabnew` —
   dann wird die Datei mit einem **OS-nativen** Pfad geöffnet (lib.nvim).
4. Trägt das Ergebnis ein `range`, springt der Cursor auf `line:col` und zentriert
   (`normal! zz`).

---

## Fallbacks bei „nicht gefunden"

Liefert die Auflösung einen Pfad, der nicht existiert, probiert `commands` der
Reihe nach:

1. **Fuzzy-Alternate** — Levenshtein-Ähnlichkeit gegen Dateien im selben
   Verzeichnis ([`alternate/`](../lua/gopath/alternate)), gesteuert über
   `alternate.similarity_threshold`.
2. **Anlegen bei Fehlen** — scheitert auch das, fragt `gopath.open` (Button-
   Dialog über lib.nvim's `ui.kit.confirm`, mit `vim.ui.select`-Fallback wenn
   lib.nvim fehlt), ob die Datei angelegt werden soll. Siehe
   [`gopath.create`](../lua/gopath/create.lua) und den `create_on_missing`
   Config-Block. Opt-out mit `create_on_missing.enable = false`, oder die
   Nachfrage überspringen mit `confirm = false`. Das eigene Keymap `gC` /
   `:GopathCheck` prüft die Existenz direkt (ohne vorherigen Öffnungsversuch)
   und bietet die Anlage immer an — unabhängig vom `enable`-Opt-out.

Früher gab es einen dritten Fallback, der das nächstgelegene existierende
Vorfahren-*Verzeichnis* des nicht aufgelösten Pfads als Buffer öffnete —
entfernt, weil ein Verzeichnis sich nicht wie eine Datei in einem
Neovim-Buffer öffnen lässt (man landete kommentarlos in netrw). Existiert für
den aufgelösten Pfad ein Vorfahren-Verzeichnis und ist
[filetree.nvim](https://github.com/StefanBartl/filetree.nvim) installiert und
eingerichtet, bietet der Anlage-Dialog stattdessen einen zweiten Button,
**„Open in filetree"**: er setzt Neovims cwd auf dieses Verzeichnis und
verwurzelt/fokussiert dort filetree.nvims Baum. Der Button erscheint nur,
wenn beide Bedingungen erfüllt sind — sonst ist der Dialog nur Create/Cancel.

---

## Konfiguration & Einstiegspunkte

- Öffentliche API: `require("gopath").resolve(opts)` liefert ein `GopathResult`,
  ohne etwas zu öffnen; `require("gopath").commands` stellt die
  Öffnen-/Kopieren-/Debug-Aktionen für eigene Keymaps bereit.
- Modus-Wahl (`mode = "hybrid" | "lsp" | "treesitter" | "builtin"`) und die
  Resolver-`order` sind in der [Haupt-README](../README.md#configuration)
  dokumentiert.
- Schalter pro Phase: `linepath.enable`, `tailsearch.enable`,
  `env_variable_resolution.enable`, `alternate.enable` und die
  `languages`-Tabelle.

Siehe [CACHE-DE.md](./CACHE-DE.md) für den Cache hinter den Phasen 3/3.5 und dem
async-Fallback.
