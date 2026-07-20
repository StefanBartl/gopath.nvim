# Resolution Pipeline

> 🇩🇪 Deutsche Version: [RESOLUTION-DE.md](./RESOLUTION-DE.md)

This document explains how gopath turns *the thing under your cursor* into *an
opened file at the right line* — the ordered chain of resolvers, the
asynchronous open flow, and the fallbacks. It complements
[CACHE.md](./CACHE.md), which covers the truncated-path cache that the pipeline
relies on.

- Orchestrator: [`lua/gopath/resolve.lua`](../lua/gopath/resolve.lua)
- Command/open flow: [`lua/gopath/commands.lua`](../lua/gopath/commands.lua),
  [`lua/gopath/open/init.lua`](../lua/gopath/open/init.lua)
- Token extraction: [`lua/gopath/providers/token.lua`](../lua/gopath/providers/token.lua)
- Separator handling: [`lua/gopath/util/cross.lua`](../lua/gopath/util/cross.lua)

---

## Contents

- [The result type](#the-result-type)
- [Phase order](#phase-order)
- [Token extraction & path normalization](#token-extraction--path-normalization)
- [Synchronous fast path vs. async search](#synchronous-fast-path-vs-async-search)
- [Path lookup caching](#path-lookup-caching)
- [Opening: window placement, jump, externals](#opening-window-placement-jump-externals)
- [Not-found fallbacks](#not-found-fallbacks)
- [Configuration & entry points](#configuration--entry-points)

---

## The result type

Every resolver returns a `GopathResult` (or `nil`):

| Field | Meaning |
|-------|---------|
| `path` | Absolute path, **forward-slash canonical** internally |
| `range` | `{ line, col }` to jump to, or `nil` |
| `kind` | `"file"` / `"module"` / `"help"` |
| `source` | Which resolver produced it (debugging) |
| `confidence` | `0–1`; higher wins earlier |
| `exists` | Whether the path was confirmed on disk |

`confidence` and `exists` drive the orchestration: a confident, existing hit is
returned immediately; a low-confidence or non-existent result is held as a
fallback so later phases can improve on it.

---

## Phase order

`resolve_at_cursor` ([`resolve.lua`](../lua/gopath/resolve.lua)) tries resolvers
in order and returns the first success:

| Phase | Resolver | Trigger |
|-------|----------|---------|
| 1 | `:help` subject | token looks like a Vim help tag |
| 2 | `$VAR` env path | token starts with `$` or `${` |
| 3 | **filetoken** | `<cfile>` under cursor; searches `&path`, rtp, then the **cache** |
| 3.5 | **linepath** | scans the whole current line (stacktraces, extension-driven, absolute) |
| 4 | Language pipeline | LSP → Treesitter → builtin (per filetype, e.g. Lua `require`) |
| 5 | filetoken fallback | the low-confidence/non-existent result held from phase 3 |
| 6 | raw `<cfile>` | last resort |

Phase 3 returns immediately **only** when it finds a confirmed file
(`exists and confidence ≥ 0.6`); otherwise it stashes the speculative result and
lets phases 3.5–4 try first.

> **Important:** phases 3 and 3.5 consult the truncated-path cache via
> `tailsearch.resolve_cached` — a **cache-only, non-blocking** lookup. They never
> run a live filesystem walk inside this synchronous pipeline. That keeps the
> pipeline instant; the (potentially slow) live search is deferred to the
> command layer (next section).

---

## Token extraction & path normalization

The token under the cursor comes from
[`providers/token.lua`](../lua/gopath/providers/token.lua), which is smarter than
plain `<cfile>`: it walks outward over path-like characters and preserves a
trailing `:line:col` / `(line)` location suffix.

Cleanup that matters cross-platform:

- A **leading `(`** pulled in from a markdown link `](path)` is stripped (it is
  part of the accepted character set so `path(10)` works, so a leading one must
  be removed explicitly).
- A leading **chain dot** (`.foo` → `foo`) is removed, but `./`, `.\` (relative)
  and `...` (truncated) prefixes are **preserved**.
- Separators are normalized to **forward slashes** for all internal matching via
  [`util/cross.lua`](../lua/gopath/util/cross.lua), and the final openable path
  is converted back to **OS-native** separators (backslashes on Windows) right
  before `:edit`. Both directions are backed by **lib.nvim**
  (`lib.nvim.cross.separators`), with built-in fallbacks if lib.nvim is absent.

This is why a markdown link like `[x](.\spickzettel/Learn.md)` — mixed
separators, a leading paren, a `.\` prefix — resolves correctly.

---

## Synchronous fast path vs. async search

`commands.resolve_and_open(kind)` ([`commands.lua`](../lua/gopath/commands.lua))
orchestrates the user-facing open:

```
resolve_at_cursor()            -- fast: help/env/rtp/&path/cache only
   │
   ├─ exists ≠ false ─────────▶ open immediately            (fast path)
   │
   └─ no confirmed file
          │ derive a search tail (from the speculative path or <cfile>)
          ▼
      vim.notify("Dateisuche läuft…")
      tailsearch.resolve_async(tail, …)   -- async libuv walk, off main loop
          │
          ├─ found ──────────▶ open
          └─ miss ───────────▶ not-found fallbacks
```

- The **fast path** covers the overwhelming majority of jumps (existing files,
  rtp/`&path` hits, warm cache) and opens with **zero latency and no message**.
- Only when nothing is confirmed does the **asynchronous live search** kick in.
  It shows a single progress message *only when the slow walk actually starts*
  (an `on_live_start` hook — a warm cache hit skips it), then opens the buffer
  when a match arrives. The UI never freezes.

`tailsearch.resolve_async` itself is cache-first (instant) and only walks the
filesystem on a miss — see [CACHE.md](./CACHE.md#live-fallback-search).

The visual-selection / cursor **probe** (`:GopathProbe`, `<leader>pp`) uses the
same async machinery and presents a `vim.ui.select` picker on ambiguity.

---

## Path lookup caching

`gF` is a keypress, so [`util/path.lua`](../lua/gopath/util/path.lua) is built to
stay off the filesystem. The naive search — stat every candidate under every
runtimepath entry — costs ~200 `fs_stat` calls per lookup, which on Windows
(especially with AV/EDR scanning) measured **~9.7 ms per miss** against a
50-entry runtimepath.

Misses are the common case: any dotted token under the cursor is fed into the
chain, so most invocations resolve nothing and would pay that walk in full.

Instead each search root is read **once** with a single `fs_scandir`, indexed by
the names directly inside it. A candidate is only stat'ed in a root whose index
actually contains its first path segment, so an unknown token is rejected by
hash lookup alone:

| Lookup | Uncached | Indexed |
| --- | --- | --- |
| module miss (2 candidates) | 9.7 ms | 0.09 ms |
| file-token miss | 5.3 ms | 0.05 ms |
| full `search_module` chain, miss | 11.3 ms | 0.31 ms |

Search **order is unchanged** — the index only skips probes that could not have
matched, so results are identical to the uncached walk.

Because only the *first* segment is indexed, adding a file inside an
already-known directory needs no invalidation at all. Only a brand-new
top-level entry can be hidden by a stale index, and four signals cover that:

- installing/loading a plugin moves the runtimepath, which the caches key on
- gopath's create-on-missing calls `path.invalidate_caches()` directly
- a `BufWritePost` autocmd does the same for buffers written in this session
  (see [BINDINGS.md](./BINDINGS.md#autocommands))
- a 30 s TTL backstops changes made entirely outside Neovim

---

## Opening: window placement, jump, externals

[`open/init.lua`](../lua/gopath/open/init.lua) handles the actual open:

1. **External files** (images, PDFs, …) are handed to the system opener via
   `gopath.external`.
2. A non-existent path is offered for creation via
   [`gopath.create`](../lua/gopath/create.lua) (`create_on_missing`, see
   below) instead of just reporting `File not found`. On confirmation the
   file (+ parent dirs) is created and `M.open` re-enters with `exists = true`.
3. Window placement runs first — `edit` / `split` / `vsplit` / `tabnew` —
   then the file is opened with an **OS-native** path (lib.nvim).
4. If the result carries a `range`, the cursor jumps to `line:col` and centers
   (`normal! zz`).

---

## Not-found fallbacks

When resolution yields a path that does not exist, `commands` tries, in order:

1. **Fuzzy alternate** — Levenshtein similarity against files in the same
   directory ([`alternate/`](../lua/gopath/alternate)), gated by
   `alternate.similarity_threshold`.
2. **Create on missing** — if that fails too, `gopath.open` asks (button
   dialog via lib.nvim's `ui.kit.confirm`, falling back to `vim.ui.select`
   when lib.nvim is absent) whether to create the file. See
   [`gopath.create`](../lua/gopath/create.lua) and the `create_on_missing`
   config block. Opt-out with `create_on_missing.enable = false`, or skip the
   prompt with `confirm = false`. The dedicated `gC` / `:GopathCheck`
   keymap/command checks existence directly (no open attempt first) and
   always offers to create, bypassing the `enable` opt-out.

There used to be a third fallback that opened the nearest existing ancestor
*directory* of the unresolved path as a buffer — removed, because a directory
can't be opened in a Neovim buffer the way a file can (it just handed you to
netrw with no warning). When the resolved path has an existing ancestor
directory and [filetree.nvim](https://github.com/StefanBartl/filetree.nvim)
is installed and set up, the create-on-missing dialog offers a second
button, **"Open in filetree"**, instead: it sets Neovim's cwd to that
directory and roots/focuses filetree.nvim's tree there. The button is only
shown when both conditions hold; otherwise the dialog is just
Create/Cancel.

---

## Configuration & entry points

- Public API: `require("gopath").resolve(opts)` returns a `GopathResult` without
  opening anything; `require("gopath").commands` exposes the open/copy/debug
  actions for custom keymaps.
- Mode selection (`mode = "hybrid" | "lsp" | "treesitter" | "builtin"`) and the
  resolver `order` are documented in the [main README](../README.md#configuration).
- Per-phase switches: `linepath.enable`, `tailsearch.enable`,
  `env_variable_resolution.enable`, `alternate.enable`, and the `languages`
  table.

See [CACHE.md](./CACHE.md) for the cache that backs phases 3/3.5 and the async
fallback.
