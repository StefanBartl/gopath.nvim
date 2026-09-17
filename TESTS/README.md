# Tests

Two different things live under this heading, and they are not
interchangeable.

**`TESTS/*.lua` are manual guides.** Each file is a buffer full of realistic
lines with a "HOW TO TEST" header: open it, put the cursor where the comment
says, press the keymap, look at what happens. They exercise the parts of
gopath that only make sense with a human and a window — which key opened which
split, what the create-on-missing dialog looks like, whether the PDF chooser
appears. CI only checks that they are still valid, side-effect-free Lua.

**`scripts/ci/` holds the automated suites.** They are plain Lua run by
headless Neovim with their own assertion helpers — there is no plenary/busted
dependency, and no spec here starts a subprocess or touches the network.

## Table of contents

- [Running them](#running-them)
- [The three runners](#the-three-runners)
- [No subprocesses, no network](#no-subprocesses-no-network)
- [Writing a spec](#writing-a-spec)
- [Coverage](#coverage)
- [Bugs pinned by a regression assertion](#bugs-pinned-by-a-regression-assertion)
- [Deliberately not covered](#deliberately-not-covered)

## Running them

`lib.nvim` is a hard dependency and must be on the runtimepath. CI checks it
out to `deps/lib.nvim`; locally, point at wherever you have it.

```sh
LIB=../lib.nvim   # or E:/repos/lib.nvim, or deps/lib.nvim

nvim --headless --noplugin -u NONE --cmd "set runtimepath+=$LIB" \
  -c "lua dofile('scripts/ci/headless_tests.lua')"

nvim --headless --noplugin -u NONE --cmd "set runtimepath+=$LIB" \
  -c "lua dofile('scripts/ci/functional_tests.lua')"

nvim --headless --noplugin -u NONE --cmd "set runtimepath+=$LIB" \
  -c "lua dofile('scripts/ci/unit_tests.lua')"
```

Each exits non-zero on the first failing check, so they drop straight into a
shell `&&` chain or a git hook.

While working on one area, `GOPATH_SPEC` filters the unit suite to the spec
files whose name contains the given substring:

```sh
GOPATH_SPEC=tailsearch nvim --headless --noplugin -u NONE \
  --cmd "set runtimepath+=$LIB" -c "lua dofile('scripts/ci/unit_tests.lua')"
```

`ui.nvim` is **not** required. Where a module prefers `ui.kit` (the
create-on-missing dialog, the alternate picker, the PDF chooser, the ambiguous
probe) the specs supply a stand-in and assert what it was offered, so the
suites behave the same whether or not ui.nvim happens to be installed.

## The three runners

| Runner | What it is for |
| --- | --- |
| `scripts/ci/headless_tests.lua` | The plugin loads, `setup({})` runs, and no guide under `TESTS/` has bit-rotted into a syntax error or a `require` of a module that no longer exists. |
| `scripts/ci/functional_tests.lua` | End-to-end resolution, written as one flat file: the Lua table/symbol locators (Treesitter-first *and* the no-parser fallback), the URL phases as they behave inside the real pipeline, the alternate frecency ceiling against a real store, and the two curated-array config cases. |
| `scripts/ci/unit_tests.lua` | Runs every `scripts/ci/specs/*_spec.lua`. Per-module behaviour for everything else. |

A spec file is a module returning `function(H)`, where `H` is
`scripts/ci/harness.lua`: `H.check` / `H.eq` / `H.same` / `H.match` /
`H.raises`, plus fixtures (`H.tmpdir`, `H.write`, `H.buf`, `H.cursor_on`,
`H.line_at`), notification and `vim.ui.select` capture, `H.config_sandbox`, and
`H.with_modules`.

`H.with_modules` is the important one. Modules here bind their dependencies to
upvalues while loading —

```lua
local LOG = require("gopath.util.log")
```

— so patching a field afterwards is too late. `with_modules` replaces entries
in `package.loaded` (or makes a `require` fail, for "this plugin is not
installed"), evicts the module under test so it re-runs its top-level requires,
and restores everything afterwards.

## No subprocesses, no network

gopath reaches for an external process in exactly four places. Each is cut at a
seam, and what is asserted is the **argv that would have been spawned**:

| Where | Spawns | Seam | Spec |
| --- | --- | --- | --- |
| `external/helpers/opener.lua` | `explorer.exe` / `open` / `xdg-open` via `vim.system` | `vim.system`, plus `open_nvim` and `lib.nvim.cross.open_default` in `package.loaded` | `external_spec.lua` |
| `external/helpers/revealer.lua` | the same three via `vim.fn.jobstart` | `vim.fn.jobstart`, plus `lib.nvim.cross.reveal_in_fm` | `external_spec.lua` |
| `resolvers/common/tailsearch.lua` | `git -C <dir> rev-parse --show-toplevel` | `vim.system` | `tailsearch_spec.lua` |
| `truncated/finder.lua` | `fd` / `fdfind` / `rg` | `vim.fn.executable` + `vim.system` | `truncated_spec.lua` |

Two more things are substituted rather than exercised for real:

* **the cache file.** `truncated/cache.lua` writes
  `stdpath("cache")/gopath_fs_cache.json`, which a test run must not clobber —
  `lib.nvim.fs.json` and `lib.nvim.fs.is_readable_file` are replaced for every
  persistence case. The *scans* are real, over directories built under
  `vim.fn.tempname()`.
* **the LSP.** `providers/lsp.lua` is driven with a canned
  `vim.lsp.buf_request_sync` response, one per shape a server can answer with
  (a single `Location`, a list of them, a `LocationLink`). That no request is
  made at all without an attached client is pinned in
  `functional_tests.lua`.

Everything else runs against the real filesystem, real buffers and a real
cursor. The path helpers exist to `fs_stat` and `fs_scandir`; a mocked
filesystem would only test the mock.

## Writing a spec

```lua
-- scripts/ci/specs/my_thing_spec.lua
---@param H table
return function(H)
  H.check("does the thing", function()
    local dir = H.tmpdir()
    H.write(dir .. "/a.lua", { "return {}" })
    H.line_at("see " .. dir .. "/a.lua", "a.lua", { filetype = "lua" })

    local r = require("gopath.resolvers.common.filetoken").resolve()
    H.truthy(r, "expected a result")
    H.eq(r.exists, true)
  end)
end
```

Drop the file in `scripts/ci/specs/`; the runner discovers it. There is no
aggregator to register it in.

Two house rules:

* **Assert the reported text, not just that something failed.** A guard that
  turns a raw `E739` into "Could not create file: …" is the whole point of the
  guard; `pcall(...) == false` would pass either way.
* **Leave the editor as you found it.** `H.config_sandbox` restores the config
  (`setup()` accumulates and `get()` hands back the live table), and the specs
  that move the runtimepath, register commands or bind keys put them back.

## Coverage

77 files under `lua/`. 17 spec files under `scripts/ci/specs/`, 435 checks and
about 1600 executed assertions, plus the 38 checks in `functional_tests.lua`
and the 8 in `headless_tests.lua`.

| Spec | Covers |
| --- | --- |
| `util_path_spec` | `util/path.lua`: separator-normalising `join`, `exists`, and all four search strategies (runtimepath + its name index and TTL, `&path`/`suffixesadd`, `package.path`, the install dirs of installed-but-unloaded plugins) plus the composed `search_module` |
| `util_misc_spec` | `util/cross.lua` (with and without lib.nvim), `util/location.lua` (all five suffix forms, Windows drives, range clamping), `util/log.lua` (both notifier paths, the `dev_mode` gate), `util/safe.lua`, `util/safe_notify.lua` |
| `config_spec` | `config/DEFAULTS.lua`'s shape and `config/init.lua`'s recursive merge: nested overrides, list-replacement, scalars over tables, accumulation across calls |
| `url_spec` | `util/url.lua` (strict vs. loose detection, the drive-letter guard, normalisation, cursor extraction) and `resolvers/common/url.lua` (both passes, the `enable`/`bare_hosts` gates, configured schemes/TLDs) |
| `env_shorten_spec` | `env_shorten.lua`: all four root forms, every negative case from `TESTS/06`, multi-pair ordering, and the buffer-facing `:GopathToReposDir` |
| `external_spec` | `external/`: the extension/URL detector, `should_open_externally`, the opener and revealer argv chains through all their fallback layers, and the PDF mode chooser |
| `create_open_spec` | `create.lua` (the offer in every branch, the nearest-ancestor walk, filetree.nvim, ui.kit vs. `vim.ui.select`) and `open/init.lua` (URL / explorer / external / missing / placement / jump / escaping) |
| `tailsearch_spec` | `resolvers/common/tailsearch.lua`: `sanitize`, `suffix_candidates`, `pick_best`, `guess_roots`, `find_by_tail`, `cache_lookup`, and all four resolution entry points including the picker flow |
| `truncated_spec` | `truncated/cache.lua` (scan, exclusions, depth, both search strategies, persistence validation, staleness, roots, the refresh timer) and `truncated/finder.lua` (the async walk and the `fd`/`rg` argv) |
| `lang_resolvers_spec` | `resolvers/common/lang_helper.lua` and all eight language resolvers — python, go, rust, c/cpp, javascript/typescript, csharp, zig, java — each against a real miniature project |
| `common_resolvers_spec` | `resolvers/common/`: the extractor (terminators, boundary expansion, dedup, all three find algorithms), `linepath.lua`, `filetoken.lua`, `env_path.lua`, `help.lua` |
| `providers_spec` | `providers/token.lua`, `providers/builtin.lua`, `providers/treesitter.lua`, `providers/lsp.lua` |
| `lua_resolvers_spec` | `resolvers/lua/`: `require_path`, `binding_index`, `alias_index` (including the per-buffer cache and its invalidation), `chain`, `identifier_locator`, `local_to_module`, `ts_lua_ast` |
| `pipeline_spec` | `registry.lua` (per-language dispatch, custom resolvers, the `resolvers` allow-list) and `resolve.lua` (every phase, in order, with each one observable) |
| `commands_spec` | `commands.lua`: window-mode routing, the async tailsearch fallback, the clipboard format per result kind, the existence check, the visual-selection probe, the debug report |
| `alternate_spec` | `alternate/`: directory helpers, the similarity matcher, the selection UI on both backends, and the callback contract both entry points hang on |
| `wiring_spec` | `bindings/` (keymaps incl. overrides/lists/`false`, `:Gopath` and every alias, the autocommands), `open/help.lua`, `health.lua`, and `init.lua`'s `setup()` |

## Bugs pinned by a regression assertion

Found while writing the above, each marked `BUG:` at the assertion that pins
it. They are pinned rather than fixed: every one of them is a visible
behaviour change, and none of them blocked the specs.

1. **`external/helpers/opener.lua` passes a stray argument to `explorer.exe`.**
   `cmd = { "explorer.exe", path:gsub("/", "\\") }` — an unparenthesised
   `gsub` in the last slot of a table constructor contributes *both* return
   values, so the replacement count lands in the argv. Windows-only, and only
   on the minimal fallback path (neither open.nvim nor lib.nvim installed).
   The sibling `revealer.lua` writes the same `gsub` inside a concatenation,
   which truncates it to one value, and is fine.
2. **`resolvers/common/extractor/helpers.lua`'s `expand_right` keeps the
   terminator.** `expand_left` returns `j + 1`, `expand_right` returns `j`, so
   the character that ended the path ends up inside it. `strip_wrappers`
   cleans up brackets but not a space, comma, semicolon or quote — so
   `see docs/a.md, then run` yields the candidate `docs/a.md,`. The trailing
   *space* case is easy to miss on Windows, where the Win32 API tolerates one;
   on Linux and macOS it does not resolve.
3. **`resolvers/common/tailsearch.lua`'s `sanitize` strips a drive letter only
   from `<UPPER>:/`.** The strip is the first `gsub` in the chain, so it runs
   before backslashes are normalised, and `%u` excludes a lowercase drive.
   `C:\repos\x.lua` becomes the tail `C/repos/x.lua`, and the `:line:col`
   branch returns before the strip runs at all, so `E:/repos/x.lua:12:3`
   keeps its `E:` segment. It degrades rather than breaks (shorter suffixes
   are tried next), but the longest and most trusted candidate is the
   unmatchable one.
4. **`resolvers/lua/require_path.lua`'s previous-line lookup is dead code.**
   It scans the line above for a `require(...)` continued across lines, then
   checks `cursor_in(s, e, 1e9)` — meant as "any column", but `cursor_in`
   requires `col <= span_e`, so it always fails.
5. **`providers/token.lua` breaks the `path(line)` location format.** The
   module docstring promises to preserve it and `filetoken.looks_like_path`
   accepts it, but the cleanup ends with `token:gsub("%)$", "")`. What is left
   (`src/a.lua(42`) parses as a *filename*, so the file stops resolving too,
   not just the line number.
6. **`commands.lua`'s `check_under_cursor` help branch is unreachable.** It
   opens with `if not res or not res.path`, and a help result has no `path` —
   `common/help.lua` returns `{ language, kind, subject, subjects, source,
   confidence }`. `gC` on `vim.api` reports "no match to check: unknown"
   instead of "help target — nothing to check".
7. **`util/path.lua`'s `invalidate_caches()` does not clear the
   plugin-directory list.** It clears `_rtpidx` and `_pidx_*` but not
   `_pdir_*`, which sit in the same block of module locals, so a plugin set
   that changed without the runtimepath moving stays invisible.
8. **`create.lua`'s "built-in fallback" still requires lib.nvim.** When
   `lib.nvim.fs.create_entry` is missing the module logs "using a built-in
   mkdir+open fallback", but that fallback is
   `require("lib.nvim.fs.write.to_file")(...)` — an unguarded require of the
   dependency just found missing. With lib.nvim genuinely absent the create
   offer dies with a raw "module not found" instead of gopath's own
   "Could not create file: …".

Four further quirks are pinned as *documented behaviour* rather than defects,
so a future change to any of them fails loudly: `config.get()` hands back the
live state table (as its docstring says); `extractor/find.lua`'s second
stacktrace pass re-matches the first one more greedily; `linepath`'s explicit
cwd join is unreachable because `fs_stat` already resolves relative paths
against the process cwd; and `cache.lua`'s own 18-entry exclusion list is
always overridden by the 7-entry one in `config/DEFAULTS.lua`.

## Deliberately not covered

* **`lua/gopath/@types/*.lua`, `alternate/@types`, `resolvers/@types`,
  `resolvers/lua/@types`, `truncated/@types`, `util/@types`** — pure
  `---@meta` annotations. No runtime code to run.
* **`plugin/gopath.lua`** — a three-line `vim.g.loaded_gopath` guard with no
  branch of its own.
* **`config/DEFAULTS.lua` as a file** — a declarative table; its *shape* is
  asserted in `config_spec` because the rest of the plugin indexes into it.
* **The actual launching of an external application**, and the actual running
  of `fd`/`rg`/`git`. What a system opener does with a path is the OS's
  business; the argv it is handed is gopath's, and that is what is asserted.
* **`truncated/cache.lua`'s periodic refresh callback.** The timer's setup and
  replacement are covered; waiting out a real interval would measure the clock,
  and `needs_refresh` + `build_async` are both driven directly.
* **The rendering half of the pickers** — what `ui.kit.select` / `kit.confirm`
  draw on screen. The specs assert the spec table handed to them (items, title,
  formatter, the select/cancel callbacks) and stop at that boundary; ui.nvim
  tests its own drawing.
* **Live LSP navigation.** No server is started. Every response shape
  `providers/lsp.lua` has to understand is fed to it directly.
* **What `TESTS/*.lua` is for**: which window a keymap opened, how a dialog
  looks, whether a PDF actually appeared. That is what the manual guides are,
  and a headless run cannot see it.
