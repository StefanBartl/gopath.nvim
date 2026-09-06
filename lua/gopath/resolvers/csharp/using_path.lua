---@module 'gopath.resolvers.csharp.using_path'
---@brief Resolve C# `using` namespaces under the cursor into source files.
---@description
--- C# does not map namespaces to file paths the way Python/Java do, so this
--- resolver is necessarily heuristic. Handles:
---   • `using My.App.Utils;`            → search the project for a file whose path
---                                        mirrors the namespace, or a file named
---                                        after the last segment.
---   • `using static My.App.Helpers;`   → same, ignoring the `static` keyword.
---
--- The project root is the nearest `*.csproj`/`*.sln`/`.git`. Resolution prefers
--- a path that mirrors the dotted namespace (My/App/Utils.cs); failing that it
--- falls back to any file named after the final namespace segment. OmniSharp
--- provides exact navigation when an LSP is attached.

local H = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

local CS_LITERAL_MARKERS = { "Directory.Build.props", ".git" }

---Find the nearest ancestor directory containing a `*.csproj`/`*.sln` file, or
---(failing that) one of the literal marker files.
---
---`vim.fs.find` does not support globs when `names` is a string/table (Neovim
---docs: "paths and globs are not supported when {names} is a string or a
---table") — `H.find_root`'s exact-name matching can't express "any *.csproj",
---so extension matching needs the function form of `names` instead.
---@internal
---@return string|nil
local function find_cs_root()
  local start = H.current_file_dir()
  local ok, found = pcall(vim.fs.find, function(name)
    return name:match("%.csproj$") ~= nil or name:match("%.sln$") ~= nil
  end, { upward = true, path = start, limit = 1 })
  if ok and type(found) == "table" and found[1] then return vim.fs.dirname(found[1]) end
  return H.find_root(CS_LITERAL_MARKERS)
end

---Parse a `using` line into a dotted namespace.
---@internal
---@param line string
---@return string|nil dotted
local function parse_using(line)
  -- using static My.App.Helpers;  → captures "My.App.Helpers"
  local ns = line:match("^%s*using%s+static%s+([%w_%.]+)%s*;")
  if ns then return ns end
  -- using My.App.Utils;  (skip alias form `using X = Y;`)
  ns = line:match("^%s*using%s+([%w_%.]+)%s*;")
  if ns and not line:match("=") then return ns end
  return nil
end

---@return GopathResult|nil
function M.resolve()
  local dotted = parse_using(H.current_line())
  if not dotted or not dotted:match("%.") then return nil end

  local root = find_cs_root() or H.current_file_dir()
  local rel = dotted:gsub("%.", "/")

  -- 1. Mirror the namespace as a directory path: My/App/Utils.cs
  local abs = H.first_existing({ PATH.join(root, rel .. ".cs") })

  -- 2. Fall back to any *.cs named after the final segment.
  if not abs then
    local last = dotted:match("([%w_]+)$")
    if last then
      local ok, found = pcall(vim.fs.find, last .. ".cs", {
        type = "file",
        limit = 1,
        path = root,
      })
      if ok and type(found) == "table" and found[1] then
        abs = vim.fn.fnamemodify(found[1], ":p")
      end
    end
  end

  if not abs then return nil end

  return H.make_result({
    language = "cs",
    path = abs,
    exists = true,
    kind = "module",
    confidence = 0.7, -- heuristic mapping → slightly lower confidence
  })
end

return M
