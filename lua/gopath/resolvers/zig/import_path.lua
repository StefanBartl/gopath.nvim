---@module 'gopath.resolvers.zig.import_path'
---@brief Resolve Zig `@import("…")` specifiers under the cursor.
---@description
--- Zig imports are either a relative source file or a well-known builtin:
---   • `@import("../utils.zig")`  → relative to the current file's directory
---   • `@import("foo/bar.zig")`   → relative path
---   • `@import("std")`           → builtin module (not resolvable offline; skipped)
---   • `@import("root")` / "builtin" → builtin (skipped)
---
--- Relative `.zig` files are the common, resolvable case and are handled here.
--- Package imports declared in `build.zig` are left to zls when available.

local H    = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

-- Builtin import names that do not correspond to a project file.
local BUILTINS = { std = true, builtin = true, root = true, ["c"] = true }

---Extract the @import("…") argument from the current line.
---@param line string
---@return string|nil spec
local function parse_import(line)
  return line:match('@import%s*%(%s*"([^"]+)"%s*%)')
end

---@return GopathResult|nil
function M.resolve()
  local spec = parse_import(H.current_line())
  if not spec then return nil end

  -- Skip builtin modules — let zls resolve those.
  if BUILTINS[spec] then return nil end

  -- Resolve as a relative file path (with or without trailing .zig).
  local base = PATH.join(H.current_file_dir(), spec)
  local abs  = H.first_existing({ base })
  if not abs and not spec:match("%.zig$") then
    abs = H.first_existing({ base .. ".zig" })
  end

  if not abs then return nil end

  return H.make_result({
    language   = "zig",
    path       = abs,
    exists     = true,
    kind       = "module",
    confidence = 0.8,
  })
end

return M
