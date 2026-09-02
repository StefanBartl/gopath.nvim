# Integrations

gopath.nvim is a resolver, and a resolver is useful to more than the keymap
that ships with it. Two plugins in this ecosystem call it directly, and both
go through the same entry point:

```lua
require("gopath.resolve").resolve_at_cursor()  --> { kind, path, exists, … }
```

Both reach it through `pcall`, so gopath stays a soft dependency on their
side: uninstalled, each falls back to `<cfile>` and loses only the cases
`<cfile>` could never have done.

## hover.nvim — the path under the cursor, previewed

[hover.nvim](https://github.com/StefanBartl/hover.nvim) opens a float showing
whatever the cursor rests on. gopath is what makes a *truncated* path hover at
all — `...nvim/init.lua` copied out of `:messages`, a `:line:col` suffix, a
file findable only through `&path` / rtp / a tail search.

Two rules it applies to the answer, both worth knowing when a result
surprises someone:

- **A `kind == "url"` result is declined.** gopath opens URLs in a browser;
  the hover has its own URL preview and reaches it by another route.
- **`exists` must be true.** A result for something not on disk is discarded,
  and whether that absence is worth reporting is then hover's decision, not
  gopath's. A false "no such file" float is therefore **not** a gopath bug —
  it is the single most likely misattribution, because the float looks like a
  resolver verdict and is not one.

**And one measurement that belongs here rather than there.** hover asks gopath
first on an explicit request, but on its automatic `CursorHold` trigger it
asks only where gopath could plausibly help: the token contains `...` or `…`,
or it has no slash at all. That gate exists because a **failing**
`resolve_at_cursor` cost **13.2 ms** in the population an ambient trigger
produces — mostly prose that is not a path at all. Successful resolutions were
well under 500 µs.

The asymmetry is the finding: **the misses are the expensive case**, and a
consumer running on a timer cannot pay for them. If a cheap "this token cannot
resolve" early-out ever lands in this repository, that gate downstream becomes
unnecessary.

- **Consumer module:** hover.nvim `lua/hover/bare_path.lua` (`via_gopath`)
- **Their write-up:** [hover.nvim INTEGRATIONS.md](https://github.com/StefanBartl/hover.nvim/blob/main/docs/INTEGRATIONS.md)

## images.nvim — the picture under the cursor

[images.nvim](https://github.com/StefanBartl/images.nvim) uses gopath as the
third step of its `under_cursor`: markdown links first, a `<figure>` block
second, then gopath, then `<cfile>`. It keeps only results whose path carries
a configured image extension, so an LSP symbol, a `:help` subject or a URL
that gopath resolved for an unrelated reason falls through instead of
hijacking the picture.

- **Consumer module:** images.nvim `lua/images/resolve.lua`
  (`resolve_via_gopath`)
- **Their config:** `display.gopath_fallback`, default `true`

## What this means for changes here

`resolve_at_cursor` is a public entry point with consumers outside this
repository, and its **result shape is the contract**: `kind`, `path`, `exists`,
and a `:line:col` already applied. `kind = "url"` is load-bearing in
particular — both consumers use it to *decline*, not to route, so folding URLs
into another kind would silently turn two hovers into browser launches.
