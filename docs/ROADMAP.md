# gopath.nvim — Roadmap

## Implemented (v0.3)

- Multi-provider resolution pipeline: LSP → Treesitter → builtin, per-language
  configurable order
- Lua-aware resolution: `require("a.b")`, variable chains, table keys, value
  origin, local-to-module enhancement
- Language resolvers: Lua, Python, JavaScript/TS(X), Rust, Go, C/C++, C#, Zig,
  Java
- `:help` tag resolution for `vim.api.*` / `vim.fn.*` / `vim.loop`
- `$VAR` / `${VAR}` environment-variable path expansion
- Whole-line path extraction (stacktraces, extension-driven expansion,
  absolute paths) — works even when the cursor isn't on the path segment
- Suffix-based filesystem search (tailsearch) across bufdir → cwd → git root
  → stdpaths, with an on-disk cache for truncated (`...`) paths
- Fuzzy alternate resolution (Levenshtein) and nearest-existing-folder
  fallback when a target doesn't exist
- External file opening (images, PDFs, media) via the OS default application
- 7 keymaps + `:Gopath` unified command (with legacy `:Gopath*` aliases),
  all individually configurable/disableable
- `config/` (DEFAULTS + merge) and `bindings/` (keymaps, usrcmds, autocmds,
  which-key) module split
- lib.nvim is a required dependency (keymaps/usrcmds/autocmds route through
  it); `util/cross.lua` and `util/log.lua` degrade gracefully to built-in
  fallbacks if it's ever missing at runtime, but it must still be declared
  in the plugin spec (`dependencies = { "StefanBartl/lib.nvim" }`)
- Optional which-key: labels the `probe` keymap when installed
  (`which_key = false` to disable)
- `:checkhealth gopath`
- `docs/BINDINGS.md` — machine-readable keymap/command/autocmd cheatsheet
- `docs/TESTS/` — manual test guides for the core resolution pipeline
  (linepath, tailsearch, `:Gopath`, stack traces, direct symbol jumps)
- CI (`.github/workflows/ci.yml`): `stylua --check`, `luacheck`, and a
  headless smoke test (`scripts/ci/headless_tests.lua`) that boots gopath
  and executes every `docs/TESTS/*.lua` fixture as a plain Lua chunk

---

## Qualität & Checklist-Audits

gopath.nvim wurde gegen die drei persönlichen Lua/Neovim-Checklisten
auditiert (2026-07-04), analog zum bereits durchgeführten Audit von
`buffer-ctx.nvim`:

- [Arch&Coding.md](ROADMAP/Arch&Coding.md) — Architektur- & Coding-Regeln
- [Zentral-Prinzipien.md](ROADMAP/Zentral-Prinzipien.md) — zentrale Modul-Prinzipien
- [Checklist.md](ROADMAP/Checklist.md) — Master-Checklist (Schnell-Check/PR/Coding)

**Bilanz:** überwiegend erfüllt. Sortier-/Datenstruktur-/Bit-Operationen-Kapitel
sind n/a (kein eigener Algorithmus-Code jenseits von Levenshtein-Distanz und
Suffix-Matching, beides klein und pure-function). Konkrete Funde behoben
(2026-07-04):

- ~~Vereinzelte direkte `vim.notify(...)`-Aufrufe~~ in `commands.lua`,
  `bindings/usrcmds.lua`, `truncated/finder.lua`,
  `resolvers/common/env_path.lua`, `external/helpers/opener.lua` und
  `util/cross.lua` auf `gopath.util.log` umgestellt — konsistentes Prefixing
  und, wo installiert, Delegation an `lib.nvim.notify` (analog
  `buffer_ctx.util.notify`).
- ~~`GopathKeymaps`-Typ fehlte das `probe`-Feld~~ in `@types/config.lua`
  ergänzt (Checklist §7: "jeder Key braucht einen Typ").
- ~~Kein `/config`- bzw. `/bindings`-Ordner~~ — beide analog zu
  `buffer-ctx.nvim` eingeführt (`config/DEFAULTS.lua` + `config/init.lua`,
  `bindings/{keymaps,usrcmds,autocmds,which_key,init}.lua`).
- ~~Keine which-key-Unterstützung~~ — `bindings/which_key.lua` (soft
  dependency, v2/v3-Fallback) ergänzt, inkl. Healthcheck-Zeile.
- ~~Kein CI-Workflow~~ (stylua + luacheck + `docs/TESTS`-Runner headless) —
  `.github/workflows/ci.yml` ergänzt, einziger offener "empfohlen"-Punkt aus
  Checklist §7 damit erledigt.

Damit sind alle aus dem Audit vom 2026-07-04 offenen Punkte abgearbeitet.

---

## Geplante Features

Keine dringenden offenen Features zum jetzigen Zeitpunkt; neue Ideen werden
hier ergänzt, sobald sie konkret anstehen.

## Nicht geplant

- **Eigener Fuzzy-Finder/Picker** — Integration mit Telescope/fzf-lua bleibt
  bewusst außerhalb des Scopes; gopath löst Pfade auf, es ersetzt keinen Picker.
