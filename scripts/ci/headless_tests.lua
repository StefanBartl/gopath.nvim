-- scripts/ci/headless_tests.lua
-- Headless CI smoke test: verifies gopath.nvim loads, `setup()` runs without
-- error, and every fixture in docs/TESTS/ is valid, side-effect-free Lua.
--
-- The docs/TESTS/*.lua files are written as manual, interactive test guides
-- (place cursor on a marked token, press a keymap, inspect the result) rather
-- than automated assertions, so this runner can't verify resolution outcomes.
-- What it *can* verify cheaply, on every push, is that the plugin still loads
-- cleanly and that none of the fixtures have bit-rotted into a syntax error
-- or a require() of a module that no longer exists.
--
-- Run via:
--   nvim --headless --noplugin -u NONE -c "lua dofile('scripts/ci/headless_tests.lua')"

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local failures = {}

---@param name string
---@param fn fun()
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print(("[ OK ] %s"):format(name))
  else
    print(("[FAIL] %s: %s"):format(name, err))
    failures[#failures + 1] = name
  end
end

check("require('gopath')", function() require("gopath") end)

check("gopath.setup({})", function() require("gopath").setup({}) end)

local tests_dir = root .. "/docs/TESTS"
local fixtures = vim.fn.globpath(tests_dir, "*.lua", false, true)
table.sort(fixtures)

if #fixtures == 0 then
  print("[FAIL] no fixtures found under docs/TESTS/")
  failures[#failures + 1] = "docs/TESTS discovery"
end

for _, path in ipairs(fixtures) do
  check("docs/TESTS/" .. vim.fn.fnamemodify(path, ":t"), function()
    local chunk = assert(loadfile(path))
    chunk()
  end)
end

if #failures > 0 then
  print(("\n%d/%d check(s) failed"):format(#failures, #fixtures + 2))
  vim.cmd("cquit 1")
else
  print(("\nAll %d checks passed."):format(#fixtures + 2))
  vim.cmd("qa!")
end
