# gopath.nvim — module map

> **Generated** by `documentation`. Do not edit by hand — run `:DocMap`
> (or `nvim --headless -l scripts/gen_map.lua`) to regenerate.

**7 modules** · 17 namespaces · 56 helper files

The [interactive map](index.html) has filtering, full descriptions and
source links; this page is the version the code host renders directly.


## Namespaces

```mermaid
flowchart LR
  nlua["gopath.nvim"]
  nlua_gopath["gopathbr/smallMain entry point called by package managers…/small"]
  nlua_gopath_alternate["alternatebr/smallAttempts to find similar files in the…/small"]
  nlua_gopath_bindings["bindingsbr/smalloptional which-key label./small"]
  nlua_gopath_config["configbr/smallOwns a single module-level state table that…/small"]
  nlua_gopath_external["externalbr/smallOpen files with external applications…/small"]
  nlua_gopath_open["openbr/smallReplaces the previous per-mode openers…/small"]
  nlua_gopath_providers["providers"]
  nlua_gopath_resolvers["resolvers"]
  nlua_gopath_truncated["truncatedbr/smallHandles paths like:…/small"]
  nlua_gopath_util["util"]
  nlua --> nlua_gopath
  nlua_gopath --> nlua_gopath_alternate
  nlua_gopath --> nlua_gopath_bindings
  nlua_gopath --> nlua_gopath_config
  nlua_gopath --> nlua_gopath_external
  nlua_gopath --> nlua_gopath_open
  nlua_gopath --> nlua_gopath_providers
  nlua_gopath --> nlua_gopath_resolvers
  nlua_gopath --> nlua_gopath_truncated
  nlua_gopath --> nlua_gopath_util
```


## Dependencies

Which parts of the tree require which, rolled up to the second level.
The [interactive map](index.html)'s **Deps** view has this per module,
in both directions, with load-time and lazy requires told apart.

```mermaid
flowchart LR
  nlua_gopath_alternate["gopath.alternate"]
  nlua_gopath_bindings["gopath.bindings"]
  nlua_gopath_commands_lua["gopath.commands"]
  nlua_gopath_config["gopath.config"]
  nlua_gopath_create_lua["gopath.create"]
  nlua_gopath_external["gopath.external"]
  nlua_gopath_health_lua["gopath.health"]
  nlua_gopath_open["gopath.open"]
  nlua_gopath_providers["providers"]
  nlua_gopath_registry_lua["gopath.registry"]
  nlua_gopath_resolve_lua["gopath.resolve"]
  nlua_gopath_resolvers["resolvers"]
  nlua_gopath_truncated["gopath.truncated"]
  nlua_gopath_util["util"]
  nlua_gopath_bindings --> nlua_gopath_commands_lua
  nlua_gopath_bindings --> nlua_gopath_truncated
  nlua_gopath_bindings --> nlua_gopath_util
  nlua_gopath_commands_lua --> nlua_gopath_alternate
  nlua_gopath_commands_lua --> nlua_gopath_config
  nlua_gopath_commands_lua --> nlua_gopath_create_lua
  nlua_gopath_commands_lua --> nlua_gopath_open
  nlua_gopath_commands_lua --> nlua_gopath_providers
  nlua_gopath_commands_lua --> nlua_gopath_resolve_lua
  nlua_gopath_commands_lua --> nlua_gopath_resolvers
  nlua_gopath_commands_lua --> nlua_gopath_truncated
  nlua_gopath_commands_lua --> nlua_gopath_util
  nlua_gopath_create_lua --> nlua_gopath_config
  nlua_gopath_create_lua --> nlua_gopath_util
  nlua_gopath_external --> nlua_gopath_config
  nlua_gopath_external --> nlua_gopath_util
  nlua_gopath_health_lua --> nlua_gopath_config
  nlua_gopath_health_lua --> nlua_gopath_truncated
  nlua_gopath_open --> nlua_gopath_create_lua
  nlua_gopath_open --> nlua_gopath_external
  nlua_gopath_open --> nlua_gopath_util
  nlua_gopath_providers --> nlua_gopath_util
  nlua_gopath_registry_lua --> nlua_gopath_config
  nlua_gopath_registry_lua --> nlua_gopath_resolvers
  nlua_gopath_registry_lua --> nlua_gopath_util
  nlua_gopath_resolve_lua --> nlua_gopath_config
  nlua_gopath_resolve_lua --> nlua_gopath_registry_lua
  nlua_gopath_resolve_lua --> nlua_gopath_resolvers
  nlua_gopath_resolve_lua --> nlua_gopath_util
  nlua_gopath_resolvers --> nlua_gopath_config
  nlua_gopath_resolvers --> nlua_gopath_external
  nlua_gopath_resolvers --> nlua_gopath_providers
  nlua_gopath_resolvers --> nlua_gopath_truncated
  nlua_gopath_resolvers --> nlua_gopath_util
  nlua_gopath_truncated --> nlua_gopath_alternate
  nlua_gopath_truncated --> nlua_gopath_config
  nlua_gopath_truncated --> nlua_gopath_util
  nlua_gopath_util --> nlua_gopath_config
```


