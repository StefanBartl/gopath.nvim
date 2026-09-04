# gopath.nvim — Documentation

Index of the `docs/` folder. Start at the [project README](../README.md) for
installation, keymaps and configuration; the pages below go deeper on the
individual subsystems.

## Getting it running

| Topic | Page |
|-------|------|
| lazy.nvim and packer snippets, optional dependencies, the CLI tools that speed up a tail search | [installation.md](./installation.md) |
| Every `setup()` option with its default | [configuration.md](./configuration.md) |
| `:checkhealth gopath`, and what to do when nothing jumps | [troubleshooting.md](./troubleshooting.md) |

## Using it

| Topic | Page |
|-------|------|
| Day to day: which keymap to reach for, when to trust the cache, and the five places gopath guesses | [WORKFLOW.md](./WORKFLOW.md) |
| Keymap / user command / autocommand cheatsheet, including the whole `:Gopath` subcommand tree | [BINDINGS.md](./BINDINGS.md) |
| The feature catalogue, one page per theme | [FEATURES/](./FEATURES/README.md) |

## How it works

Deep dives into the more complex subsystems. Each has a short catalogue entry
in [`FEATURES/`](./FEATURES/README.md); these are the long versions.

| Topic | Page |
|-------|------|
| Filesystem cache & truncated-path resolution | [cache.md](./cache.md) |
| Resolution pipeline (cursor → opened file) | [resolution.md](./resolution.md) |
| Lua symbol & require resolution | [lua-symbols.md](./lua-symbols.md) |
| Plugins that call `resolve_at_cursor` from outside | [FEATURES/INTEGRATIONS.md](./FEATURES/INTEGRATIONS.md) |

## Developer notes

For contributors and people extending gopath.

| Topic | Page |
|-------|------|
| Architecture, providers, resolvers, custom resolvers | [Developer-Notes/DEV-README.md](./Developer-Notes/DEV-README.md) |
| Location parsing (`:line:col`, `(line)`, `+line`) | [Developer-Notes/util/location.md](./Developer-Notes/util/location.md) |

## CI

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs on every push
and PR: `stylua --check`, `luacheck`, and a headless smoke test
([`scripts/ci/headless_tests.lua`](../scripts/ci/headless_tests.lua)) that
boots gopath and executes every `TESTS/*.lua` fixture as a plain Lua
chunk to catch load-time regressions.

## Test scripts

Manual / scratch test scripts exercising individual resolvers
([TESTS/](../TESTS)):

- [`01_linepath.lua`](../TESTS/01_linepath.lua) — whole-line path extraction
- [`02_tailsearch.lua`](../TESTS/02_tailsearch.lua) — suffix-based search
- [`03_gopath_cmd.lua`](../TESTS/03_gopath_cmd.lua) — `:Gopath` command
- [`04_stack_traces.lua`](../TESTS/04_stack_traces.lua) — stacktrace patterns
- [`05_direct_symbol_jump.lua`](../TESTS/05_direct_symbol_jump.lua) — direct symbol/definition jumps
