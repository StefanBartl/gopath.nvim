---@module 'gopath.resolvers.javascript.import_path'
---@brief Resolve JS/TS import/require specifiers under the cursor.
---@description
--- Shared by the `javascript`, `javascriptreact`, `typescript` and
--- `typescriptreact` filetypes. Handles:
---   • `import x from './foo'`         → ./foo.{ts,tsx,js,jsx,…} or ./foo/index.*
---   • `import { a } from '../bar'`    → relative resolution
---   • `export * from './baz'`         → relative resolution
---   • `require('./foo')`              → relative resolution
---   • `import x from 'pkg'`           → node_modules/pkg  (best-effort: main/index)
---
--- Relative specifiers are resolved against the current file's directory.
--- Bare specifiers are resolved against the nearest node_modules. Full
--- package.json "exports"/"main" resolution is intentionally shallow — an LSP
--- handles the precise cases when present.

local H = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

-- Extension probe order: TS first (covers TS projects), then JS, then JSON.
local EXTS = { ".ts", ".tsx", ".d.ts", ".js", ".jsx", ".mjs", ".cjs", ".json" }
local INDEX_NAMES = { "index" }

---Extract the import specifier string from the current line.
---@param line string
---@return string|nil specifier
local function parse_specifier(line)
  -- import ... from '<spec>'   /   export ... from "<spec>"
  local spec = line:match("from%s+['\"]([^'\"]+)['\"]")
  if spec then return spec end

  -- import '<spec>'  (side-effect import)
  spec = line:match("^%s*import%s+['\"]([^'\"]+)['\"]")
  if spec then return spec end

  -- require('<spec>')  /  import('<spec>')  (dynamic)
  spec = line:match("require%s*%(%s*['\"]([^'\"]+)['\"]")
    or line:match("import%s*%(%s*['\"]([^'\"]+)['\"]")
  if spec then return spec end

  return nil
end

---Resolve a relative specifier (./… or ../…) against `base_dir`.
---@param base_dir string
---@param spec string
---@return string|nil abs
local function resolve_relative(base_dir, spec)
  local joined = PATH.join(base_dir, spec)

  -- Exact path (specifier already carries an extension)
  local exact = H.first_existing({ joined })
  if exact then return exact end

  -- <spec><ext> and <spec>/index<ext>
  return H.resolve_with_extensions(joined, EXTS, INDEX_NAMES)
end

---Resolve a bare specifier ('lodash', '@scope/pkg') via the nearest node_modules.
---@param spec string
---@return string|nil abs
local function resolve_bare(spec)
  local nm_dir = H.find_root({ "node_modules" })
  if not nm_dir then return nil end
  local pkg_base = PATH.join(nm_dir, "node_modules", spec)

  -- Try package entry points: index.* and the directory's own files.
  local hit = H.resolve_with_extensions(pkg_base, EXTS, INDEX_NAMES)
  if hit then return hit end

  -- Best-effort: read "main"/"module"/"types" from package.json.
  local pkg_json = PATH.join(pkg_base, "package.json")
  if PATH.exists(pkg_json) then
    local ok, content = pcall(function()
      return table.concat(vim.fn.readfile(pkg_json), "\n")
    end)
    if ok then
      local ok2, data = pcall(vim.json.decode, content)
      if ok2 and type(data) == "table" then
        local entry = data.types or data.module or data.main
        if type(entry) == "string" then
          local entry_abs = H.first_existing({ PATH.join(pkg_base, entry) })
          if entry_abs then return entry_abs end
        end
      end
    end
    return vim.fn.fnamemodify(pkg_json, ":p")
  end

  return nil
end

---@return GopathResult|nil
function M.resolve()
  local spec = parse_specifier(H.current_line())
  if not spec then return nil end

  local abs
  if spec:match("^%.%.?/") or spec == "." or spec == ".." then
    abs = resolve_relative(H.current_file_dir(), spec)
  else
    abs = resolve_bare(spec)
  end

  if not abs then return nil end

  return H.make_result({
    language = vim.bo.filetype or "javascript",
    path = abs,
    exists = true,
    kind = "module",
    confidence = 0.8,
  })
end

return M
