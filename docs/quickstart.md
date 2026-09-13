# Quickstart

Put the cursor on a `require("a.b")`, a file path, a `:help` tag or a
stack-trace line, and press:

```
gP
```

That is the whole plugin. If the resolved path does not exist, gopath offers
to create it.

The command tree does the same jobs without keymaps, and answers a few
questions keymaps cannot:

```vim
:Gopath open vsplit    " resolve and open in a vertical split
:Gopath copy           " copy path:line:col to the clipboard
:Gopath check          " does the path under the cursor exist? offer to create
:Gopath debug          " print the resolution chain to :messages
:Gopath cache build    " warm the filesystem cache for truncated tails
```

Verify your setup any time with:

```vim
:checkhealth gopath
```

From here: [What you get with the defaults](what-you-get.md) for the full
keymap table, or [What it does and what not](scope.md) for the resolution
pipeline at a glance.
