---@module 'gopath.resolvers.common.lang_helper'
---@brief Shared utilities for language-specific import/use/include resolvers.
---@description
--- Every language resolver (python, javascript, rust, go, c, csharp, zig, java)
--- follows the same shape: read the current line, parse the import construct,
--- turn it into one or more candidate file paths and return the first that
--- exists on disk. This module factors out the parts that are identical across
--- languages: cursor/line access, project-root discovery, candidate probing and
--- GopathResult construction. The language-specific *parsing* stays in each
--- resolver so the differences remain explicit and readable.

local PATH = require("gopath.util.path")
local LOC = require("gopath.util.location")

local M = {}

---Absolute directory of the file in the current buffer.
---@return string
function M.current_file_dir()
  return vim.fn.expand("%:p:h")
end

---Full text of the current cursor line.
---@return string
function M.current_line()
  return vim.api.nvim_get_current_line()
end

---1-based cursor column on the current line.
---@return integer
function M.cursor_col()
  return vim.api.nvim_win_get_cursor(0)[2] + 1
end

---Find the nearest ancestor directory containing any of `markers`.
---Searches upward from the current file's directory.
---@param markers string[]  e.g. { "go.mod", ".git" }
---@return string|nil root  Absolute path of the directory containing a marker
function M.find_root(markers)
  if type(markers) ~= "table" or #markers == 0 then return nil end
  local start = M.current_file_dir()
  local ok, found = pcall(vim.fs.find, markers, { upward = true, path = start, limit = 1 })
  if ok and type(found) == "table" and found[1] then return vim.fs.dirname(found[1]) end
  return nil
end

---Return the first candidate path that exists as a regular file (absolute).
--- Each candidate is normalized first (`vim.fs.normalize`) so that embedded
--- "./" and "../" segments resolve correctly and separators are unified —
--- without this, `fs_stat` fails on paths like ".../app/./util.ts" on Windows.
---@param candidates string[]  Candidate paths (absolute or already joined)
---@return string|nil abs
function M.first_existing(candidates)
  for i = 1, #candidates do
    local p = candidates[i]
    if p and p ~= "" then
      local norm = vim.fs.normalize(p)
      if PATH.exists(norm) then return vim.fn.fnamemodify(norm, ":p") end
    end
  end
  return nil
end

---Expand a base path (without extension) into <base><ext> and <base>/index<ext>
---style candidates for each extension, then return the first existing one.
---@param base string         Absolute path without extension (e.g. ".../foo")
---@param exts string[]       Extensions WITH leading dot (e.g. { ".ts", ".tsx" })
---@param index_names string[]|nil  Index basenames to try inside a directory (e.g. { "index" })
---@return string|nil abs
function M.resolve_with_extensions(base, exts, index_names)
  local candidates = {}
  -- <base><ext>
  for i = 1, #exts do
    candidates[#candidates + 1] = base .. exts[i]
  end
  -- <base>/<index><ext>
  if index_names then
    for j = 1, #index_names do
      for i = 1, #exts do
        candidates[#candidates + 1] = PATH.join(base, index_names[j] .. exts[i])
      end
    end
  end
  return M.first_existing(candidates)
end

---Build a GopathResult for a resolved language module/file.
---@param opts { language:string, path:string|nil, exists:boolean, kind:string|nil, line:integer|nil, col:integer|nil, confidence:number|nil, source:string|nil }
---@return GopathResult
function M.make_result(opts)
  return {
    language = opts.language,
    kind = opts.kind or (opts.exists and "module" or "file"),
    path = opts.path,
    range = LOC.create_range(opts.line, opts.col),
    chain = nil,
    source = opts.source or "builtin",
    confidence = opts.confidence or (opts.exists and 0.8 or 0.3),
    exists = opts.exists,
  }
end

return M
