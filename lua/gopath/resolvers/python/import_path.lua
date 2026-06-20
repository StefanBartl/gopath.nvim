---@module 'gopath.resolvers.python.import_path'
---@brief Resolve Python import statements under the cursor into module files.
---@description
--- Handles the common Python import forms:
---   • `import foo.bar`                → foo/bar.py or foo/bar/__init__.py
---   • `import foo.bar as b`           → foo/bar.py
---   • `from foo.bar import baz`       → foo/bar.py  (or foo/bar/baz.py if baz is a submodule)
---   • `from . import x` / `from .foo` → relative to the current package
---   • `from ..pkg import y`           → parent-package relative
---
--- Resolution is rooted at the project root (nearest pyproject.toml / setup.py /
--- setup.cfg / .git) and additionally tried relative to the current file's
--- directory. Standard-library and site-packages modules are intentionally not
--- resolved offline; an LSP handles those when available.

local H    = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

local PY_ROOT_MARKERS = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" }

---Convert a dotted module name to candidate file paths under `root`.
---@param root string  Absolute search root
---@param dotted string  e.g. "foo.bar.baz"
---@return string[] candidates
local function dotted_to_candidates(root, dotted)
  local rel = dotted:gsub("%.", "/")
  return {
    PATH.join(root, rel .. ".py"),
    PATH.join(root, rel, "__init__.py"),
  }
end

---Resolve a relative import like `.foo`, `..bar.baz` against the current package.
---@param dots string  Leading dots ("." or ".." …)
---@param tail string|nil  Dotted module after the dots (may be nil/empty)
---@return string|nil abs
local function resolve_relative(dots, tail)
  -- One dot = current package dir; each extra dot climbs one level.
  local dir = H.current_file_dir()
  for _ = 2, #dots do
    dir = vim.fn.fnamemodify(dir, ":h")
  end

  if tail and tail ~= "" then
    return H.first_existing(dotted_to_candidates(dir, tail))
  end
  -- `from . import x` → the package __init__ itself
  return H.first_existing({ PATH.join(dir, "__init__.py") })
end

---Parse the current line for a Python import.
---@param line string
---@return string|nil dotted    Dotted module name (e.g. "foo.bar")
---@return string|nil rel_dots  Leading dots for relative imports, else nil
---@return string|nil imported  First imported name in a `from … import X` form
local function parse_import(line)
  -- Relative: from .foo import x  /  from .. import y
  local dots, tail = line:match("^%s*from%s+(%.+)([%w_%.]*)%s+import")
  if dots then
    local imported = line:match("import%s+([%w_]+)")
    return tail, dots, imported
  end

  -- from foo.bar import baz
  local mod = line:match("^%s*from%s+([%w_%.]+)%s+import")
  if mod then
    local imported = line:match("import%s+([%w_]+)")
    return mod, nil, imported
  end

  -- import foo.bar  /  import foo.bar as b
  mod = line:match("^%s*import%s+([%w_%.]+)")
  if mod then
    return mod, nil, nil
  end

  return nil, nil, nil
end

---Resolve `dotted` (and an optional imported submodule name) under `root`.
---@param root string
---@param dotted string
---@param imported string|nil
---@return string|nil abs
local function resolve_under(root, dotted, imported)
  -- 1. The module itself: foo/bar.py or foo/bar/__init__.py
  local abs = H.first_existing(dotted_to_candidates(root, dotted))
  if abs then return abs end

  -- 2. `from foo.bar import baz` where baz is a submodule: foo/bar/baz.py
  if imported then
    abs = H.first_existing(dotted_to_candidates(root, dotted .. "." .. imported))
    if abs then return abs end
  end

  return nil
end

---@return GopathResult|nil
function M.resolve()
  local line = H.current_line()
  local dotted, rel_dots, imported = parse_import(line)
  if not dotted and not rel_dots then
    return nil
  end

  local abs
  if rel_dots then
    abs = resolve_relative(rel_dots, dotted)
  else
    -- Try project root first, then current-file dir as a fallback.
    local root = H.find_root(PY_ROOT_MARKERS) or H.current_file_dir()
    abs = resolve_under(root, dotted, imported)
    if not abs then
      abs = resolve_under(H.current_file_dir(), dotted, imported)
    end
  end

  if not abs then
    return nil
  end

  return H.make_result({
    language   = "python",
    path       = abs,
    exists     = true,
    kind       = "module",
    confidence = 0.8,
  })
end

return M
