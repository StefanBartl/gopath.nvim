# External files

## External file opening

Images, PDFs, and other media files resolved by gopath open automatically
in the system default application instead of as a text buffer.
`opts.external.extensions` extends the built-in extension list (does not
replace it).

- **Module:** `external/init.lua`, `external/helpers/detector.lua`
- **Config:** `opts.external.enable` (default `true`),
  `opts.external.extensions` (default `nil`, extends the built-in list)

## URLs

A URL under the cursor is opened in the browser instead of being turned into a
file path. This is what makes `gP` (and any keymap bound to it, e.g. `gF` or
`<2-LeftMouse>`) work on links in `:messages`, notification buffers, comments,
markdown docs and terminal output.

Two recognition strengths, deliberately placed at different points of the
resolve pipeline:

| Strength | Matches | Runs |
|---|---|---|
| strict | explicit scheme (`https://`, `ftp://`, `file://`, `mailto:`) or a `www.` prefix | before every file resolver — no local path can be spelled this way |
| loose | bare host with a known TLD (`github.com/neovim/neovim`), scp-style git remote (`git@github.com:foo/bar.git`) | after every file resolver missed — a real `notes.info` on disk still wins |

The URL is read from the raw buffer line, not from `<cfile>`: `'isfname'` stops
at `?`, `&` and `#`, which would silently truncate every URL carrying a query
string or fragment. Wrapping delimiters and trailing sentence punctuation are
stripped (`(https://x).` → `https://x`), balanced pairs inside the URL are kept.
Scheme-less targets are normalized (`www.google.com` → `https://www.google.com`,
`git@github.com:foo/bar.git` → `https://github.com/foo/bar`).

Results carry `kind = "url"` and `exists = true`, so they never enter the
create-on-missing flow — this is the fix for `gF` on a link offering to create
`<cwd>/https:/example.com/...`.

- **Module:** `resolvers/common/url.lua`, `util/url.lua`
- **Config:** `opts.url.enable` (default `true`),
  `opts.url.bare_hosts` (default `true`, set `false` to require an explicit
  scheme), `opts.url.schemes` / `opts.url.tlds` (default `nil`, both extend the
  built-in lists)

## Opener fallback chain

Three-stage fallback for actually launching the external application, each
stage falling through to the next on dispatch failure rather than only
when the stage is merely unavailable:
[open.nvim](https://github.com/StefanBartl/open.nvim)'s `default` handler
(if installed) → lib.nvim's cross-platform system opener → a minimal
built-in per-OS opener (`open`/`xdg-open`/`explorer.exe`).

- **Module:** `external/helpers/opener.lua`
