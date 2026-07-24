std = "luajit"
cache = true

-- "vim" itself is mutable (fields like vim.g.* are commonly assigned by
-- plugins), so it must live in `globals`, not `read_globals`.
globals = {
  "vim",
}

exclude_files = {
  "docs/TESTS/*.lua",
}

-- Long lines are handled by stylua's column_width; don't duplicate the check here.
max_line_length = false
