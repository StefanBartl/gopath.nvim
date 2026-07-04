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
| `gY` | n | `copy_location` | Copy `path:line:col` to clipboard |
| `g?` | n | `debug` | Print resolution chain to `:messages` |
| `<leader>pp` | n | `probe` | Probe path under cursor (suffix search, vsplit) |
| `<leader>pp` | v | `probe` | Probe selected text (suffix search, vsplit) |

Set any config key to `false` to disable that single mapping, or
`mappings = false` to disable all of them. Values may be a single lhs string
or a list of lhs strings (`{ "gP", "<leader>gp" }`).

---

## User Commands

### `:Gopath` subcommand tree

`:Gopath <subcommand> [args…]` — tab-completion works at every level.

| Subcommand | Args | Action |
| --- | --- | --- |
| `open` | `[edit\|split\|vsplit\|tab]` | Resolve and open |
| `copy` | — | Copy `path:line:col` to clipboard |
| `debug` | — | Print resolution chain to `:messages` |
| `probe` | `[edit\|split\|vsplit]` | Probe path under cursor / selection |
| `cache build` | — | Rebuild filesystem index |
| `cache info` | — | Show cache statistics |
| `cache add-root` | `<dir>` | Add directory to cache search roots |

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
| `:GopathProbe[!]` | `:Gopath probe` (`!` = split) | always on |
| `:GopathCacheBuild` | `:Gopath cache build` | requires `truncated.enable` |
| `:GopathCacheInfo` | `:Gopath cache info` | requires `truncated.enable` |
| `:GopathCacheAddRoot <dir>` | `:Gopath cache add-root <dir>` | requires `truncated.enable` |

`commands = false` disables every user command, including the `:Gopath`
dispatcher itself.

---

## Autocommands

One opt-in autocommand, registered from `lua/gopath/bindings/autocmds.lua`:

| Event | Group | Enabled when | Action |
| --- | --- | --- | --- |
| `BufWritePost` | `GopathCacheAutoRebuild` | `truncated.auto_rebuild_on_save = true` | Debounced (≤ once/5min) filesystem cache rebuild, matching `truncated.watch_patterns` (default `*.lua`, `*.vim`) |

Disabled by default (`auto_rebuild_on_save = false`).

---

## which-key

which-key.nvim is a soft dependency (`lua/gopath/bindings/which_key.lua`):
when installed and `which_key ~= false` in config, the `probe` keymap gets a
`"gopath: probe path under cursor/selection"` label in both normal and
visual mode. No-op if which-key.nvim is not installed. `:checkhealth gopath`
reports whether it was detected.

---
