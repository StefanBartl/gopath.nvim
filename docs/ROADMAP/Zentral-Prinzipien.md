# Checkliste: Zentrale Prinzipien für nvim-Module

Diese Liste ist als schnelle mentale Prüfung pro Modul gedacht.
Wenn mehrere Punkte mit „ja“ beantwortet werden, lohnt sich meist eine strukturelle Anpassung.
Diese Checkliste ist kein Dogma, sondern ein Werkzeug, um bei jedem Modul schnell zu erkennen, **wo strukturelles Potenzial liegt**, bevor echte Performance-Probleme entstehen.

**WICHTIG**:
Verwende die custom `StefanBartl/lib.nvim`-Library, insbesondere:
    - `lib.notify` anstatt `vim.notify()` oder `print()`
    - `lib.map` anstatt `vim.keymap.set`; respektive `lib.usercmd`, `lib.autocmd`, `lib.augroup`
    - `lib.cross_plattform` / `lib.cross`: Alle Module müssen entweder Cross-Plattform sein oder eine alternative innerhalb des Moduls bereitstellen
    - `lib.hover_select`: Ein wrapper der vim.select ersetzt und bei kontinuierlicher Verwendung eine konsequente UI ermöglicht
    - `lib.lazy` ermöglich die Vermeidung unnötiger Ladelast
    - `lib.memo` ermöglicht Standardisierte Memoization
    - uvm...

---

## Table of content

  - [1. Events bündeln, Logik entkoppeln](#1-events-bndeln-logik-entkoppeln)
  - [2. Eigene Logik lazy laden](#2-eigene-logik-lazy-laden)
  - [3. Kontext statt Mehrfach-API-Zugriffe](#3-kontext-statt-mehrfach-api-zugriffe)
  - [4. Autocommand-Gruppen sauber nutzen](#4-autocommand-gruppen-sauber-nutzen)
  - [5. Event oder Command?](#5-event-oder-command)
  - [6. Treesitter notwendig oder nicht?](#6-treesitter-notwendig-oder-nicht)
  - [7. Cache vorhanden und explizit?](#7-cache-vorhanden-und-explizit)
  - [8. Allokationen im Hot-Path vermeiden](#8-allokationen-im-hot-path-vermeiden)
  - [9. Debugbarkeit eingeplant?](#9-debugbarkeit-eingeplant)
  - [10. Laufzeit wichtiger als Startup?](#10-laufzeit-wichtiger-als-startup)
  - [Kurzform (mental)](#kurzform-mental)

---

## 1. Events bündeln, Logik entkoppeln

* Gibt es in diesem Modul eigene `nvim_create_autocmd`-Aufrufe?
* Reagieren mehrere Module auf dasselbe Event?
* Könnte dieses Modul stattdessen einen Handler registrieren?
* Wird Logik mehrfach an Events gebunden, statt zentral ausgelöst?

---

## 2. Eigene Logik lazy laden

* Wird das Modul beim Startup geladen, obwohl es selten gebraucht wird?
* Hängt die Funktionalität an einem Event, Command oder Filetype?
* Könnte `require` hinter einen Nil-Check oder in einen Handler verschoben werden?
* Wird Code geladen, obwohl die Funktion nie aufgerufen wird?

---

## 3. Kontext statt Mehrfach-API-Zugriffe

* Ruft das Modul mehrfach `nvim_buf_get_*` oder `vim.fn.*` auf?
* Werden dieselben Informationen in mehreren Funktionen erneut abgefragt?
* Könnte ein Context-Objekt (bufnr, path, ft, root) einmal erzeugt werden?
* Gibt es versteckte Abhängigkeiten zu globalem Zustand?

---

## 4. Autocommand-Gruppen sauber nutzen

* Ist das Autocommand einer klaren Gruppe zugeordnet?
* Kann das Event gezielt gelöscht oder neu initialisiert werden?
* Ist klar ersichtlich, wo dieses Event definiert wird?
* Würde ein Reload ohne Neustart sauber funktionieren?

---

## 5. Event oder Command?

* Wird Logik automatisch ausgeführt, obwohl sie nur auf explizite Aktion gehört?
* Könnte ein `:Command` statt eines Autocommands sinnvoller sein?
* Läuft Code bei jedem Bufferwechsel, obwohl er selten gebraucht wird?
* Ist der Auslöser wirklich zustandsgetrieben?

---

## 6. Treesitter notwendig oder nicht?

* Wird Treesitter nur für einfache Pattern-Erkennung genutzt?
* Reicht ein Zeilen-Scan oder Regex?
* Läuft Treesitter-Code in häufigen Events?
* Ist echte Syntax-Semantik wirklich erforderlich?

---

## 7. Cache vorhanden und explizit?

* Wird ein Ergebnis mehrfach neu berechnet?
* Könnte das Ergebnis gecached werden?
* Ist der Cache regenerierbar und invalidierbar?
* Liegt der Cache in `stdpath("cache")` und nicht im Runtime-State?

---

## 8. Allokationen im Hot-Path vermeiden

* Werden in Schleifen neue Tabellen erzeugt?
* Werden Strings in Loops konkatenziert?
* Gibt es Closures in häufig aufgerufenen Pfaden?
* Sind Tabellen mit bekannter Struktur typisiert oder vorannotiert?

---

## 9. Debugbarkeit eingeplant?

* Ist klar erkennbar, wann dieses Modul aktiv wird?
* Gibt es einen einfachen Debug-Schalter?
* Lässt sich das Modul isoliert testen?
* Ist der Kontrollfluss nachvollziehbar?

---

## 10. Laufzeit wichtiger als Startup?

* Läuft Code bei `CursorMoved`, `TextChanged`, `BufEnter`?
* Ist der Code dort minimal und deterministisch?
* Wird unnötige Arbeit bei häufigen Events vermieden?
* Ist Startup-Optimierung hier überhaupt relevant?

---

## Kurzform (mental)

* Wann läuft es?
* Muss es jetzt laufen?
* Lädt es mehr als nötig?
* Läuft es öfter als nötig?
* Wird Arbeit wiederholt?
* Ist der Datenfluss klar?

---
