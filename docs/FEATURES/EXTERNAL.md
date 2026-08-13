# External files

## External file opening

Images, PDFs, and other media files resolved by gopath open automatically
in the system default application instead of as a text buffer.
`opts.external.extensions` extends the built-in extension list (does not
replace it).

- **Module:** `external/init.lua`, `external/helpers/detector.lua`
- **Config:** `opts.external.enable` (default `true`),
  `opts.external.extensions` (default `nil`, extends the built-in list)

## Opener fallback chain

Three-stage fallback for actually launching the external application, each
stage falling through to the next on dispatch failure rather than only
when the stage is merely unavailable:
[open.nvim](https://github.com/StefanBartl/open.nvim)'s `default` handler
(if installed) → lib.nvim's cross-platform system opener → a minimal
built-in per-OS opener (`open`/`xdg-open`/`explorer.exe`).

- **Module:** `external/helpers/opener.lua`
