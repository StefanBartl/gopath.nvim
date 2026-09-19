-- scripts/ci/unit_tests.lua
-- Headless CI unit/behaviour suite: runs every spec under scripts/ci/specs/.
--
-- Complements the two older runners rather than replacing them:
--   * scripts/ci/headless_tests.lua  — loads the plugin and syntax-checks the
--     manual fixture guides in TESTS/.
--   * scripts/ci/functional_tests.lua — end-to-end resolution cases for the
--     Lua resolvers, URLs, frecency and the config merge.
--   * this file — per-module coverage of the rest: path/url/location helpers,
--     the config merge, every language resolver, the line extractor, the
--     truncated-path cache and finder, tailsearch, alternate, external/PDF
--     routing, create-on-missing, the open layer, commands, bindings, health.
--
-- No spec here starts a subprocess or touches the network. The four sites that
-- would (`external.helpers.opener`, `external.helpers.revealer`,
-- `tailsearch.git_root`, `truncated.finder.search_root`) are cut at a seam and
-- asserted on the argv they *would* have spawned.
--
-- Requires lib.nvim on the runtimepath (a hard gopath.nvim dependency).
--
-- Run via:
--   nvim --headless --noplugin -u NONE \
--     -c "set rtp+=<path-to-lib.nvim>" \
--     -c "lua dofile('scripts/ci/unit_tests.lua')"
--
-- A single spec can be run with GOPATH_SPEC=<substring>, e.g.
--   GOPATH_SPEC=tailsearch nvim --headless ... -c "lua dofile('scripts/ci/unit_tests.lua')"

local root = vim.fn.getcwd()
vim.opt.runtimepath:prepend(root)

local H = dofile(root .. "/scripts/ci/harness.lua")

require("gopath").setup({})

local filter = vim.env.GOPATH_SPEC
local spec_dir = root .. "/scripts/ci/specs"

-- `vim.fn.globpath` reads its directory argument as a glob PATTERN, not a
-- path -- fatal on Windows when the checkout sits under an 8.3 short name
-- (`C:/Users/STEFAN~1/...`, which any profile name over eight characters
-- gets from a `getcwd()`/`%TEMP%`-derived path): glob tries `~1` as a
-- home-directory reference, finds no such user, and answers an empty list
-- with no error, misreported below as "no specs found" (XP-01). `vim.fs.dir`
-- takes `spec_dir` as an actual path, so no directory spelling can be
-- misread as pattern syntax.
local specs = {}
for name, typ in vim.fs.dir(spec_dir) do
  if typ == "file" and name:sub(-4) == ".lua" then specs[#specs + 1] = spec_dir .. "/" .. name end
end
table.sort(specs)

if #specs == 0 then
  print("[FAIL] no specs found under scripts/ci/specs/")
  vim.cmd("cquit 1")
  return
end

local ran = 0
for _, path in ipairs(specs) do
  local name = vim.fn.fnamemodify(path, ":t:r")
  if not filter or name:find(filter, 1, true) then
    ran = ran + 1
    print(("\n--- %s ---"):format(name))
    local ok_load, spec = pcall(dofile, path)
    if not ok_load or type(spec) ~= "function" then
      print(("[FAIL] %s failed to load: %s"):format(name, tostring(spec)))
      H.failures[#H.failures + 1] = name .. " (load)"
    else
      -- A spec that throws outside any check() would otherwise skip the rest
      -- of its file silently; report it as one failure and carry on.
      local ok_run, err = pcall(spec, H)
      if not ok_run then
        print(("[FAIL] %s aborted: %s"):format(name, tostring(err)))
        H.failures[#H.failures + 1] = name .. " (aborted)"
      end
    end
  end
end

print(("\n%d spec file(s), %d check(s), %d assertion(s)"):format(ran, H.checks, H.assertions))

if #H.failures > 0 then
  print(("%d check(s) failed:"):format(#H.failures))
  for _, name in ipairs(H.failures) do
    print("  - " .. name)
  end
  vim.cmd("cquit 1")
else
  print("All checks passed.")
  vim.cmd("qa!")
end
