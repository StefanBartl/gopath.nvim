# Filesystem cache

The subsystem that powers fast [suffix-based search](NAVIGATION.md) on
truncated/partial paths — the kind produced by error messages, stack
traces, and logs — without freezing the editor. Full walkthrough in
[`../cache.md`](../cache.md).

## Background filesystem index

Scans configured roots (cwd, Neovim config/data/cache dirs, git repo root
by default) once in the background via a bounded-concurrency libuv
`fs_scandir` walk — at most `max_concurrency` (16) directory reads in
flight, subdirectories queued rather than recursed immediately, so open
handles stay bounded regardless of tree size. Every subsequent lookup then
answers from the in-memory index in well under 10ms instead of walking the
filesystem live.

- **Module:** `truncated/cache.lua`, `truncated/finder.lua`
- **Usercmds:** `:Gopath cache build`, `:GopathCacheBuild` (rebuild),
  `:Gopath cache info`, `:GopathCacheInfo` (statistics),
  `:Gopath cache add-root <dir>`, `:GopathCacheAddRoot <dir>` (extend
  search roots) — all require `opts.truncated.enable = true`
- **Completion:** `<dir>` is declared `type = "DIR"` on the composer route, so
  `<Tab>` offers directories and a non-directory is rejected before the
  handler runs. The alias sets `complete = "dir"` for the same effect.
- **Config:** `opts.truncated.enable` (default `true`),
  `opts.truncated.cache_roots` (default: auto-detected), `opts.truncated.
  max_depth` (default `6`), `opts.truncated.excluded_dirs` (`.git`,
  `.github`, `node_modules`, `target`, `build`, `.cache`, `venv`)

## Tail reconstruction

Given a truncated tail like `lua/config/neotree/open/win.lua`, tries
progressively shorter suffix candidates (longest first, up to
`max_components`) against the indexed paths, using an exact-suffix match
first and a sequential (not necessarily contiguous) segment match as a
fallback — so a leading partial segment like `...a/AppData` still
resolves. The longest candidate that produces any hit wins; ties are
broken toward the shortest absolute path, or a `vim.ui.select` picker when
`ask_on_ambiguous = true`.

- **Module:** `resolvers/common/tailsearch.lua`, `truncated/cache.lua`
  (`search`)

## On-disk persistence

The in-memory index (`state.paths`) is mirrored to a versioned JSON file
at `stdpath("cache") .. "/gopath_fs_cache.json"`, loaded on startup so the
very first lookup of a session is already fast, and rewritten after every
rebuild.

- **Module:** `truncated/cache.lua`

## Refresh lifecycle

| State | Trigger | Action |
|---|---|---|
| Never built | `last_built == nil` | build on setup, deferred ~2s |
| Stale | `os.time() - last_built > max_cache_age` | background rebuild |
| Periodic | every `cache_refresh_interval` seconds | rebuild if stale |
| On save | `auto_rebuild_on_save = true` | debounced rebuild, matching `watch_patterns` |
| Manual | `:Gopath cache build` | immediate rebuild |

A `state.building` guard prevents concurrent builds.

- **Config:** `opts.truncated.use_cache` (default `true`),
  `opts.truncated.cache_refresh_interval` (default `600`),
  `opts.truncated.max_cache_age` (default `3600`),
  `opts.truncated.auto_rebuild_on_save` (default `false`),
  `opts.truncated.watch_patterns` (default `*.lua`, `*.vim`)

## Live fallback search

On a cache miss (cold start, file outside scanned roots, or deeper than
`max_depth`), resolution doesn't block: it shows a "search running"
message, runs an async libuv walk with early-exit once enough matches are
found, and opens the buffer once found or reports no match.

- **Module:** `truncated/finder.lua`
- **Config:** `opts.truncated.live_search_fallback` (default `true`)

## `BufWritePost` cache invalidation

A lightweight autocommand (always on, separate from the heavier
`auto_rebuild_on_save` rebuild) drops the directory-listing caches that
back non-truncated path lookups (`gF` etc.) whenever a buffer is written,
since a save is the usual way a new file appears mid-session.

- **Module:** `bindings/autocmds.lua`, `util/path.lua`
