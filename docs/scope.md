# What it does and what not

`gf` opens the file under the cursor, as long as the file under the cursor is
written as a path that exists relative to somewhere Neovim already knows
about. That covers a fraction of the references people actually write. A
`require("a.b.c")`, an `import` with a truncated tail, a `:help` tag, a
`file.lua:42:7` out of a stack trace — none of them are paths, and all of
them name a file.

gopath resolves them through a pipeline that tries progressively less
certain methods and stops at the first that answers:

| Phase | Uses |
| --- | --- |
| **LSP** | The language server's own definition, when there is one |
| **Treesitter** | The syntax node under the cursor, so a string is read as a string |
| **Whole-line extraction** | The line's shape — a stack-trace frame, a `:help` tag, a diagnostic |
| **Suffix search** | A truncated tail matched against the filesystem cache |
| **Fuzzy alternate** | The nearest plausible file, offered rather than opened |

Non-text targets — images, PDFs, other media — open in the system's default
application instead of being loaded as a text buffer. And if the resolved
path does not exist, gopath offers to create it rather than reporting
failure.

This is the elevator version. The exact phase order, the result type each
resolver returns, and the async open flow are in
[resolution.md](resolution.md).
