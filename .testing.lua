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
  -- Guards (testing.nvim docs/GUARDS.md). The suite passes the fs, state, scheduled-error, prompt
  -- and process guards cleanly (each spec file runs in an editor of its own), so those are errors.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    -- Real finding: lua/gopath/health.lua evaluates the deprecated vim.lsp.get_active_clients()
    -- eagerly although it is meant to be reached only when vim.lsp.get_clients is absent.
    deprecation = "warn",
    process_net = "error",
  },
  guard_allow = {
    -- lua_resolvers_spec and util_path_spec run `git` (repository root lookup) through vim.system.
    -- The python resolver specs probe the interpreter (python3 -c "import ...") through vim.system.
    spawn = { "git", "python3" },
    fs = {},
    network = {},
  },
}
