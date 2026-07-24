# gopath.nvim — Documentation

Index of the `docs/` folder. Start at the [project README](../README.md) for
installation, keymaps and configuration; the pages below go deeper on the
individual subsystems.

## User guides (EN / DE)

Deep dives into the more complex features, available in English and German.

| Topic | English | Deutsch |
|-------|---------|---------|
| Filesystem cache & truncated-path resolution | [CACHE.md](./CACHE.md) | [CACHE-DE.md](./CACHE-DE.md) |
| Resolution pipeline (cursor → opened file) | [RESOLUTION.md](./RESOLUTION.md) | [RESOLUTION-DE.md](./RESOLUTION-DE.md) |
| Lua symbol & require resolution | [LUA-SYMBOLS.md](./LUA-SYMBOLS.md) | [LUA-SYMBOLS-DE.md](./LUA-SYMBOLS-DE.md) |

## Reference

| Topic | Page |
|-------|------|
| Keymap / user command / autocommand cheatsheet | [BINDINGS.md](./BINDINGS.md) |
| Roadmap & checklist audits | [ROADMAP.md](./ROADMAP.md) |

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
boots gopath and executes every `docs/TESTS/*.lua` fixture as a plain Lua
chunk to catch load-time regressions.

## Test scripts

Manual / scratch test scripts exercising individual resolvers
([TESTS/](./TESTS)):

- [`01_linepath.lua`](./TESTS/01_linepath.lua) — whole-line path extraction
- [`02_tailsearch.lua`](./TESTS/02_tailsearch.lua) — suffix-based search
- [`03_gopath_cmd.lua`](./TESTS/03_gopath_cmd.lua) — `:Gopath` command
- [`04_stack_traces.lua`](./TESTS/04_stack_traces.lua) — stacktrace patterns
- [`05_direct_symbol_jump.lua`](./TESTS/05_direct_symbol_jump.lua) — direct symbol/definition jumps
