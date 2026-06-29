# Filesystem Cache & Truncated-Path Resolution

> 🇩🇪 Deutsche Version: [CACHE-DE.md](./CACHE-DE.md)

This document describes the **filesystem cache** that powers fast resolution of
*truncated* and *partial* paths — the kind you get from error messages, stack
traces and logs:

```
...a/Local/nvim/lua/config/neotree/open/filemanager/win.lua:62
…/lua/config/init.lua
neo-tree/ui/renderer.lua
```

The cache lets gopath answer "which real file on disk does this fragment refer
to?" **without freezing the editor**, by scanning the filesystem once in the
background and reconstructing the full absolute path from the visible tail.

- Code: [`lua/gopath/truncated/cache.lua`](../lua/gopath/truncated/cache.lua),
  [`lua/gopath/truncated/finder.lua`](../lua/gopath/truncated/finder.lua),
  [`lua/gopath/truncated/init.lua`](../lua/gopath/truncated/init.lua)
- Lookup glue: [`lua/gopath/resolvers/common/tailsearch.lua`](../lua/gopath/resolvers/common/tailsearch.lua)

---

## Contents

- [Why a cache?](#why-a-cache)
- [The big picture](#the-big-picture)
- [What gets scanned, and when](#what-gets-scanned-and-when)
- [How the scan works (non-blocking)](#how-the-scan-works-non-blocking)
- [Storage: in-memory + on-disk](#storage-in-memory--on-disk)
- [Matching: reconstructing the full path from a tail](#matching-reconstructing-the-full-path-from-a-tail)
- [Live fallback search](#live-fallback-search)
- [Refresh lifecycle](#refresh-lifecycle)
- [Configuration](#configuration)
- [Commands](#commands)
- [Tuning & troubleshooting](#tuning--troubleshooting)
- [Design notes & future ideas](#design-notes--future-ideas)

---

## Why a cache?

Resolving a truncated path means searching the filesystem for a file whose path
*ends with* the visible fragment. Doing that search live, on the main thread
(e.g. with `vim.fs.find`), walks large directory trees synchronously and **locks
up the UI for several seconds** on a real machine (a populated `nvim-data`
directory on Windows is enough to cause a multi-second freeze).

The cache solves this by paying the traversal cost **once, in the background**,
and then answering every subsequent lookup from memory in well under 10 ms.

---

## The big picture

```
                         ┌──────────────────────────────┐
   setup() ───────────▶  │  build_async()  (background)  │
                         │  bounded libuv scandir walk   │
                         └───────────────┬──────────────┘
                                         │ file paths
                                         ▼
   on-disk JSON  ◀────────────  in-memory index  (state.paths)
   (stdpath cache)                       ▲
                                         │ M.search(tail)
   cursor on a truncated path ──▶ cache_lookup(tail)  ──▶ full absolute path
                                         │ (miss)
                                         ▼
                              async live finder walk
                              ("Dateisuche läuft…")
```

1. At startup the cache is **loaded from disk** (instant) and, if stale,
   **rebuilt in the background**.
2. When the cursor lands on a truncated/partial path, the resolver first asks
   the **in-memory cache** (instant).
3. On a cache miss it falls back to an **asynchronous live search** that shows a
   progress message and opens the file once found.

---

## What gets scanned, and when

Scan roots are chosen in [`cache.setup()`](../lua/gopath/truncated/cache.lua).
If you do not set `truncated.cache_roots`, they are auto-detected (deliberately
conservative — we do **not** index a whole drive by default):

| Root | Source |
|------|--------|
| Working directory | `vim.fn.getcwd()` |
| Neovim config | `vim.fn.stdpath("config")` |
| Neovim data (plugins) | `vim.fn.stdpath("data")` |
| Neovim cache | `vim.fn.stdpath("cache")` |
| Git repository root | `git rev-parse --show-toplevel` (if inside a repo) |

Each root is walked up to `truncated.max_depth` levels deep (default **6**),
skipping `truncated.excluded_dirs` (`.git`, `node_modules`, `target`, `build`,
`.cache`, …).

A build is triggered:

- **Once on setup**, deferred ~2 s, only when the cache is missing or stale
  (see [Refresh lifecycle](#refresh-lifecycle)).
- **Periodically**, every `cache_refresh_interval` seconds, when stale.
- **On save** (optional), if `auto_rebuild_on_save = true`, debounced.
- **Manually**, via `:Gopath cache build`.

> ⚠️ The build is wired up in [`lua/gopath/init.lua`](../lua/gopath/init.lua)
> via `cache.setup{…}`. Without that call the scan roots are empty and the cache
> indexes nothing — so the cache is only active when `truncated.enable = true`
> (the default).

---

## How the scan works (non-blocking)

The traversal is a **bounded-concurrency work queue** over libuv's async
`fs_scandir` (`scan_roots_bounded` in `cache.lua`):

- A queue holds `{ dir, depth }` items; at most `max_concurrency` (default
  **16**) `fs_scandir` operations are in flight at once.
- Subdirectories are pushed back onto the queue instead of recursing
  immediately, so the number of open directory handles stays bounded regardless
  of tree size. This avoids `EMFILE` / threadpool starvation on huge trees.
- The whole walk runs off the main loop — Neovim stays responsive while it
  builds.

The live fallback finder uses the **same** bounded libuv walk
(`finder.find_async`), with early-exit once enough matches are found, so it
needs no external tools (`fd`/`rg` are used only by the synchronous
`finder.find`).

---

## Storage: in-memory + on-disk

- **In-memory:** `state.paths` — a flat array of every discovered absolute file
  path. This is what lookups search.
- **On-disk:** a versioned JSON file at
  `stdpath("cache") .. "/gopath_fs_cache.json"` containing `paths`,
  `last_built`, `scan_roots` and a `version`. It is rewritten after each build
  and loaded on startup so the very first lookup of a session is already fast.

---

## Matching: reconstructing the full path from a tail

This is the heart of the system, and it directly implements the idea of *"find
where enough of the path overlaps and rebuild the missing left part."*

A truncated token is first reduced to a clean **tail** (ellipsis/quotes/`:line`
stripped, separators normalized to `/`). The lookup then tries progressively
shorter **suffix candidates**, longest first
(`tailsearch.cache_lookup` → `suffix_candidates`):

```
tail = "...a/Local/nvim/lua/config/neotree/open/filemanager/win.lua"

candidates (longest → shortest, up to max_components):
  lua/config/neotree/open/filemanager/win.lua
  config/neotree/open/filemanager/win.lua
  neotree/open/filemanager/win.lua
  open/filemanager/win.lua
  filemanager/win.lua
  win.lua
```

For each candidate, `cache.search` matches every indexed path with two
strategies (case-insensitive, `\`→`/` normalized):

1. **Exact tail (suffix) match** — the indexed path *ends with* the candidate.
   This is what reconstructs the absolute left part: the full hit
   `C:/Users/me/AppData/Local/nvim/lua/config/.../win.lua` ends with
   `lua/config/.../win.lua`, so the missing `C:/Users/me/AppData/Local/nvim`
   prefix is recovered.
2. **Sequential part match** — every segment of the candidate appears **in
   order** inside the indexed path (not necessarily contiguous). This is the
   "≥ N matching folders in sequence" heuristic: it tolerates a partial leading
   segment (e.g. the `...a` fragment left of `AppData`).

The **longest** candidate that produces any hit wins, so the result is as
specific as possible and we never fall through to a bare `win.lua` that matches
half the disk. If several files match the winning candidate, the **shortest**
absolute path is preferred (`pick_best`), and commands may present a
`vim.ui.select` picker (`ask_on_ambiguous`).

For interactive selection, candidates are additionally ranked by filename
similarity (Levenshtein, `truncated.similarity_threshold`) — see
[`alternate/helpers/matcher.lua`](../lua/gopath/alternate/helpers/matcher.lua).

---

## Live fallback search

When the cache misses (cold start, file outside the scanned roots, or deeper
than `max_depth`), resolution does **not** block. The command layer:

1. shows `"[gopath] Dateisuche läuft…"`,
2. runs `finder.find_async` (async libuv walk, off the main loop),
3. opens the buffer once a match is found, or reports no match.

See [RESOLUTION.md](./RESOLUTION.md) for how this fits into the full pipeline.

---

## Refresh lifecycle

| State | Check | Action |
|-------|-------|--------|
| Never built | `last_built == nil` | build on setup (deferred ~2 s) |
| Stale | `os.time() - last_built > max_cache_age` | background rebuild |
| Periodic | every `cache_refresh_interval` s | rebuild if stale |
| On save | `auto_rebuild_on_save` | debounced rebuild |

`needs_refresh(max_age)` and `start_periodic_refresh(interval)` implement this.
Concurrent builds are prevented by a `state.building` guard.

---

## Configuration

```lua
require("gopath").setup({
  truncated = {
    enable                 = true,   -- master switch for cache + truncated resolution
    use_cache              = true,   -- consult the in-memory cache before live search
    cache_refresh_interval = 600,    -- seconds between periodic refresh checks
    max_cache_age          = 3600,   -- seconds before the cache is considered stale
    live_search_fallback   = true,   -- fall back to a live search on cache miss
    similarity_threshold   = 75,     -- 0–100; filename similarity for disambiguation
    cache_roots            = nil,    -- nil = auto-detect (cwd, stdpaths, git root)
    max_depth              = 6,      -- max directory depth per root
    excluded_dirs          = { ".git", "node_modules", "target", "build", ".cache" },
    auto_rebuild_on_save   = false,  -- rebuild (debounced) on BufWritePost
  },
})
```

Related knobs live under `tailsearch` (suffix length, ambiguity prompt, result
limit) — see the [main README](../README.md#configuration).

---

## Commands

| Command | Alias | Effect |
|---------|-------|--------|
| `:Gopath cache build` | `:GopathCacheBuild` | Rebuild the cache now (background) |
| `:Gopath cache info` | `:GopathCacheInfo` | Show indexed file count, last-built time, staleness |
| `:Gopath cache add-root <dir>` | `:GopathCacheAddRoot <dir>` | Add a scan root and rebuild |

`g?` (`:GopathDebug`) also prints cache stats for the path under the cursor.

---

## Tuning & troubleshooting

- **Truncated path won't resolve.** Run `:Gopath cache info`. If the file count
  is 0, the cache hasn't built yet (wait a moment after startup, or run
  `:Gopath cache build`). If the file lives outside the default roots, add it
  with `:Gopath cache add-root <dir>` or set `truncated.cache_roots`.
- **Resolution finds the wrong file.** Increase `tailsearch.max_components` so a
  longer, more specific suffix is tried first, and/or raise
  `similarity_threshold`.
- **Build feels heavy.** Lower `max_depth`, extend `excluded_dirs`, or pin
  `cache_roots` to just the directories you care about.
- **Want a wider net.** Set `cache_roots` explicitly (e.g. a whole project
  drive) — but note a bigger index means slower builds and a larger JSON file.

---

## Performance characteristics

Approximate, order-of-magnitude figures (hardware- and tree-dependent):

| Operation | Cost |
|-----------|------|
| Cache build, ~1 000 files | ~0.5 s (background) |
| Cache build, ~10 000 files | ~3 s (background) |
| Cache build, ~50 000 files | ~15 s (background) |
| **Cache lookup** | **< 10 ms** |
| Live search (async libuv walk) | ~100 ms – a few seconds, off the main loop |
| On-disk cache size | ~100 KB per 10 000 files |

The point of the design: builds are slow but **never block** the UI, while the
lookups you actually do interactively are effectively instant.

---

## Design notes & future ideas

- The cache is intentionally a **flat path list** with string matching rather
  than a trie/DB: it is trivial to serialize, fast enough for tens of thousands
  of entries, and easy to reason about.
- The two-strategy matcher already realizes the "enough overlap → rebuild the
  left part" idea. A natural extension is an explicit **overlap score**
  (e.g. *N consecutive matching segments*, or *1 segment + drive letter*) with a
  configurable minimum, surfaced as `truncated.min_overlap`. The suffix +
  sequential strategies are the current approximation of that.