## Modules

| Module | Description | Fns | Docs |
|---|---|---|---|
| `gopath` | Main entry point called by package managers (lazy.nvim, packer, …). | 3 | [src](../../lua/gopath/init.lua) |
| &nbsp;&nbsp;`gopath.alternate` | Attempts to find similar files in the target directory and presents them via interactive selection. | 2 | [src](../../lua/gopath/alternate/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`helpers` |  |  |  |
| &nbsp;&nbsp;`gopath.bindings` | optional which-key label. | 1 | [src](../../lua/gopath/bindings/init.lua) |
| &nbsp;&nbsp;`gopath.config` | Owns a single module-level state table that is populated once by `setup()` and read-only afterwards via `get()`. | 3 | [src](../../lua/gopath/config/init.lua) |
| &nbsp;&nbsp;`gopath.external` | Open files with external applications (images, PDFs, URLs, etc.). | 2 | [src](../../lua/gopath/external/init.lua) |
| &nbsp;&nbsp;&nbsp;&nbsp;`helpers` |  |  |  |
| &nbsp;&nbsp;`gopath.open` | Replaces the previous per-mode openers (edit/window/vsplit/tab). | 2 | [src](../../lua/gopath/open/init.lua) |
| &nbsp;&nbsp;`providers` |  |  |  |
| &nbsp;&nbsp;`resolvers` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`c` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`common` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;`extractor` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`csharp` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`go` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`java` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`javascript` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`lua` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`python` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`rust` |  |  |  |
| &nbsp;&nbsp;&nbsp;&nbsp;`zig` |  |  |  |
| &nbsp;&nbsp;`gopath.truncated` | Handles paths like: "...AppData\Local\nvim\init.lua:42" or "…/lua/config/init.lua". | 5 | [src](../../lua/gopath/truncated/init.lua) |
| &nbsp;&nbsp;`util` |  |  |  |

## Drift

0 errors · 0 warnings · 14 info

No errors or warnings.


<details>
<summary>14 informational findings</summary>


| Check | Message |
|---|---|
| `missing-readme` | lua/gopath has no README.md |
| `missing-readme` | lua/gopath/alternate has no README.md |
| `missing-readme` | lua/gopath/bindings has no README.md |
| `missing-readme` | lua/gopath/config has no README.md |
| `missing-readme` | lua/gopath/external has no README.md |
| `missing-readme` | lua/gopath/open has no README.md |
| `missing-readme` | lua/gopath/truncated has no README.md |
| `undocumented-param` | has_name has 2 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.safe_notify_defer has 4 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.safe_notify has 5 parameter(s) but only 0 @param line(s) |
| `undocumented-param` | M.safe_notify_schedule has 3 parameter(s) but only 0 @param line(s) |
| `unreferenced-module` | gopath is required by no other file in the tree |
| `unreferenced-module` | gopath.health is required by no other file in the tree |
| `unreferenced-module` | gopath.truncated is required by no other file in the tree |

</details>
