---@meta
---@module 'gopath.@types.env_path'

---@class EnvPathOptions
---@field enable boolean
--- Whether to resolve environment variables in paths (default: true).
--- When enabled, tokens like $REPOS_DIR/foo.md or ${REPOS_DIR}/foo.md
--- are expanded before file resolution.
---@field shorten_vars string[]
--- Env vars tried, in order, by :GopathToReposDir / :Gopath to-repos-dir —
--- the reverse direction: an absolute path on the current line matching one
--- of these variables' values is rewritten back to `$VAR`.
--- Default: { "REPOS_DIR" }.

---@class EnvPathResult
---@field raw string    The original token before expansion (e.g., "$REPOS_DIR/foo.md")
---@field expanded string  The expanded absolute path
---@field var_name string  The environment variable name that was resolved
---@field var_value string The resolved value of the variable
