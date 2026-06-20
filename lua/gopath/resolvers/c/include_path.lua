---@module 'gopath.resolvers.c.include_path'
---@brief Resolve C/C++ #include directives under the cursor into header files.
---@description
--- Shared by the `c` and `cpp` filetypes. Handles:
---   • `#include "foo/bar.h"`  → quoted form: current dir first, then project include dirs
---   • `#include <foo/bar.h>`  → angled form: project include dirs, then common system dirs
---
--- Quoted includes are searched relative to the current file's directory first
--- (matching the C preprocessor's behaviour), then against typical project
--- include roots discovered via the build-system marker (CMakeLists.txt,
--- Makefile, compile_commands.json, .git). System headers (`<stdio.h>`) are
--- looked up in a small set of conventional locations as best-effort.

local H    = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

local C_ROOT_MARKERS = { "compile_commands.json", "CMakeLists.txt", "Makefile", ".clangd", ".git" }
-- Common project-relative include roots, tried under the project root.
local INCLUDE_SUBDIRS = { ".", "include", "src", "inc", "headers" }
-- Conventional system include directories (best-effort, Unix-ish).
local SYSTEM_DIRS = { "/usr/include", "/usr/local/include" }

---Parse an #include directive into (header, is_angled).
---@param line string
---@return string|nil header, boolean is_angled
local function parse_include(line)
  local h = line:match('#%s*include%s*"([^"]+)"')
  if h then return h, false end
  h = line:match("#%s*include%s*<([^>]+)>")
  if h then return h, true end
  return nil, false
end

---@return GopathResult|nil
function M.resolve()
  local header, is_angled = parse_include(H.current_line())
  if not header then return nil end

  local candidates = {}

  -- Quoted form: current file's directory has highest priority.
  if not is_angled then
    candidates[#candidates + 1] = PATH.join(H.current_file_dir(), header)
  end

  -- Project include roots.
  local root = H.find_root(C_ROOT_MARKERS)
  if root then
    for i = 1, #INCLUDE_SUBDIRS do
      candidates[#candidates + 1] = PATH.join(root, INCLUDE_SUBDIRS[i], header)
    end
  end

  -- System directories (mainly for the angled form).
  for i = 1, #SYSTEM_DIRS do
    candidates[#candidates + 1] = PATH.join(SYSTEM_DIRS[i], header)
  end

  local abs = H.first_existing(candidates)
  if not abs then return nil end

  return H.make_result({
    language   = vim.bo.filetype or "c",
    path       = abs,
    exists     = true,
    kind       = "module",
    confidence = 0.8,
  })
end

return M
