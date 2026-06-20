---@module 'gopath.resolvers.go.import_path'
---@brief Resolve Go import paths under the cursor into package directories.
---@description
--- Handles Go import specifiers, e.g.:
---   • `import "github.com/user/repo/pkg/util"`
---   • grouped imports inside `import ( … )`
---
--- Strategy:
---   1. Read the module path from the nearest `go.mod`.
---   2. If the import is inside the current module, map it to a local directory
---      and open a representative `.go` file there.
---   3. Otherwise look it up under the module cache (`$GOMODCACHE` or
---      `$GOPATH/pkg/mod`) and the vendor directory.
---
--- Go packages are directories; we open the first non-test `.go` file as the
--- entry point (or the directory's `doc.go` when present).

local H    = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

---Read the `module` path declared in `<root>/go.mod`.
---@param root string
---@return string|nil module_path
local function read_module_path(root)
  local gomod = PATH.join(root, "go.mod")
  if not PATH.exists(gomod) then return nil end
  local ok, lines = pcall(vim.fn.readfile, gomod)
  if not ok then return nil end
  for i = 1, #lines do
    local mod = lines[i]:match("^module%s+(%S+)")
    if mod then return mod end
  end
  return nil
end

---Pick a representative .go file inside `dir` (prefer doc.go, skip _test.go).
---@param dir string
---@return string|nil abs
local function representative_go_file(dir)
  if vim.fn.isdirectory(dir) ~= 1 then return nil end
  local doc = PATH.join(dir, "doc.go")
  if PATH.exists(doc) then return vim.fn.fnamemodify(doc, ":p") end

  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok or type(entries) ~= "table" then return nil end
  for i = 1, #entries do
    local name = entries[i]
    if name:match("%.go$") and not name:match("_test%.go$") then
      return vim.fn.fnamemodify(PATH.join(dir, name), ":p")
    end
  end
  return nil
end

---Extract the import path string under or near the cursor.
---@param line string
---@return string|nil import_path
local function parse_import(line)
  -- "github.com/..."  on an import line or inside an import ( ) block
  return line:match('"([^"]+)"')
end

---Resolve `import_path` to a directory, given module info.
---@param import_path string
---@param root string|nil  module root dir
---@param module_path string|nil  declared module path
---@return string|nil dir
local function locate_package_dir(import_path, root, module_path)
  -- 1. Inside the current module
  if root and module_path and import_path:sub(1, #module_path) == module_path then
    local rel = import_path:sub(#module_path + 1):gsub("^/", "")
    local dir = PATH.join(root, rel)
    if vim.fn.isdirectory(dir) == 1 then return dir end
  end

  -- 2. Vendor directory
  if root then
    local vendored = PATH.join(root, "vendor", import_path)
    if vim.fn.isdirectory(vendored) == 1 then return vendored end
  end

  -- 3. Module cache ($GOMODCACHE or $GOPATH/pkg/mod)
  local modcache = vim.env.GOMODCACHE
  if not modcache or modcache == "" then
    local gopath = vim.env.GOPATH
    if gopath and gopath ~= "" then
      modcache = PATH.join(gopath, "pkg", "mod")
    end
  end
  if modcache and modcache ~= "" then
    local dir = PATH.join(modcache, import_path)
    if vim.fn.isdirectory(dir) == 1 then return dir end
  end

  return nil
end

---@return GopathResult|nil
function M.resolve()
  local import_path = parse_import(H.current_line())
  if not import_path or not import_path:match("/") then
    return nil
  end

  local root        = H.find_root({ "go.mod" })
  local module_path = root and read_module_path(root) or nil

  local dir = locate_package_dir(import_path, root, module_path)
  if not dir then return nil end

  local abs = representative_go_file(dir)
  if not abs then return nil end

  return H.make_result({
    language   = "go",
    path       = abs,
    exists     = true,
    kind       = "module",
    confidence = 0.8,
  })
end

return M
