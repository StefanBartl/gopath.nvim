---@module 'gopath.resolvers.lua.identifier_locator'
---@brief Resolve bare identifiers to their module sources.
---Handles cases like: local config = require("gopath.config")
---Cursor on 'config' → resolve to gopath/config.lua

local PATH = require("gopath.util.path")
local TS = require("gopath.providers.treesitter")

local M = {}

---Check if cursor is on a bare identifier (not part of a chain)
---@return string|nil identifier Identifier text or nil
local function get_bare_identifier()
  local node = TS.node_at_cursor()
---@cast node TSNode
  if not node then
    return nil
  end

  -- Only match standalone identifiers
  if node:type() ~= "identifier" then
    return nil
  end

  -- Check if parent is a chain (field_expression, dot_index, etc.)
  local parent = node:parent()
  if parent then
    local ptype = parent:type()
    -- Skip if part of a chain
    if ptype == "field_expression"
      or ptype == "dot_index_expression"
      or ptype == "method_index_expression" then
      return nil
    end
  end

  -- Extract identifier text
  local ok, text = pcall(vim.treesitter.get_node_text, node, 0)
  if not ok or not text or text == "" then
    return nil
  end

  return text
end

---Resolve bare identifier to module path
---@return table|nil GopathResult
function M.resolve()
  local identifier = get_bare_identifier()
  if not identifier then
    return nil
  end

  -- Get binding map (identifier → module)
  local bind_index = require("gopath.resolvers.lua.binding_index")
  local bind = bind_index.get_map()

  local mod = bind[identifier]
  if not mod then
    return nil
  end

  -- Resolve module to file path
  local rel = mod:gsub("%.", "/")
  local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" })
           or PATH.search_with_package_path(mod)

  if not abs then
    return nil
  end

  return {
    language   = "lua",
    kind       = "module",
    path       = abs,
    range      = nil,  -- No specific location, just open the module
    chain      = nil,
    source     = "treesitter",
    confidence = 0.85,
  }
end

return M
