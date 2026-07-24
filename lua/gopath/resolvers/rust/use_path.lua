---@module 'gopath.resolvers.rust.use_path'
---@brief Resolve Rust `use` / `mod` paths under the cursor into source files.
---@description
--- Handles the project-local Rust path forms:
---   • `mod foo;`              → foo.rs or foo/mod.rs (relative to current file)
---   • `use crate::a::b`       → <crate-src>/a/b.rs or <crate-src>/a/b/mod.rs or <crate-src>/a.rs
---   • `use super::a`          → parent module directory
---   • `use self::a`           → current module directory
---
--- The crate source root is the directory of the nearest `lib.rs`/`main.rs`
--- under `src/`, discovered via the enclosing Cargo.toml. External crates
--- (`use serde::…`) are not resolved offline; rust-analyzer covers those.

local H = require("gopath.resolvers.common.lang_helper")
local PATH = require("gopath.util.path")

local M = {}

---Locate the crate's `src` directory via the nearest Cargo.toml.
---@return string|nil src_dir
local function crate_src_dir()
  local root = H.find_root({ "Cargo.toml" })
  if not root then return nil end
  local src = PATH.join(root, "src")
  if PATH.exists(PATH.join(src, "lib.rs")) or PATH.exists(PATH.join(src, "main.rs")) then
    return src
  end
  return src
end

---Turn a `::`-separated module path into candidate files under `base`.
---Drops a trailing item that is likely a type/function (Uppercase or {…}).
---@param base string
---@param segments string[]
---@return string[] candidates
local function segments_to_candidates(base, segments)
  -- Build the directory chain from segments, trying file and mod.rs at each
  -- plausible truncation (the last segment may be an item, not a module).
  local candidates = {}
  local function add_for(count)
    if count < 1 then return end
    local parts = {}
    for i = 1, count do
      parts[i] = segments[i]
    end
    local rel = table.concat(parts, "/")
    candidates[#candidates + 1] = PATH.join(base, rel .. ".rs")
    candidates[#candidates + 1] = PATH.join(base, rel, "mod.rs")
  end
  add_for(#segments)
  add_for(#segments - 1) -- last segment was probably an item (Foo, func, …)
  return candidates
end

---Parse a `use`/`mod` line into (origin, segments).
---@param line string
---@return string|nil origin  "crate"|"super"|"self"|"mod"
---@return string[]|nil segments
local function parse_line(line)
  -- mod foo;
  local m = line:match("^%s*mod%s+([%w_]+)%s*;")
  if m then return "mod", { m } end

  -- use crate::a::b  /  use super::a  /  use self::a
  local origin, rest = line:match("^%s*use%s+([%w_]+)::([%w_:]+)")
  if origin and (origin == "crate" or origin == "super" or origin == "self") then
    local segs = vim.split(rest, "::", { plain = true, trimempty = true })
    if #segs > 0 then return origin, segs end
  end

  return nil, nil
end

---@return GopathResult|nil
function M.resolve()
  local origin, segments = parse_line(H.current_line())
  if not origin or not segments then return nil end

  local abs
  if origin == "mod" then
    local dir = H.current_file_dir()
    abs = H.first_existing({
      PATH.join(dir, segments[1] .. ".rs"),
      PATH.join(dir, segments[1], "mod.rs"),
    })
  elseif origin == "crate" then
    local src = crate_src_dir()
    if src then abs = H.first_existing(segments_to_candidates(src, segments)) end
  elseif origin == "self" then
    abs = H.first_existing(segments_to_candidates(H.current_file_dir(), segments))
  elseif origin == "super" then
    local parent = vim.fn.fnamemodify(H.current_file_dir(), ":h")
    abs = H.first_existing(segments_to_candidates(parent, segments))
  end

  if not abs then return nil end

  return H.make_result({
    language = "rust",
    path = abs,
    exists = true,
    kind = "module",
    confidence = 0.8,
  })
end

return M
