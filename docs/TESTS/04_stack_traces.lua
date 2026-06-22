-- docs/TESTS/04_stack_traces.lua
-- Real-world error / stacktrace lines for testing linepath + tailsearch.
-- Press gP with cursor anywhere on a line to attempt resolution.
-- Expected: Neovim opens the referenced file at the correct line.

-- ── Neovim Lua stacktrace ────────────────────────────────────────────────────
local _01 = "E5113: Error while calling lua chunk: ...AppData/Local/nvim/init.lua:14: module 'pickers' not found"
local _02 = "stack traceback:"
local _03 = "	[C]: in function 'require'"
local _04 = "	C:/Users/bartl/AppData/Local/nvim/lua/custom/pathprobe/init.lua:14: in main chunk"

-- ── lazy.nvim error format ───────────────────────────────────────────────────
local _05 = "  vim/...ocal/nvim-data/lazy/gopath.nvim/lua/gopath/init.lua:42: attempt to index nil"

-- ── Go error ─────────────────────────────────────────────────────────────────
local _06 = "goroutine 1 [running]:\nmain.main()\n\t/home/user/myproject/main.go:42 +0x5e"

-- ── Python traceback ─────────────────────────────────────────────────────────
local _07 = '  File "/home/user/project/app/views.py", line 88, in get'
local _08 = "  File \"C:\\Users\\bartl\\project\\main.py\", line 12, in <module>"

-- ── Rust / cargo ─────────────────────────────────────────────────────────────
local _09 = "  --> src/main.rs:42:10"

-- ── TypeScript / Node ────────────────────────────────────────────────────────
local _10 = "    at Object.<anonymous> (/home/user/project/src/index.ts:24:5)"
local _11 = "    at Module._resolveFilename (node:internal/modules/cjs/loader:1039:15)"

-- ── Lua test runner (busted) ─────────────────────────────────────────────────
local _12 = "FAILED tests/unit/config_spec.lua @ 42"

-- ── Neovim checkhealth ───────────────────────────────────────────────────────
local _13 = "  - ERROR: ...vim/lua/gopath/health.lua:55: bad argument #1"

-- ── Windows Event log style ──────────────────────────────────────────────────
local _14 = "Faulting module path: C:\\Program Files\\Neovim\\bin\\nvim.exe"
