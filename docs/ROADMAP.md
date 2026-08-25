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
- `TESTS/` — manual test guides for the core resolution pipeline
  (linepath, tailsearch, `:Gopath`, stack traces, direct symbol jumps)
- CI (`.github/workflows/ci.yml`): `stylua --check`, `luacheck`, and a
  headless smoke test (`scripts/ci/headless_tests.lua`) that boots gopath
  and executes every `TESTS/*.lua` fixture as a plain Lua chunk

---

## Quality & checklist audits

gopath.nvim was audited against the three personal Lua/Neovim checklists
(2026-07-04), analogously to the audit of `buffer-ctx.nvim` that had already
been carried out:

- [Arch&Coding.md](ROADMAP/Arch&Coding.md) — architecture & coding rules
- [Zentral-Prinzipien.md](ROADMAP/Zentral-Prinzipien.md) — central module principles
- [Checklist.md](ROADMAP/Checklist.md) — the master checklist (quick check/PR/coding)

**Verdict:** mostly met. The chapters on sorting, data structures and bit
operations are n/a (no algorithm code of its own beyond the Levenshtein
distance and suffix matching, both small and pure functions). Concrete findings
fixed (2026-07-04):

- ~~A few direct `vim.notify(...)` calls~~ in `commands.lua`,
  `bindings/usrcmds.lua`, `truncated/finder.lua`,
  `resolvers/common/env_path.lua`, `external/helpers/opener.lua` and
  `util/cross.lua` switched over to `gopath.util.log` — consistent prefixing
  and, where installed, delegation to `lib.nvim.notify` (analogous to
  `buffer_ctx.util.notify`).
- ~~The `GopathKeymaps` type was missing the `probe` field~~ — added in
  `@types/config.lua` (checklist §7: "every key needs a type").
- ~~No `/config` or `/bindings` folder~~ — both introduced analogously to
  `buffer-ctx.nvim` (`config/DEFAULTS.lua` + `config/init.lua`,
  `bindings/{keymaps,usrcmds,autocmds,which_key,init}.lua`).
- ~~No which-key support~~ — `bindings/which_key.lua` (a soft dependency, with
  a v2/v3 fallback) added, including a healthcheck line.
- ~~No CI workflow~~ (stylua + luacheck + the `TESTS` runner headless) —
  `.github/workflows/ci.yml` added, which closes the only open "recommended"
  item from checklist §7.

All points left open by the audit of 2026-07-04 are thereby worked off.

---

## Planned features

- **Frecency learning for alternate suggestions** — frequently chosen
  alternates should be sorted to the top. `pickers.nvim` already has an
  implementation in `smart/frecency.lua`; that belongs shared via `lib.nvim`
  instead of rebuilt in gopath. It is cross-repo work (lib.nvim +
  pickers.nvim + gopath) and therefore not done in a single session. A
  configurable UI backend and a preview (size/mtime), by contrast, already
  exist — see
  [FEATURES/NAVIGATION.md](FEATURES/NAVIGATION.md#fuzzy-alternate-resolution).

- **Treesitter instead of line patterns in `symbol_locator`/`table_locator`** —
  despite the "treesitter provider" name, both locate their target via
  line-oriented Lua patterns rather than real treesitter queries (built that
  way deliberately, for tolerance of line breaks after `=`, bracket keys and
  tables inside function calls). A full migration is roughly a week of work,
  because all 8 fallback strategies in `table_locator.locate` have to be
  preserved. Concrete bugs in the existing pattern logic get fixed as they
  come up (see the `find_child_table` fix, which corrected a double bracket
  count).

Otherwise there are no urgent open features at this point; new ideas get added
here as soon as they become concrete.

## Not planned

- **A fuzzy finder/picker of its own** — integration with Telescope/fzf-lua
  deliberately stays out of scope; gopath resolves paths, it does not replace a
  picker.
