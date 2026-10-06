-- .testing.lua -- configuration of testing.nvim for this project.
-- Keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "gopath",
  -- The automated suites live in scripts/ci (TESTS/ holds manual guides, see TESTS/README.md).
  roots = { "scripts/ci" },
  -- The 19 `return function(H)` specs are named *_spec.lua; the two self-running scripts that the
  -- CI used to start one by one are named explicitly.
  spec_pattern = {
    "_spec%.lua$",
    "^scripts/ci/headless_tests%.lua$",
    "^scripts/ci/functional_tests%.lua$",
  },
  -- The specs run on scripts/ci/harness.lua (found upwards from scripts/ci/specs); the two scripts
  -- run in a process of their own.
  dialect = {
    ["scripts/ci/specs/*"] = "h",
    ["*"] = "script",
  },
  deps = { "lib.nvim" },
  -- One editor per file, started like the old CI line (`-c "lua dofile(...)"`): the specs use
  -- vim.fn.expand("<cfile>"), which raises under `nvim -l`.
  isolated = "file",
  host = "c",
}
