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

## Developer notes

For contributors and people extending gopath.

| Topic | Page |
|-------|------|
| Architecture, providers, resolvers, custom resolvers | [Developer-Notes/DEV-README.md](./Developer-Notes/DEV-README.md) |
| Location parsing (`:line:col`, `(line)`, `+line`) | [Developer-Notes/util/location.md](./Developer-Notes/util/location.md) |

## Test scripts

Manual / scratch test scripts exercising individual resolvers
([TESTS/](./TESTS)):

- [`01_linepath.lua`](./TESTS/01_linepath.lua) — whole-line path extraction
- [`02_tailsearch.lua`](./TESTS/02_tailsearch.lua) — suffix-based search
- [`03_gopath_cmd.lua`](./TESTS/03_gopath_cmd.lua) — `:Gopath` command
- [`04_stack_traces.lua`](./TESTS/04_stack_traces.lua) — stacktrace patterns
