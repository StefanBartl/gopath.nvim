# gopath.nvim — Binding Cheatsheet

Machine-readable overview of every keymap, user command, and autocommand
defined by `gopath.nvim`. This file is documentation only and mirrors the
source of truth in `lua/gopath/bindings/` (`keymaps.lua`, `usrcmds.lua`,
`autocmds.lua`, `which_key.lua`). Any change there must be reflected here.

All keymaps and commands are individually configurable (or fully disabled)
via `require("gopath").setup({ mappings = ..., commands = ... })`. See
README.md → Configuration for the exact option shapes.

## Table of content

  - [Keymaps](#keymaps)
  - [User Commands](#user-commands)
    - [`:Gopath` subcommand tree](#gopath-subcommand-tree)
    - [Individual aliases](#individual-aliases)
  - [Autocommands](#autocommands)
  - [which-key](#which-key)

---

## Keymaps

| lhs | mode | config key | action |
| --- | --- | --- | --- |
| `gP` | n | `open_here` | Resolve and open in current window |
| `g\|` | n | `open_split` | Resolve and open in horizontal split |
| `g\` | n | `open_vsplit` | Resolve and open in vertical split |
| `g}` | n | `open_tab` | Resolve and open in new tab |
| `gM` | n | `open_explorer` | Reveal target in the system file manager (Explorer/Finder/…) instead of opening it |
| `gY` | n | `copy_location` | Copy `path:line:col` to clipboard |
| `g?` | n | `debug` | Print resolution chain to `:messages` |
| `gC` | n | `check` | Check path under cursor exists; offer to create if missing (does not open on hit) |
| `<leader>pp` | n | `probe` | Probe path under cursor (suffix search, vsplit) |
| `<leader>pp` | v | `probe` | Probe selected text (suffix search, vsplit) |

Set any config key to `false` to disable that single mapping, or
`mappings = false` to disable all of them. Values may be a single lhs string
or a list of lhs strings (`{ "gP", "<leader>gp" }`).

`open_explorer` (`gM`) is the odd one out: it never opens a buffer, so it does
not go through create-on-missing or the external-opener heuristic below — it
warns instead of prompting when the resolved path does not exist. Backed by
[lib.nvim's `cross.reveal_in_fm`](https://github.com/StefanBartl/lib.nvim),
falling back to a minimal built-in per-OS reveal
(`explorer.exe /select,`/`open -R`/`xdg-open`) when lib.nvim is absent.

### Create-on-missing

When `open_here`/`open_split`/`open_vsplit`/`open_tab` resolve to a path that
does not exist (and the fuzzy-alternate fallback in
`gopath.commands.finish_open` also comes up empty), `gopath.open` calls
`gopath.create.offer()`: a button dialog (lib.nvim's `ui.kit.confirm`,
falling back to `vim.ui.select` when lib.nvim is absent) asking to create the
file. "Create file" creates it (+ parent dirs via `mkdir -p`) and re-opens it
in the originally requested window mode, jumping to `res.range` if present.

There is **no** automatic "open nearest existing folder" fallback — a
directory can't be opened in a buffer the way a file can. Instead, when the
unresolved path has an existing ancestor directory *and*
[filetree.nvim](https://github.com/StefanBartl/filetree.nvim) is installed
and set up, the dialog offers a second button, **"Open in filetree"**: sets
cwd to that directory and roots/focuses filetree.nvim's tree there.

Config: `create_on_missing = { enable = true, confirm = true }`.
- `enable = false` restores the old "File not found" error for the passive
  open keymaps only. The `check` keymap/command still offers to create
  (explicit user action, bypasses the opt-out).
- `confirm = false` skips the dialog and creates the file silently whenever
  offered (no "Open in filetree" choice in this mode).

---

## User Commands

### `:Gopath` subcommand tree

`:Gopath <subcommand> [args…]` — built via
[`lib.nvim.bindings.usercmd.composer`](https://github.com/StefanBartl/lib.nvim),
tab-completion works at every level. `cache *` subcommands only appear when
`truncated.enable = true` in config.

| Subcommand | Args | Action |
| --- | --- | --- |
| `open` | `[edit\|split\|vsplit\|tab\|explorer]` | Resolve and open (`explorer` reveals in the file manager instead) |
| `copy` | — | Copy `path:line:col` to clipboard |
| `debug` | — | Print resolution chain to `:messages` |
| `probe` | `[edit\|split\|vsplit]` | Probe path under cursor / selection |
| `check` | — | Check path under cursor exists; offer to create if missing |
| `cache build` | — | Rebuild filesystem index |
| `cache info` | — | Show cache statistics |
| `cache add-root` | `<dir>` | Add directory to cache search roots |

`<Tab>` completes subcommands throughout, and `cache add-root`'s `<dir>`
completes directories — it is declared as a `DIR` argument, so the composer
derives both its completion and its validation from that one declaration. The
`:GopathCacheAddRoot` alias below completes the same way.

### Individual aliases

Kept for backward compatibility; each is a thin wrapper around the
`:Gopath` dispatcher above and can be disabled independently via
`config.commands`.

| Alias | Equivalent | Config key |
| --- | --- | --- |
| `:GopathResolve` | `:Gopath debug` | `resolve` |
| `:GopathOpen [mode]` | `:Gopath open [mode]` | `open` |
| `:GopathCopy` | `:Gopath copy` | `copy` |
| `:GopathDebug` | `:Gopath debug` | `debug` |
| `:GopathCheck` | `:Gopath check` | `check` |
| `:GopathProbe[!]` | `:Gopath probe` (`!` = split) | always on |
| `:GopathCacheBuild` | `:Gopath cache build` | requires `truncated.enable` |
| `:GopathCacheInfo` | `:Gopath cache info` | requires `truncated.enable` |
| `:GopathCacheAddRoot <dir>` | `:Gopath cache add-root <dir>` | requires `truncated.enable` |

`commands = false` disables every user command, including the `:Gopath`
dispatcher itself.

---

## Autocommands

Two autocommands, registered from `lua/gopath/bindings/autocmds.lua`:

| Event | Group | Enabled when | Action |
| --- | --- | --- | --- |
| `BufWritePost` | `GopathPathCacheInvalidate` | always | Drop the path-lookup directory caches (`path.invalidate_caches`) |
| `BufWritePost` | `GopathCacheAutoRebuild` | `truncated.auto_rebuild_on_save = true` | Debounced (≤ once/5min) filesystem cache rebuild, matching `truncated.watch_patterns` (default `*.lua`, `*.vim`) |

The second is disabled by default (`auto_rebuild_on_save = false`).

The first is always on and deliberately cheap — it only clears three variables.
`gopath.util.path` caches a directory listing per search root so that `gF` does
not stat the filesystem on every keypress; writing a buffer is the usual way a
new file appears mid-session, so a write invalidates those listings. Files
created by gopath's own create-on-missing invalidate directly from
`gopath.create`, and installing a plugin moves the runtimepath, which the caches
key on. See [Resolution](resolution.md#path-lookup-caching).

---

## which-key

which-key.nvim is a soft dependency. Per-key labels need no registration at
all: which-key reads the mappings itself and labels each from its own `desc`,
which every gopath mapping carries. gopath used to register the `probe`
description a second time, which only gave the same string two places to
drift apart in.

What which-key cannot work out for itself is the *group* label. gopath's keys
are single `g`-prefixed ones except `probe`, which sits under the user's
`<leader>` prefix — so that prefix is the one thing handed over, and only when
`probe` is actually configured. `which_key = false` in config opts out of the
label while leaving every mapping and its description in place. Declared in
the keymap spec (`lua/gopath/bindings/keymaps.lua`) and applied by
`lib.nvim.bindings.keymap`. `:checkhealth gopath` reports whether which-key
was detected.

---
