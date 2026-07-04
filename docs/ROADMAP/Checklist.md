# Checklisten für Lua/Neovim-Architektur, Performance und Codierungsregeln

## Table of content

- [Checklisten für Lua/Neovim-Architektur, Performance und Codierungsregeln](#checklisten-fr-luaneovim-architektur-performance-und-codierungsregeln)
  - [Hinweise zur Anwendung](#hinweise-zur-anwendung)
  - [Schnell-Check (10 Punkte, vor jedem Merge)](#schnell-check-10-punkte-vor-jedem-merge)
    - [Bonuspunkt: Custom `lib`-Modul nutzen](#bonuspunkt-custom-lib-modul-nutzen)
  - [PR-Review-Checkliste (Detail)](#pr-review-checkliste-detail)
    - [1. Sicherheit und Fehlerbehandlung](#1-sicherheit-und-fehlerbehandlung)
    - [2. Modularität und Struktur](#2-modularitt-und-struktur)
    - [3. Buffer-/Window-Management (Neovim)](#3-buffer-window-management-neovim)
    - [4. UI-State-Management](#4-ui-state-management)
    - [5. Dokumentation und Annotationen](#5-dokumentation-und-annotationen)
    - [6. Testbarkeit und Lesbarkeit](#6-testbarkeit-und-lesbarkeit)
    - [7. Tooling](#7-tooling)
  - [Coding-Checkliste (beim Implementieren)](#coding-checkliste-beim-implementieren)
    - [Funktionales Programmieren in Lua](#funktionales-programmieren-in-lua)
      - [1. Dateiverarbeitung](#1-dateiverarbeitung)
      - [2. Netzwerk- und Protokollverarbeitung](#2-netzwerk-und-protokollverarbeitung)
      - [3. Datenkompression und Kodierung](#3-datenkompression-und-kodierung)
      - [4. Streaming-Transformationen](#4-streaming-transformationen)
      - [5. Datenintegration und ETL-Prozesse](#5-datenintegration-und-etl-prozesse)
      - [6. Debugging & Logging](#6-debugging-logging)
      - [7. Parallelisierung / Remote Processing](#7-parallelisierung-remote-processing)
    - [A. Strings und Tabellen](#a-strings-und-tabellen)
    - [B. Performance-Quickwins](#b-performance-quickwins)
      - [Performance-Checks](#performance-checks)
    - [C. Neovim-API sicher verwenden](#c-neovim-api-sicher-verwenden)
    - [D. State- und Datenmodelle](#d-state-und-datenmodelle)
    - [E. Garbage-Collector bewusst steuern](#e-garbage-collector-bewusst-steuern)
    - [F. Lazy-Loading und On-Demand-Konfiguration](#f-lazy-loading-und-on-demand-konfiguration)
  - [Architektur-Checkliste](#architektur-checkliste)
    - [C/C++ nativen Quellcode](#cc-nativen-quellcode)
  - [Anti-Pattern-Check](#anti-pattern-check)
  - [Import- und Dateistruktur-Check](#import-und-dateistruktur-check)
  - [Performance-Spickzettel (zum Abhaken bei Hotpaths)](#performance-spickzettel-zum-abhaken-bei-hotpaths)
  - [Sortieralgorithmen (Auswahl, Implementierung, Review) mit Prioritäten](#sortieralgorithmen-auswahl-implementierung-review-mit-prioritten)
    - [Eingabe- und Randbedingungen](#eingabe-und-randbedingungen)
    - [Algorithmuswahl (Daumenregeln)](#algorithmuswahl-daumenregeln)
    - [Komplexität und Speicher](#komplexitt-und-speicher)
    - [Implementierungsdetails](#implementierungsdetails)
    - [Tests und Verifikation](#tests-und-verifikation)
    - [Dokumentation](#dokumentation)
  - [Einfüge-/Lösch-/Update-/Such-Algorithmen und verwandte Datenstruktur-Operationen](#einfge-lsch-update-such-algorithmen-und-verwandte-datenstruktur-operationen)
    - [Anforderungen und Randbedingungen](#anforderungen-und-randbedingungen)
    - [Struktur-/Algorithmuswahl (Daumenregeln)](#struktur-algorithmuswahl-daumenregeln)
    - [Arrays/Vektoren (dynamisch)](#arraysvektoren-dynamisch)
    - [Verkettete Listen (Singly/Doubly)](#verkettete-listen-singlydoubly)
    - [Hash-Tabellen](#hash-tabellen)
    - [Balancierte Suchbäume (AVL/Red-Black)](#balancierte-suchbume-avlred-black)
    - [Heaps/Priority Queues](#heapspriority-queues)
    - [B-/B+-Bäume (Block/Externspeicher)](#b-b-bume-blockexternspeicher)
    - [Skip-Lists](#skip-lists)
    - [Tries/Radix-Bäume](#triesradix-bume)
    - [Bitset/Bloom/Cuckoo Filter](#bitsetbloomcuckoo-filter)
    - [Union-Find (Disjoint Set)](#union-find-disjoint-set)
    - [Segment-/Fenwick-/Interval-Bäume](#segment-fenwick-interval-bume)
    - [Sequenzstrukturen (Rope, Piece Table, Gap Buffer)](#sequenzstrukturen-rope-piece-table-gap-buffer)
    - [Lösch-Strategien](#lsch-strategien)
    - [Parallelität und Nebenläufigkeit](#parallelitt-und-nebenlufigkeit)
    - [Persistenz/Immutabilität](#persistenzimmutabilitt)
    - [Tests, Invarianten, Benchmarks](#tests-invarianten-benchmarks)
    - [Dokumentation und Verträge](#dokumentation-und-vertrge)
  - [Zeit- und Platzkomplexität (Notation, Kommunikation, Nachweis) mit Prioritäten](#zeit-und-platzkomplexitt-notation-kommunikation-nachweis-mit-prioritten)
    - [Notationsdisziplin](#notationsdisziplin)
    - [Aussagekraft und Annahmen](#aussagekraft-und-annahmen)
    - [Kommunikation und Nachweis](#kommunikation-und-nachweis)
    - [Qualitätssicherung](#qualittssicherung)
  - [Bitoperationen](#bitoperationen)
    - [Plattform/Eignung (Kurz-Check)](#plattformeignung-kurz-check)
    - [Allgemeine Leitlinien](#allgemeine-leitlinien)
    - [Zwei Werte ohne temporäre Variable tauschen (XOR-Swap)](#zwei-werte-ohne-temporre-variable-tauschen-xor-swap)
    - [Einzigartiges Element in Duplikaten finden (alle anderen exakt zweimal)](#einzigartiges-element-in-duplikaten-finden-alle-anderen-exakt-zweimal)
    - [Unterschiede zwischen zwei Werten (Maske/LSB isolieren)](#unterschiede-zwischen-zwei-werten-maskelsb-isolieren)
    - [Bit-Parität (gerade/ungerade Anzahl gesetzter Bits)](#bit-paritt-geradeungerade-anzahl-gesetzter-bits)
    - [XOR-Linked-List](#xor-linked-list)
    - [XOR-Range-Trick (XOR von 1..n bzw. L..R)](#xor-range-trick-xor-von-1n-bzw-lr)
    - [Bitmasken mit XOR zum gezielten Flippen](#bitmasken-mit-xor-zum-gezielten-flippen)
  - [Zusammenfassende Anti-Pattern-Checks für Bittricks](#zusammenfassende-anti-pattern-checks-fr-bittricks)
  - [Reviewer-Notizen (Vorlage)](#reviewer-notizen-vorlage)
  - [Referenzen](#referenzen)

---

## Hinweise zur Anwendung

  1. Erst Schnell-Check ausfüllen.
  2. Bei Abweichungen die Detail-Abschnitte nutzen und konkrete Punkte abhaken.
  3. Für Hotpaths zusätzlich den Performance-Spickzettel prüfen.
  4. Bei Neovim-Fenster/Buffer-Code immer Handle-Validierung doppelt prüfen, insbesondere in asynchronen Callbacks.

Referenz: [Arch\&Coding-Regeln](./Arch&Coding-Regeln.md)

## Schnell-Check (10 Punkte, vor jedem Merge)

| Status | Prüfschritt                | Kurzbeschreibung                                           | Priorität      |
| ------ | -------------------------- | ---------------------------------------------------------- | -------------- |
| `[ ]`  | Fehlerbehandlung vorhanden | pcall/xpcall oder zentraler Wrapper, keine stillen Fehler  | 🔴 KRITISCH     |
| `[ ]`  | Type Guards                | type(...) vor API-Zugriff; nil-Check                       | 🔴 KRITISCH     |
| `[ ]`  | Buffer/Window validieren   | nvim_*_is_valid() vor jeder Operation                      | 🔴 KRITISCH     |
| `[ ]`  | Keine globalen States      | Zustände modul-intern, Getter/Setter, DI                   | 🔴 KRITISCH     |
| `[ ]`  | Single Responsibility      | Modul/Funktion hat eine Verantwortung                      | 🔴 KRITISCH     |
| `[ ]`  | UI-Cleanup                 | cleanup_all() schließt Fenster/Buffer sicher               | 🟡 EMPFOHLEN    |
| `[ ]`  | Performance-Hotspots       | Strings via table.concat, Tabellen vorreservieren          | 🟡 EMPFOHLEN    |
| `[ ]`  | Annotationen vollständig   | @module, @class, @param, @return, Aliase                   | 🟡 EMPFOHLEN    |
| `[ ]`  | Testbarkeit                | Pure Functions, DI, Snapshot/Restore                       | 🟡 EMPFOHLEN    |
| `[ ]`  | Import-Reihenfolge         | System → Debug → Utils → State → UI → Controller → Keymaps | 🟢 NICE-TO-HAVE |

### Bonuspunkt: Custom `lib`-Modul nutzen

**WICHTIG**:
Verwende die custom `/nvim/lua/lib/**/**.lua`-Library, insbesondere:
    - `lib.notify` anstatt `vim.notify()` oder `print()`
    - `lib.map` anstatt `vim.keymap.set`; respektive `lib.usercmd`, `lib.autocmd`, `lib.augroup`
    - `lib.cross_plattform` / `lib.cross`: Alle Module müssen entweder Cross-Plattform sein oder eine alternative innerhalb des Moduls bereitstellen
    - `lib.hover_select`: Ein wrapper der vim.select ersetzt und bei kontinuierlicher Verwendung eine konsequente UI ermöglicht
    - `lib.lazy` ermöglich die Vermeidung unnötiger Ladelast
    - `lib.memo` ermöglicht Standardisierte Memoization
    - uvm...

---

## PR-Review-Checkliste (Detail)

### 1. Sicherheit und Fehlerbehandlung

| Status | Prüfschritt          | Details                                                                             | Priorität  |
| ------ | -------------------- | ----------------------------------------------------------------------------------- | ---------- |
| `[ ]`  | pcall/xpcall         | 🔴 Kritische Calls kapseln; zentraler safe_call(fn, …) erlaubt konsistente Rückgaben | 🔴 KRITISCH |
| `[ ]`  | Strukturierte Fehler | Konsistente Fehlertypen wie InvalidStateError, InvalidQueryError                    | 🔴 KRITISCH |
| `[ ]`  | Explizite Rückgaben  | true/false und optionales Fehlerobjekt; kein notify im Low-Level                    | 🔴 KRITISCH |
| `[ ]`  | Guards vor API       | type(...) und nil-Checks vor vim.api/vim.fn Zugriffen                               | 🔴 KRITISCH |

### 2. Modularität und Struktur

| Status | Prüfschritt           | Details                                               | Priorität      |
| ------ | --------------------- | ----------------------------------------------------- | -------------- |
| `[ ]`  | Single Responsibility | Modul erfüllt genau eine Verantwortung                | 🔴 KRITISCH     |
| `[ ]`  | Keine Globals         | Kein _G.*; State in Modul, Zugriff über Getter/Setter | 🔴 KRITISCH     |
| `[ ]`  | Reine Funktionen      | Wo möglich pure functions, keine Seiteneffekte        | 🟡 EMPFOHLEN    |
| `[ ]`  | Interne Helfer lokal  | Nicht exportierte Funktionen lokal halten             | 🟡 EMPFOHLEN    |
| `[ ]`  | Tools/Registry        | Werkzeuge zentral registriert (Registry-Pattern)      | 🟢 NICE-TO-HAVE |
| `[ ]`  | Config                | Einen `/config` Folder mit `/config/DEFAULTS.lua`     | 🟢 NICE-TO-HAVE |

### 3. Buffer-/Window-Management (Neovim)

| Status | Prüfschritt          | Details                                                       | Priorität   |
| ------ | -------------------- | ------------------------------------------------------------- | ----------- |
| `[ ]`  | Handle zuerst binden | local buf/win = …; danach prüfen; erst dann nutzen            | 🔴 KRITISCH  |
| `[ ]`  | Gültigkeit prüfen    | nvim_buf_is_valid / nvim_win_is_valid vor jedem API-Call      | 🔴 KRITISCH  |
| `[ ]`  | Einheitliche API     | open_window, close_window, configure, apply_layout konsistent | 🟡 EMPFOHLEN |
| `[ ]`  | Cleanup              | cleanup_all() löscht temporäre Buffer und schließt Windows    | 🟡 EMPFOHLEN |
| `[ ]`  | Race Conditions      | Defer-Callbacks validieren Handles erneut                     | 🔴 KRITISCH  |

### 4. UI-State-Management

| Status | Prüfschritt      | Details                                               | Priorität      |
| ------ | ---------------- | ----------------------------------------------------- | -------------- |
| `[ ]`  | Zentraler State  | ui_state mit Getter/Setter statt direktem Feldzugriff | 🟡 EMPFOHLEN    |
| `[ ]`  | Snapshot/Restore | Zustands-Snapshots für Tests/Undo verfügbar           | 🟢 NICE-TO-HAVE |

### 5. Dokumentation und Annotationen

| Status | Prüfschritt          | Details                                                                         | Priorität      |
| ------ | -------------------- | ------------------------------------------------------------------------------- | -------------- |
| `[ ]`  | Kopf-Tags            | Datei beginnt mit @module, @class, @brief, @description                         | 🟡 EMPFOHLEN    |
| `[ ]`  | Funktions-Tags       | Jede public-Funktion mit @param, @return, ggf. @async; konsistente Typen/Aliase | 🟡 EMPFOHLEN    |
| `[ ]`  | Aliase/Typen         | Eigene Aliase (@alias) und Felder (@field) statt Inline-Monster                 | 🟡 EMPFOHLEN    |
| `[ ]`  | Kommentar-Konvention | Optionales # in @alias/@return gemäß Lua LS Hinweise                            | 🟢 NICE-TO-HAVE |

### 6. Testbarkeit und Lesbarkeit

| Status | Prüfschritt          | Details                                         | Priorität      |
| ------ | -------------------- | ----------------------------------------------- | -------------- |
| `[ ]`  | DI statt Hard-Wiring | Abhängigkeiten injizieren (API-Clients, Config) | 🟡 EMPFOHLEN    |
| `[ ]`  | Pure Functions       | Berechnungslogik ohne Seiteneffekte             | 🟡 EMPFOHLEN    |
| `[ ]`  | Test-Entry           | Separater Test-Entrypoint (tools/_test) möglich | 🟢 NICE-TO-HAVE |

### 7. Tooling

| Status | Prüfschritt      | Details                                              | Priorität   |
| ------ | ---------------- | ---------------------------------------------------- | ----------- |
| `[ ]`  | Lua LS Settings  | diagnostics.globals=vim; workspace.library; hints on | 🟡 EMPFOHLEN |
| `[ ]`  | Formatter/Linter | stylua, luacheck im CI                               | 🟡 EMPFOHLEN |

## Coding-Checkliste (beim Implementieren)

[reduce-reuse-recycle Prinzip beachten](./MyNotes/Checklists/Lua/Referenzen/reduce-reuse-recycle.md)

**WICHTIG**:
Verwende die custom `/nvim/lua/lib/**/**.lua`-Library, insbesondere:
    - `lib.notify` anstatt `vim.notify()` oder `print()`
    - `lib.map` anstatt `vim.keymap.set`; respektive `lib.usercmd`, `lib.autocmd`, `lib.augroup`
    - `lib.cross_plattform` / `lib.cross`: Alle Module müssen entweder Cross-Plattform sein oder eine alternative innerhalb des Moduls bereitstellen
    - `lib.hover_select`: Ein wrapper der vim.select ersetzt und bei kontinuierlicher Verwendung eine konsequente UI ermöglicht
    - `lib.lazy` ermöglich die Vermeidung unnötiger Ladelast
    - `lib.memo` ermöglicht Standardisierte Memoization
    - uvm...

---

### Funktionales Programmieren in Lua

[filter-sinks-pumps](../../../../WKDBooks/Development/wkdbook-Lua/Literatur/Lua-Programming-Gems/functional-programming/filter-sinks-pumps.md)

Wenn man folgende Aufgaben auf die Filter/Sources/Sinks/Pumps-Architektur abbildet, kann man **Arbeitsspeicher sparen, die Verarbeitung parallelisieren und die Modularität erhöhen**, ohne dass man große Datenmengen auf einmal laden muss.

#### 1. Dateiverarbeitung

* **Große Logdateien analysieren**: Zeilenweise Einlesen, Filtern nach Schlüsselwörtern, Aggregation von Statistiken
* **CSV/TSV Parsing**: Zeilenweise Einlesen, Spalten extrahieren, direkt in Datenstruktur speichern, ohne die komplette Datei zu laden

---

#### 2. Netzwerk- und Protokollverarbeitung

* **SMTP-E-Mail-Versand**: Anhänge direkt aus Dateien codieren (Base64, Quoted-Printable) und stückweise senden
* **HTTP Chunked Transfer Encoding**: Daten komprimieren, chunkweise übertragen
* **Proxy-Server / Filter-Server**: Datenstrom transformieren (z. B. Text ersetzen, Header modifizieren) ohne Zwischenspeicherung

---

#### 3. Datenkompression und Kodierung

* **Gzip-/Deflate-Kompression**: Chunkweise komprimieren, Speicherverbrauch gering halten
* **Base64-Encoding/Decoding**: Große Dateien direkt codieren/dekodieren
* **Zeilenumbruch-/EOL-Normalisierung**: Dateien zwischen Unix, Windows, Mac-Konventionen umwandeln

---

#### 4. Streaming-Transformationen

* **Textfilterung**: Entfernen von Kommentaren oder Leerzeilen aus großen Textdateien
* **Zeilen- oder Spaltenbasierte Transformationen**: Beispielsweise tabellarische Daten formatieren oder aggregieren
* **On-the-fly Bild-/Audioverarbeitung**: Chunkweise Transformationen, z. B. Umkodierung oder Resize von Mediendaten

---

#### 5. Datenintegration und ETL-Prozesse

* **Stückweises Einlesen aus mehreren Quellen** (Datei, Datenbank, Netzwerk)
* **Datenvalidierung und Bereinigung** während des Lesens, bevor sie gespeichert werden
* **Streaming-Aggregationen** (Summen, Durchschnitt, Max/Min) ohne ganze Daten im Speicher

---

#### 6. Debugging & Logging

* **Tracing von Feldzugriffen** oder Funktionsaufrufen mittels Filterketten
* **Echtzeit-Profiling**: Zählung von Funktionsaufrufen oder Datenvolumen in Streams
* **Logging-Filter**: Lognachrichten stückweise analysieren, filtern und in unterschiedliche Senken weiterleiten

---

#### 7. Parallelisierung / Remote Processing

* **Verteilte Datenverarbeitung**: Datenstrom chunkweise zu entfernten Prozessen senden
* **RPC- oder Socket-Kommunikation**: Parameter serialisieren und zurückliefern, ohne ganze Objekte zu halten

---

### A. Strings und Tabellen

| Status | Regel                                | Anwendung                                        | Priorität      |
| ------ | ------------------------------------ | ------------------------------------------------ | -------------- |
| `[ ]`  | Keine String-Verkettung in Schleifen | Buffer sammeln, table.concat am Ende             | 🟡 EMPFOHLEN    |
| `[ ]`  | String-Indices statt Kopien          | Mit von string.find gelieferten Indizes arbeiten | 🟢 NICE-TO-HAVE |
| `[ ]`  | Tabellen vorreservieren              | { [N] = 0 } oder Reserve-Funktion nutzen         | 🟡 EMPFOHLEN    |
| `[ ]`  | Befüllen mit t[i]                    | t[i] = v ist schnellste Variante                 | 🟡 EMPFOHLEN    |
| `[ ]`  | Tabellenpool/clear                   | Wiederverwenden, table.clear wenn verfügbar      | 🟢 NICE-TO-HAVE |

### B. Performance-Quickwins

| Status | Regel                              | Anwendung                                              | Priorität      |
| ------ | ---------------------------------- | ------------------------------------------------------ | -------------- |
| `[ ]`  | Lokale Funktions-Refs in Hot-Loops | local fn = mod.fn vor der Schleife                     | 🟢 NICE-TO-HAVE |
| `[ ]`  | vim.fn nicht micro-optimieren      | Alias bringt kaum Vorteile, eher Aufrufzahl reduzieren | 🟢 NICE-TO-HAVE |
| `[ ]`  | Async statt Blocken                | vim.loop für Hintergrund-Tasks, Debouncing für Writes  | 🟡 EMPFOHLEN    |
| `[ ]`  | Memoization                        | Weak-Tables für Caches (__mode="v"/"kv")               | 🟢 NICE-TO-HAVE |

#### Performance-Checks

1. mit `vim.mpack` liegt ein messagepack serialization möglichkeit vor (eventuell json vorzuziehen)

### C. Neovim-API sicher verwenden

| Status | Regel                    | Anwendung                                      | Priorität   |
| ------ | ------------------------ | ---------------------------------------------- | ----------- |
| `[ ]`  | Handle-Validierung       | Vor jedem nvim_buf_* / nvim_win_* prüfen       | 🔴 KRITISCH  |
| `[ ]`  | Deferred Calls absichern | In vim.defer_fn erneut validieren              | 🔴 KRITISCH  |
| `[ ]`  | Einheitliche Fenster-API | Öffnen/Schließen/Konfigurieren zentral kapseln | 🟡 EMPFOHLEN |

### D. State- und Datenmodelle

| Status | Regel                             | Anwendung                                      | Priorität      |
| ------ | --------------------------------- | ---------------------------------------------- | -------------- |
| `[ ]`  | Getter/Setter statt Direktzugriff | ui_state.get_*/set_*                           | 🟡 EMPFOHLEN    |
| `[ ]`  | Metatables gezielt                | __index für Defaults, geteilte Logik           | 🟢 NICE-TO-HAVE |
| `[ ]`  | FIFO/Ringbuffer wo passend        | Begrenzte Historien/Favoriten speicherschonend | 🟢 NICE-TO-HAVE |

### E. Garbage-Collector bewusst steuern

| Status | Regel                   | Anwendung                                                    | Priorität      |
| ------ | ----------------------- | ------------------------------------------------------------ | -------------- |
| `[ ]`  | Große Objekte freigeben | Referenz auf nil, ggf. collectgarbage("collect") in Leerlauf | 🟢 NICE-TO-HAVE |
| `[ ]`  | Coroutine-Recycling     | Job-Loop statt viele kurzlebige Coroutines                   | 🟢 NICE-TO-HAVE |


### F. Lazy-Loading und On-Demand-Konfiguration

Man kann die gezeigte Technik als eine *lazy-initializing*, *on-demand* Konfiguration mit eingebauter Unterstützung für Default-Resolver und asynchrone/aktualisierbare Felder beschreiben. Anstatt beim Setup sofort eine vollständige Deep-Copy der Defaults ins User-Config-Objekt zu schreiben, initialisiert die Metatable Felder erst beim ersten Zugriff. Dadurch spart man Arbeit (und Speicher) für Felder, die nie verwendet werden, und ermöglicht dynamische Default-Berechnungen sowie automatische Refresh-Hooks.

## Architektur-Checkliste

| Status | Aspekt           | Fragen zur Prüfung                                                | Priorität   |
| ------ | ---------------- | ----------------------------------------------------------------- | ----------- |
| `[ ]`  | Schichten/Module | Ist Verantwortlichkeit klar? Ist Kopplung niedrig, Kohäsion hoch? | 🔴 KRITISCH  |
| `[ ]`  | Abhängigkeiten   | Werden States/Abh. explizit über Parameter/DI gereicht?           | 🔴 KRITISCH  |
| `[ ]`  | Erweiterbarkeit  | Gibt es zentrale Registries/Factories für Tools/Adapter?          | 🟡 EMPFOHLEN |
| `[ ]`  | Testbarkeit      | Pure Kernlogik, Ports/Adapter trennbar, Mocks möglich?            | 🟡 EMPFOHLEN |

### C/C++ nativen Quellcode

**Beispiel:**
    Wenn in Lua eine Tabelle mit einer Million Zahlen erstellt wird, verbraucht das viel Speicher und strapaziert den Garbage Collector. Über `ffi`- Foreig FUnction Interface - kannst du ein echtes C-Array im Speicher anlegen:

## Anti-Pattern-Check

| Status | Muster                          | Gegenmaßnahme                          | Priorität      |
| ------ | ------------------------------- | -------------------------------------- | -------------- |
| `[ ]`  | Globaler State                  | Modul-interner State + API; keine _G.* | 🔴 KRITISCH     |
| `[ ]`  | API ohne Guards                 | Immer type/nil + nvim_*_is_valid       | 🔴 KRITISCH     |
| `[ ]`  | String-Concat im Loop           | Buffer + table.concat                  | 🟡 EMPFOHLEN    |
| `[ ]`  | Closures im Loop                | Vorab Funktion binden, wiederverwenden | 🟡 EMPFOHLEN    |
| `[ ]`  | Viele kleine temporäre Tabellen | Tabellenpool, clear/reuse              | 🟢 NICE-TO-HAVE |

## Import- und Dateistruktur-Check

| Status | Punkt              | Soll-Zustand                                                    | Priorität      |
| ------ | ------------------ | --------------------------------------------------------------- | -------------- |
| `[ ]`  | Import-Reihenfolge | System/Kern → Debug → Utils → State → UI → Controller → Keymaps | 🟢 NICE-TO-HAVE |
| `[ ]`  | Datei-Header       | @module, @class, @brief, @description vorhanden                 | 🟡 EMPFOHLEN    |
| `[ ]`  | Typ-Ablage         | Projektweiter @types-Ordner genutzt (Alias/Interfaces)          | 🟢 NICE-TO-HAVE |

## Performance-Spickzettel (zum Abhaken bei Hotpaths)

| Status | Maßnahme                   | Wirkung                                   | Priorität      |
| ------ | -------------------------- | ----------------------------------------- | -------------- |
| `[ ]`  | t[i] statt table.insert    | Schnellstes Befüllen großer Arrays        | 🟡 EMPFOHLEN    |
| `[ ]`  | { [N] = 0 } Inline-Reserve | Reduziert Rehash/Realloc                  | 🟡 EMPFOHLEN    |
| `[ ]`  | table.concat statt ..      | Vermeidet O(n²)-Stringkosten              | 🟡 EMPFOHLEN    |
| `[ ]`  | Weak-Caches                | Automatisches Freigeben ungenutzter Werte | 🟢 NICE-TO-HAVE |
| `[ ]`  | Debounced Writes           | I/O-Spitzen glätten                       | 🟢 NICE-TO-HAVE |
| `[ ]`  | Memoization                | Teure Funktionen/Parser cachen            | 🟢 NICE-TO-HAVE |
| `[ ]`  | Async via uv               | Hintergrundarbeit ohne UI-Block           | 🟡 EMPFOHLEN    |

## Sortieralgorithmen (Auswahl, Implementierung, Review) mit Prioritäten

[Referenz](./Referenzen/Sortieralgorithmen-Ref.md)
[All-Sort notes](../../Architektur/Sortieralgorithmen/All-Sort.md)

### Eingabe- und Randbedingungen

| Status | Prüfschritt                                                               | Priorität      |
| ------ | ------------------------------------------------------------------------- | -------------- |
| `[ ]`  | Datentyp geklärt (Integer, Float, String, Objekt mit Comparator)          | 🔴 KRITISCH     |
| `[ ]`  | Größenordnung n abgeschätzt (klein/mittel/groß, evtl. Externalsort/I/O)   | 🔴 KRITISCH     |
| `[ ]`  | Wertebereich k bekannt (relevant für Counting/Radix/Bucket)               | 🔴 KRITISCH     |
| `[ ]`  | Verteilung bekannt (gleichmäßig, viele Duplikate, fast sortiert, reverse) | 🟡 EMPFOHLEN    |
| `[ ]`  | Stabilität erforderlich ja/nein                                           | 🔴 KRITISCH     |
| `[ ]`  | Zusatzspeicher-Budget definiert (O(1)/O(log n)/O(n))                      | 🔴 KRITISCH     |
| `[ ]`  | Worst-Case-Garantien nötig (Deadlines, DoS-Schutz)                        | 🔴 KRITISCH     |
| `[ ]`  | Parallelisierbarkeit relevant (Mehrkern/GPU/Netzwerke)                    | 🟢 NICE-TO-HAVE |
| `[ ]`  | Comparator bildet totale Ordnung (transitiv, antisymmetrisch, total)      | 🔴 KRITISCH     |

### Algorithmuswahl (Daumenregeln)

| Status | Prüfschritt                                                                   | Priorität      |
| ------ | ----------------------------------------------------------------------------- | -------------- |
| `[ ]`  | Standardbibliothek bevorzugen (z. B. Timsort in Python/Java)                  | 🔴 KRITISCH     |
| `[ ]`  | Quick Sort für allgemeine Fälle, in-place; Pivot-Strategie gegen O(n²)        | 🟡 EMPFOHLEN    |
| `[ ]`  | Merge Sort für Stabilität und garantierte O(n log n) (Achtung: O(n) Speicher) | 🟡 EMPFOHLEN    |
| `[ ]`  | Heap Sort für O(n log n) mit O(1) Extra-Speicher (nicht stabil)               | 🟡 EMPFOHLEN    |
| `[ ]`  | Insertion/Shell für kleine n oder fast sortierte Daten                        | 🟡 EMPFOHLEN    |
| `[ ]`  | Counting/Radix/Bucket bei Integer/Strings und geeignetem k/Verteilung         | 🔴 KRITISCH     |
| `[ ]`  | Bitonic/Parallel Merge nur bei echter Parallelumgebung                        | 🟢 NICE-TO-HAVE |
| `[ ]`  | Bubble/Selection/Gnome/Cocktail nur didaktisch oder sehr kleine n             | 🟡 EMPFOHLEN    |
| `[ ]`  | Pancake/Bogo/Sleep nicht produktiv einsetzen                                  | 🔴 KRITISCH     |

### Komplexität und Speicher

| Status | Prüfschritt                                                                           | Priorität   |
| ------ | ------------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Best-/Average-/Worst-Case pro Algorithmus dokumentiert                                | 🔴 KRITISCH  |
| `[ ]`  | Lower Bound für Vergleichssortierung (Ω(n log n)) berücksichtigt                      | 🔴 KRITISCH  |
| `[ ]`  | Platzkomplexität inkl. Rekursions-Stack angegeben                                     | 🔴 KRITISCH  |
| `[ ]`  | Cache-/Lokalitätsaspekte bewertet (z. B. Quick Sort cache-freundlicher als Heap Sort) | 🟡 EMPFOHLEN |
| `[ ]`  | Für Counting/Radix k/Basiswahl begründet; Speicherbedarf realistisch                  | 🔴 KRITISCH  |

### Implementierungsdetails

| Status | Prüfschritt                                                                                | Priorität   |
| ------ | ------------------------------------------------------------------------------------------ | ----------- |
| `[ ]`  | Quick Sort: Pivot (Random/Median-of-3), 3-Wege-Partition bei vielen Duplikaten             | 🔴 KRITISCH  |
| `[ ]`  | Merge Sort: stabile Merge-Phase, minimale Allokationen; ggf. in-place-Varianten geprüft    | 🟡 EMPFOHLEN |
| `[ ]`  | Heap Sort: Build-Heap O(n), Down-Heap korrekt, Indexgrenzen sicher                         | 🔴 KRITISCH  |
| `[ ]`  | Insertion/Shell: Schwellen/Gap-Sequenz definiert, kleine Runs optimiert                    | 🟡 EMPFOHLEN |
| `[ ]`  | Counting: Zähl-Array-Größe = k, Prefix-Summen korrekt, Stabilität je nach Bedarf           | 🔴 KRITISCH  |
| `[ ]`  | Radix: stabile Ziffernstufe (Counting), Basis/Breite festgelegt (LSB-first für Stabilität) | 🔴 KRITISCH  |
| `[ ]`  | Bucket: Bucket-Funktion/Anzahl begründet, In-Bucket-Sort stabil/passend                    | 🟡 EMPFOHLEN |
| `[ ]`  | Comparator konsistent, ohne Nebenwirkungen                                                 | 🔴 KRITISCH  |
| `[ ]`  | Overflow/Indexfehler ausgeschlossen (32/64 Bit, Grenzprüfungen)                            | 🔴 KRITISCH  |

### Tests und Verifikation

| Status | Prüfschritt                                                                                | Priorität   |
| ------ | ------------------------------------------------------------------------------------------ | ----------- |
| `[ ]`  | Ergebnis sortiert und Permutation der Eingabe (Property-Tests)                             | 🔴 KRITISCH  |
| `[ ]`  | Stabilität (falls gefordert) geprüft mit Tiebreak-Keys                                     | 🔴 KRITISCH  |
| `[ ]`  | Degenerierte Fälle: leer, 1 Element, alle gleich, schon sortiert, reverse, viele Duplikate | 🔴 KRITISCH  |
| `[ ]`  | Größenstaffelung: klein/mittel/groß, Benchmarks gegen Standardbibliothek                   | 🟡 EMPFOHLEN |
| `[ ]`  | Performance-Schwellen/Hybride (z. B. n<32 → Insertion) mit Messungen belegt                | 🟡 EMPFOHLEN |
| `[ ]`  | Speicherprofil/Spitzen geprüft; Externalsort/I/O simuliert                                 | 🟡 EMPFOHLEN |

### Dokumentation

| Status | Prüfschritt                                                                                      | Priorität   |
| ------ | ------------------------------------------------------------------------------------------------ | ----------- |
| `[ ]`  | Tabelle mit Name, Art, Stabil, In-Place, Zeit (Best/Avg/Worst), Platz, typische Einsatzszenarien | 🟡 EMPFOHLEN |
| `[ ]`  | Grenzen klar genannt (Counting/Radix nur für Integer/Strings mit begrenztem k)                   | 🔴 KRITISCH  |
| `[ ]`  | Entscheidungsbegründung und Alternativen dokumentiert (inkl. Why-not-Liste)                      | 🟡 EMPFOHLEN |

## Einfüge-/Lösch-/Update-/Such-Algorithmen und verwandte Datenstruktur-Operationen

[Referenz](./Referenzen/DataStructures-Ref.md)

### Anforderungen und Randbedingungen

| Status | Prüfschritt                                                                                  | Priorität      |
| ------ | -------------------------------------------------------------------------------------------- | -------------- |
| `[ ]`  | Operationsprofil geklärt: Anteil von Insert/Delete/Update/Search/Range/Iterationen           | 🔴 KRITISCH     |
| `[ ]`  | Datenvolumen n und Änderungsrate (Events/s) abgeschätzt                                      | 🔴 KRITISCH     |
| `[ ]`  | Schlüssel-/Werte-Charakteristik: feste Breite, variable Länge, Komparierbarkeit, Hashbarkeit | 🔴 KRITISCH     |
| `[ ]`  | Ordnung erforderlich (Sortierreihenfolge, Range-Queries, Order-Statistics)                   | 🔴 KRITISCH     |
| `[ ]`  | Stabilität der Iterationsreihenfolge gefordert (deterministische Traversierung)              | 🟡 EMPFOHLEN    |
| `[ ]`  | Speicherbudget/Overhead definiert (Bytes pro Element, Fragmentierung, Over-Allocation)       | 🔴 KRITISCH     |
| `[ ]`  | Latenz-/Durchsatzziele, Worst-Case-Garantien (Amortisiert vs. Worst Case)                    | 🔴 KRITISCH     |
| `[ ]`  | Parallelität/Locking/Lock-Free-Anforderungen                                                 | 🟡 EMPFOHLEN    |
| `[ ]`  | Persistenz/Immutabilität/Snapshots (Zeitreisen, Undo, MVCC)                                  | 🟢 NICE-TO-HAVE |

### Struktur-/Algorithmuswahl (Daumenregeln)

| Status | Prüfschritt                                                                        | Priorität   |
| ------ | ---------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Key-Value ohne Ordnung → Hash-Tabelle (Load-Factor/Resizing planen)                | 🔴 KRITISCH  |
| `[ ]`  | Ordnung/Range/Prefix notwendig → Balanced BST (AVL/RB), B/B+-Baum, Skip-List, Trie | 🔴 KRITISCH  |
| `[ ]`  | Prioritäten/Top-k/Streaming → Heap/Priority Queue, Auswahlalgorithmen              | 🔴 KRITISCH  |
| `[ ]`  | Mengenoperationen/Disjunkte Mengen → Union-Find (ohne Delete)                      | 🟡 EMPFOHLEN |
| `[ ]`  | Zeitreihen/Intervalle → Segment-/Fenwick-/Interval-Baum                            | 🟡 EMPFOHLEN |
| `[ ]`  | Text/Sequenzen mit vielen Edits → Rope, Piece Table, Gap Buffer                    | 🟡 EMPFOHLEN |
| `[ ]`  | Speicherarme Membership-Prüfung → Bloom/Cuckoo Filter (FP-Rate dimensionieren)     | 🟡 EMPFOHLEN |
| `[ ]`  | Externe/Block-Speicher → B/B+-Baum (Node-Füllgrade, Blockgrößen)                   | 🔴 KRITISCH  |

### Arrays/Vektoren (dynamisch)

| Status | Prüfschritt                                                                     | Priorität      |
| ------ | ------------------------------------------------------------------------------- | -------------- |
| `[ ]`  | Wachstumsstrategie/Growth-Factor (z. B. ×1.5/×2) und Reallocations dokumentiert | 🔴 KRITISCH     |
| `[ ]`  | Amortisierte O(1)-Append vs. O(n)-Insert/Delete in der Mitte klar kommuniziert  | 🟡 EMPFOHLEN    |
| `[ ]`  | Kapazitäts-Reservierung (reserve/preallocate) an Hotpaths                       | 🟡 EMPFOHLEN    |
| `[ ]`  | Cache-Lokalität genutzt (contiguous), Alignment beachtet                        | 🟢 NICE-TO-HAVE |

### Verkettete Listen (Singly/Doubly)

| Status | Prüfschritt                                                             | Priorität   |
| ------ | ----------------------------------------------------------------------- | ----------- |
| `[ ]`  | Insert/Delete O(1) nur mit Verweis auf Vorgänger/Nachfolger garantiert  | 🔴 KRITISCH  |
| `[ ]`  | Random-Access-Kosten (O(n)) in API und Doku klargemacht                 | 🔴 KRITISCH  |
| `[ ]`  | Speicher-Overhead (Pointer) und schlechte Cache-Lokalität einkalkuliert | 🟡 EMPFOHLEN |
| `[ ]`  | Sentinel/Head/Tail-Invarianten, Leaks/Orphans ausgeschlossen            | 🔴 KRITISCH  |

### Hash-Tabellen

| Status | Prüfschritt                                                                                  | Priorität   |
| ------ | -------------------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Hashfunktion geeignet (Verteilung, DoS-Resistenz bei untrusted Input)                        | 🔴 KRITISCH  |
| `[ ]`  | Kollisionsstrategie gewählt: Chaining vs. Open Addressing (Linear/Quadratic/Robin Hood)      | 🔴 KRITISCH  |
| `[ ]`  | Load-Factor-Grenzen und Resize-Politik (Up/Down) definiert                                   | 🔴 KRITISCH  |
| `[ ]`  | Delete-Semantik: Tombstones (Open Addressing) vs. Listen-Remove (Chaining) korrekt umgesetzt | 🔴 KRITISCH  |
| `[ ]`  | Iterationsreihenfolge dokumentiert (nicht stabil!)                                           | 🟡 EMPFOHLEN |
| `[ ]`  | Gleichheits-/Hash-Vertrag (equal ⇒ same hash) geprüft                                        | 🔴 KRITISCH  |

### Balancierte Suchbäume (AVL/Red-Black)

| Status | Prüfschritt                                                         | Priorität   |
| ------ | ------------------------------------------------------------------- | ----------- |
| `[ ]`  | Baum-Invarianten formalisiert (Höhen-/Schwarz-Eigenschaften)        | 🔴 KRITISCH  |
| `[ ]`  | Rotationen korrekt implementiert (LL/LR/RL/RR)                      | 🔴 KRITISCH  |
| `[ ]`  | Insert/Delete führt Rebalancing deterministisch aus                 | 🔴 KRITISCH  |
| `[ ]`  | Order-Statistics/Augmentation (Size/Sum/MinMax) konsistent gepflegt | 🟡 EMPFOHLEN |
| `[ ]`  | Inorder-Iteration liefert sortierte Reihenfolge                     | 🟡 EMPFOHLEN |

### Heaps/Priority Queues

| Status | Prüfschritt                                                                     | Priorität   |
| ------ | ------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Heap-Eigenschaft garantiert (parent ≥/≤ children)                               | 🔴 KRITISCH  |
| `[ ]`  | Build-Heap O(n) verwendet (nicht n×push)                                        | 🟡 EMPFOHLEN |
| `[ ]`  | Decrease-Key/Delete-Arbitrary unterstützt oder dokumentiert als nicht verfügbar | 🟡 EMPFOHLEN |
| `[ ]`  | Stabilität nur via Tiebreak-Key erreichbar (sonst nicht stabil)                 | 🟡 EMPFOHLEN |

### B-/B+-Bäume (Block/Externspeicher)

| Status | Prüfschritt                                                             | Priorität      |
| ------ | ----------------------------------------------------------------------- | -------------- |
| `[ ]`  | Ordnung/Min-Füllgrad je Node erfüllt (Split/Merge/Redistribute korrekt) | 🔴 KRITISCH     |
| `[ ]`  | Blatt-Verkettung (B+) für Range-Scans vorhanden                         | 🟡 EMPFOHLEN    |
| `[ ]`  | Blockgrößen/Alignment auf Speichermedium abgestimmt                     | 🟡 EMPFOHLEN    |
| `[ ]`  | Crash-Sicherheit/Write-Ahead-Logging/Checksums (falls nötig)            | 🟢 NICE-TO-HAVE |

### Skip-Lists

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Level-Verteilung (p, maxLevel) definiert, erwartete O(log n) begründet | 🟡 EMPFOHLEN |
| `[ ]`  | Insert/Delete aktualisiert alle betroffenen Level-Forward-Pointer      | 🔴 KRITISCH  |
| `[ ]`  | Iterationsreihenfolge sortiert, Range-Queries effizient                | 🟡 EMPFOHLEN |

### Tries/Radix-Bäume

| Status | Prüfschritt                                                                      | Priorität   |
| ------ | -------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Alphabet/Encoding (ASCII/UTF-8/Unicode) und Case-Folding/Normalization definiert | 🔴 KRITISCH  |
| `[ ]`  | Kompression (Patricia/Radix) bei spärlichen Kanten                               | 🟡 EMPFOHLEN |
| `[ ]`  | Delete entfernt verwaiste Knoten sicher (Shrinking)                              | 🔴 KRITISCH  |
| `[ ]`  | Prefix/Ranges/Autocomplete effizient                                             | 🟡 EMPFOHLEN |

### Bitset/Bloom/Cuckoo Filter

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Kapazität m, Hash-Anzahl k, gewünschte FP-Rate p dimensioniert         | 🔴 KRITISCH  |
| `[ ]`  | Deletion: Counting-Bloom nötig oder Alternativen (Cuckoo)              | 🔴 KRITISCH  |
| `[ ]`  | Hashfunktionen unabhängig/qualitativ; Seed/Salting bei untrusted Input | 🟡 EMPFOHLEN |
| `[ ]`  | Saturation/Relocation-Limit (Cuckoo) behandelt                         | 🟡 EMPFOHLEN |

### Union-Find (Disjoint Set)

| Status | Prüfschritt                                                   | Priorität   |
| ------ | ------------------------------------------------------------- | ----------- |
| `[ ]`  | Union by Rank/Size und Path Compression implementiert         | 🔴 KRITISCH  |
| `[ ]`  | Delete von Elementen nicht unterstützt oder klar dokumentiert | 🔴 KRITISCH  |
| `[ ]`  | Dynamische Erweiterung (neue Elemente) ohne Reinitialisierung | 🟡 EMPFOHLEN |

### Segment-/Fenwick-/Interval-Bäume

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Indexierung (0/1-basiert) konsistent, Grenzen/Inclusive-Exclusive klar | 🔴 KRITISCH  |
| `[ ]`  | Punkt/Range-Updates korrekt propagiert                                 | 🔴 KRITISCH  |
| `[ ]`  | Lazy-Propagation (Segmentbaum) für große Bereiche implementiert        | 🟡 EMPFOHLEN |

### Sequenzstrukturen (Rope, Piece Table, Gap Buffer)

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Zielprofil: viele mittige Edits vs. Appends → Struktur passend gewählt | 🔴 KRITISCH  |
| `[ ]`  | Join/Split/Balance-Invarianten eingehalten                             | 🔴 KRITISCH  |
| `[ ]`  | Speicherfragmente/Anzahl Stücke begrenzt (Rebalance/Coalescing)        | 🟡 EMPFOHLEN |

### Lösch-Strategien

| Status | Prüfschritt                                                          | Priorität      |
| ------ | -------------------------------------------------------------------- | -------------- |
| `[ ]`  | Physisches Delete vs. Lazy Delete/Tombstones (GC/Compaction geplant) | 🔴 KRITISCH     |
| `[ ]`  | Nebenwirkungen auf Iteration/Range-Queries und Metriken dokumentiert | 🟡 EMPFOHLEN    |
| `[ ]`  | Wiederverwendung freier Slots/Free-List implementiert                | 🟢 NICE-TO-HAVE |

### Parallelität und Nebenläufigkeit

| Status | Prüfschritt                                                               | Priorität   |
| ------ | ------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Konsistenzmodell (Linearizierbarkeit, SEQ-Cst vs. Relaxed) definiert      | 🔴 KRITISCH  |
| `[ ]`  | Resize/Rehash/Rotation/Node-Split unter Konkurrenz sicher                 | 🔴 KRITISCH  |
| `[ ]`  | Deadlocks/ABA/Memory-Reclamation (Hazard Pointers/epoch-based) adressiert | 🔴 KRITISCH  |
| `[ ]`  | Read-Optimierungen (RCU/Snapshotting)                                     | 🟡 EMPFOHLEN |

### Persistenz/Immutabilität

| Status | Prüfschritt                                                       | Priorität   |
| ------ | ----------------------------------------------------------------- | ----------- |
| `[ ]`  | Struktur-Sharing/Copy-on-Write korrekt (Referenzzählung/GC-Druck) | 🟡 EMPFOHLEN |
| `[ ]`  | Versionierung/Snapshots/Undo mit Speicherbudget vereinbar         | 🟡 EMPFOHLEN |

### Tests, Invarianten, Benchmarks

| Status | Prüfschritt                                                                                     | Priorität   |
| ------ | ----------------------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Invarianten nach jeder Operation (Shapes, Größen, Höhen, Load-Factor, Parent/Child-Beziehungen) | 🔴 KRITISCH  |
| `[ ]`  | Property-Tests: Insert→Search, Insert→Delete→Leer, Order/Range-Korrektheit                      | 🔴 KRITISCH  |
| `[ ]`  | Degenerate Fälle: leer, 1 Element, alle gleich, Platz-/Zeit-Grenzen                             | 🔴 KRITISCH  |
| `[ ]`  | Micro-Benchmarks für Insert/Delete/Update/Search; Throughput+Latency-Metriken                   | 🟡 EMPFOHLEN |
| `[ ]`  | Reproduzierbarkeit: Seeds, Hardware, Compiler/Flags, Warmup, Median/IQR                         | 🟡 EMPFOHLEN |

### Dokumentation und Verträge

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Komplexitäten (amortisiert vs. Worst Case) je Operation klar angegeben | 🔴 KRITISCH  |
| `[ ]`  | Iterationsordnung/Stabilität/Determinismus dokumentiert                | 🔴 KRITISCH  |
| `[ ]`  | Fehlermodi/Edge-Cases (Überlauf, Kollisionen, leere/volle Strukturen)  | 🔴 KRITISCH  |
| `[ ]`  | API-Verträge (Comparator/Hasher, Ownership/Lifetimes)                  | 🔴 KRITISCH  |
| `[ ]`  | Wartung: Rehash-/Rebalance-Trigger, Hintergrund-Jobs (Compaction, GC)  | 🟡 EMPFOHLEN |

## Zeit- und Platzkomplexität (Notation, Kommunikation, Nachweis) mit Prioritäten

[Referenz](./Referenzen/Complexity-Ref.md)
[Detaillerte Infos](./Referenzen/Zeitkomplexität.md)

### Notationsdisziplin

| Status | Prüfschritt                                                 | Priorität   |
| ------ | ----------------------------------------------------------- | ----------- |
| `[ ]`  | Big-O (O) als obere Schranke korrekt verwenden              | 🔴 KRITISCH  |
| `[ ]`  | Big-Omega (Ω) als untere Schranke korrekt verwenden         | 🟡 EMPFOHLEN |
| `[ ]`  | Big-Theta (Θ) als enge Schranke korrekt verwenden           | 🟡 EMPFOHLEN |
| `[ ]`  | Little-o (o) nur für strikte obere Schranken einsetzen      | 🟡 EMPFOHLEN |
| `[ ]`  | Little-omega (ω) nur für strikte untere Schranken einsetzen | 🟡 EMPFOHLEN |
| `[ ]`  | Basis/Definitionen dokumentiert (n, k, log-Basis)           | 🔴 KRITISCH  |

### Aussagekraft und Annahmen

| Status | Prüfschritt                                                               | Priorität   |
| ------ | ------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Eingabeverteilung explizit (zufällig, fast sortiert, viele Duplikate)     | 🔴 KRITISCH  |
| `[ ]`  | Kostenmodell benannt (Vergleiche, Swaps, Speicherzugriffe, I/O)           | 🔴 KRITISCH  |
| `[ ]`  | Rekursionskosten berücksichtigt (Stacktiefe, keine implizite TCO-Annahme) | 🔴 KRITISCH  |
| `[ ]`  | Platzkomplexität separat ausgewiesen (inkl. temporärer Strukturen)        | 🔴 KRITISCH  |
| `[ ]`  | Lower Bounds erwähnt (z. B. Vergleichssortierung ≥ Ω(n log n))            | 🟡 EMPFOHLEN |

### Kommunikation und Nachweis

| Status | Prüfschritt                                                           | Priorität   |
| ------ | --------------------------------------------------------------------- | ----------- |
| `[ ]`  | Best-/Average-/Worst-Case angegeben und Bedingungen für ihr Eintreten | 🔴 KRITISCH  |
| `[ ]`  | Hybrid-/Schwellenwerte dokumentiert (z. B. Umschalten auf Insertion)  | 🟡 EMPFOHLEN |
| `[ ]`  | Messaufbau beschrieben (Datensätze, Wiederholungen, Warmup, Hardware) | 🟡 EMPFOHLEN |
| `[ ]`  | Reproduzierbarkeit gesichert (Seed, Versionen, Compiler/Flags, Build) | 🟡 EMPFOHLEN |
| `[ ]`  | Trade-offs klar (Zeit vs. Speicher vs. Stabilität vs. Einfachheit)    | 🔴 KRITISCH  |

### Qualitätssicherung

| Status | Prüfschritt                                                    | Priorität      |
| ------ | -------------------------------------------------------------- | -------------- |
| `[ ]`  | Property-Tests (Sortiertheit, Permutation, Stabilität)         | 🔴 KRITISCH     |
| `[ ]`  | Fuzzer/Randomized Testing gegen Standardbibliothek             | 🟡 EMPFOHLEN    |
| `[ ]`  | Skalierungstests für Counting/Radix (großes k)                 | 🟡 EMPFOHLEN    |
| `[ ]`  | Cache-/Lokalisierungstests (Blockgrößen, Datenlayout)          | 🟢 NICE-TO-HAVE |
| `[ ]`  | Parallel-/Externalsort-Fälle separat bewertet und dokumentiert | 🟢 NICE-TO-HAVE |

---

## Bitoperationen

[Referenz](./Referenzen/Bitoperationen-Ref.md)
[Details](./Referenzen/Bitoperationen.md)

### Plattform/Eignung (Kurz-Check)

| Status | Prüfschritt                                                                        | Priorität   |
| ------ | ---------------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Zielsprache und Integer-Domäne geklärt (32-Bit, 64-Bit, BigInt)                    | 🔴 KRITISCH  |
| `[ ]`  | Bitoperatoren der Plattform geeignet (LuaJIT `bit.*`, JS number/BigInt, Go, C/C++) | 🔴 KRITISCH  |
| `[ ]`  | Maskenbreite explizit festgelegt und dokumentiert                                  | 🔴 KRITISCH  |
| `[ ]`  | Verhalten bei Vorzeichen/Überlauf geprüft (Two’s Complement, Coercion)             | 🟡 EMPFOHLEN |
| `[ ]`  | Bibliotheken/Builtins für Popcount/Parity verfügbar und berücksichtigt             | 🟡 EMPFOHLEN |

### Allgemeine Leitlinien

| Status | Prüfschritt                                                              | Priorität   |
| ------ | ------------------------------------------------------------------------ | ----------- |
| `[ ]`  | Lesbarkeit vor Micro-Optimierung                                         | 🔴 KRITISCH  |
| `[ ]`  | Domäne strikt eingehalten (32-Bit vs. 64-Bit vs. BigInt)                 | 🔴 KRITISCH  |
| `[ ]`  | Aliasing ausgeschlossen (keine identische Speicherstelle zweimal)        | 🔴 KRITISCH  |
| `[ ]`  | Maskenbreite und Semantik dokumentiert                                   | 🟡 EMPFOHLEN |
| `[ ]`  | Vorher messen, nachher verifizieren (Benchmark/Profiling/Property-Tests) | 🟡 EMPFOHLEN |
| `[ ]`  | In Lua bevorzugt paralleles Tauschen `a, b = b, a` statt XOR-Swap        | 🟡 EMPFOHLEN |

### Zwei Werte ohne temporäre Variable tauschen (XOR-Swap)

| Status | Prüfschritt                                                                                | Priorität      |
| ------ | ------------------------------------------------------------------------------------------ | -------------- |
| `[ ]`  | Operanden sind Integers in gültiger Bitdomäne (JS: 32-Bit, BigInt: beide Operanden BigInt) | 🔴 KRITISCH     |
| `[ ]`  | Kein Aliasing derselben Speicherstelle (z. B. `arr[i]` und erneut `arr[i]`)                | 🔴 KRITISCH     |
| `[ ]`  | Team-Lesbarkeit ok; sonst temporäre Variable verwenden                                     | 🔴 KRITISCH     |
| `[ ]`  | In Lua/Neovim stattdessen `a, b = b, a`                                                    | 🟡 EMPFOHLEN    |
| `[ ]`  | Messbarer Performance-Vorteil vorhanden                                                    | 🟢 NICE-TO-HAVE |

### Einzigartiges Element in Duplikaten finden (alle anderen exakt zweimal)

| Status | Prüfschritt                                                     | Priorität   |
| ------ | --------------------------------------------------------------- | ----------- |
| `[ ]`  | Problem erfüllt „alle anderen erscheinen exakt zweimal“         | 🔴 KRITISCH  |
| `[ ]`  | Werte im Integer-Gültigkeitsbereich (JS: 32-Bit oder BigInt)    | 🔴 KRITISCH  |
| `[ ]`  | Für „dreimal“/„k-mal“ existiert Bitzähl-/Modulo-je-Bit-Variante | 🟡 EMPFOHLEN |
| `[ ]`  | Vorzeichen/Negativwerte und Darstellung geprüft                 | 🟡 EMPFOHLEN |

### Unterschiede zwischen zwei Werten (Maske/LSB isolieren)

| Status | Prüfschritt                                                   | Priorität   |
| ------ | ------------------------------------------------------------- | ----------- |
| `[ ]`  | Unterschiedsmaske korrekt: `mask = a ^ b`                     | 🟡 EMPFOHLEN |
| `[ ]`  | Niedrigstes unterschiedliches Bit via `mask & -mask` isoliert | 🟡 EMPFOHLEN |
| `[ ]`  | Partitionierung nach gesetztem/nicht gesetztem Bit korrekt    | 🟡 EMPFOHLEN |

### Bit-Parität (gerade/ungerade Anzahl gesetzter Bits)

| Status | Prüfschritt                                                         | Priorität   |
| ------ | ------------------------------------------------------------------- | ----------- |
| `[ ]`  | Paritätsanforderung vorhanden (Prüfbits/Fehlererkennung)            | 🟡 EMPFOHLEN |
| `[ ]`  | Effiziente Zählung genutzt (Kernighan-Trick oder Popcount/Builtins) | 🟡 EMPFOHLEN |
| `[ ]`  | Plattform-Builtins (z. B. Go `math/bits`) berücksichtigt            | 🟡 EMPFOHLEN |

### XOR-Linked-List

| Status | Prüfschritt                                                                | Priorität   |
| ------ | -------------------------------------------------------------------------- | ----------- |
| `[ ]`  | Umgebung erlaubt Pointerarithmetik und manuelle Speicherverwaltung (C/C++) | 🔴 KRITISCH  |
| `[ ]`  | Debugbarkeit/Iteration/Sicherheit akzeptabel dokumentiert                  | 🔴 KRITISCH  |
| `[ ]`  | Zwingender Speichergrund vorhanden (z. B. Embedded)                        | 🟡 EMPFOHLEN |
| `[ ]`  | In Managed-Sprachen/Neovim-Lua/TS nicht einsetzen                          | 🔴 KRITISCH  |

### XOR-Range-Trick (XOR von 1..n bzw. L..R)

| Status | Prüfschritt                                                | Priorität   |
| ------ | ---------------------------------------------------------- | ----------- |
| `[ ]`  | Domäne natürliche Zahlen; Grenzen L ≤ R geprüft            | 🔴 KRITISCH  |
| `[ ]`  | 4-Zyklus-Muster korrekt implementiert                      | 🟡 EMPFOHLEN |
| `[ ]`  | Allgemeiner Bereich via `xor1toR ^ xor1to(L-1)` realisiert | 🟡 EMPFOHLEN |

### Bitmasken mit XOR zum gezielten Flippen

| Status | Prüfschritt                                                            | Priorität   |
| ------ | ---------------------------------------------------------------------- | ----------- |
| `[ ]`  | Maskenbreite explizit (8/16/32/64-Bit, BigInt-Breite)                  | 🔴 KRITISCH  |
| `[ ]`  | Inversion via `value ^ allOnesMask` korrekt; Vorzeichen berücksichtigt | 🟡 EMPFOHLEN |
| `[ ]`  | In JS BigInt All-Ones-Maske via `((1n << width) - 1n)`                 | 🟡 EMPFOHLEN |

## Zusammenfassende Anti-Pattern-Checks für Bittricks

| Status | Muster                                    | Gegenmaßnahme                                          | Priorität   |
| ------ | ----------------------------------------- | ------------------------------------------------------ | ----------- |
| `[ ]`  | XOR-Swap ohne zwingenden Grund            | Temporäre Variable bzw. paralleles Tauschen in Lua     | 🔴 KRITISCH  |
| `[ ]`  | Unklare Maskenbreite                      | Breite dokumentieren und testen (Property-Based Tests) | 🔴 KRITISCH  |
| `[ ]`  | Verlassen auf JS-`number` jenseits 32-Bit | BigInt nutzen oder Domain hart begrenzen               | 🔴 KRITISCH  |
| `[ ]`  | Aliasing bei XOR-Swap                     | Unterschiedliche Speicherstellen sicherstellen         | 🔴 KRITISCH  |
| `[ ]`  | Ungemessene Micro-Optimierung             | Benchmark/Profiling vor/nachher                        | 🟡 EMPFOHLEN |

## Reviewer-Notizen (Vorlage)

| Bereich                             | Beobachtung | Empfehlung |
| ----------------------------------- | ----------- | ---------- |
| Sicherheit                          |             |            |
| Modularität                         |             |            |
| Neovim-API                          |             |            |
| Performance                         |             |            |
| Doku/Annotation                     |             |            |
| Tests                               |             |            |
| (check)-health modul implementiert? |             |            |

## Referenzen

- Bei der Erstellung von neuen Projekten, Plänen, Machbarkeits-Studien, usw.. sofern möglich immer als letzten Punkt `## Literatur und Referenzen` angeben und diesen mit dem Projekt enstprechenden Referenzen, Fachliteratur, und dergelichen angeben

---
