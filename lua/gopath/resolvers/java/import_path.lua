---@module 'gopath.resolvers.java.import_path'
---@brief Resolve Java `import` statements under the cursor into source files.
---@description
--- Java maps packages directly to directory structure, which makes resolution
--- reliable for project-local classes. Handles:
---   • `import com.example.utils.Helper;`        → .../com/example/utils/Helper.java
---   • `import static com.example.Foo.bar;`      → .../com/example/Foo.java
---   • `import com.example.utils.*;`             → the package directory's first class
---
--- Source roots follow Maven/Gradle conventions (src/main/java, src/test/java)
--- discovered via the nearest build file (pom.xml / build.gradle / .git).
--- JDK and dependency classes are not resolved offline; jdtls covers those.

local H = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

local JAVA_ROOT_MARKERS =
  { "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", ".git" }
-- Conventional source roots, relative to the project root.
local SOURCE_ROOTS = {
  "src/main/java",
  "src/test/java",
  "src/main/kotlin",
  "src",
  ".",
}

---Parse an `import` line into a dotted type/package and a wildcard flag.
---@param line string
---@return string|nil dotted, boolean is_wildcard
local function parse_import(line)
  -- import static com.example.Foo.bar;
  local s = line:match("^%s*import%s+static%s+([%w_%.]+)%s*;")
  if s then
    -- Drop the trailing member: com.example.Foo.bar → com.example.Foo
    return s:gsub("%.[%w_]+$", ""), false
  end

  -- import com.example.utils.*;
  local w = line:match("^%s*import%s+([%w_%.]+)%.%*%s*;")
  if w then return w, true end

  -- import com.example.utils.Helper;
  local d = line:match("^%s*import%s+([%w_%.]+)%s*;")
  if d then return d, false end

  return nil, false
end

---First .java file inside a package directory (for wildcard imports).
---@param dir string
---@return string|nil abs
local function first_java_in(dir)
  if vim.fn.isdirectory(dir) ~= 1 then return nil end
  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok or type(entries) ~= "table" then return nil end
  for i = 1, #entries do
    if entries[i]:match("%.java$") then
      return vim.fn.fnamemodify(PATH.join(dir, entries[i]), ":p")
    end
  end
  return nil
end

---@return GopathResult|nil
function M.resolve()
  local dotted, is_wildcard = parse_import(H.current_line())
  if not dotted or not dotted:match("%.") then return nil end

  local root = H.find_root(JAVA_ROOT_MARKERS) or H.current_file_dir()
  local rel = dotted:gsub("%.", "/")

  local abs
  for i = 1, #SOURCE_ROOTS do
    local src = PATH.join(root, SOURCE_ROOTS[i])
    if is_wildcard then
      abs = first_java_in(PATH.join(src, rel))
    else
      abs = H.first_existing({ PATH.join(src, rel .. ".java") })
    end
    if abs then break end
  end

  if not abs then return nil end

  return H.make_result({
    language = "java",
    path = abs,
    exists = true,
    kind = "module",
    confidence = 0.85, -- package→path mapping is reliable in Java
  })
end

return M
