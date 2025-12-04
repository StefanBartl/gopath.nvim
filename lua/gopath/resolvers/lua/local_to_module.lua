---@module 'gopath.resolvers.lua.local_to_module'
---@brief When LSP points to a local variable that's a require(), resolve to the module instead.

local PATH = require("gopath.util.path")

local M = {}

---Check if LSP result points to a local require() and resolve to module
---@param lsp_result table LSP result with path and range
---@return table|nil module_result Module result or nil
function M.enhance_lsp_result(lsp_result)
  if not lsp_result or not lsp_result.path or not lsp_result.range then
    return nil
  end

  -- Read the file at LSP result location
  local lines = vim.fn.readfile(lsp_result.path)
  if not lines or #lines == 0 then
    return nil
  end

  local line_num = lsp_result.range.line
  if line_num < 1 or line_num > #lines then
    return nil
  end

  local line = lines[line_num]

  -- Check if this line is a local require()
  -- Pattern: local identifier = require("module.name")
  local module = line:match('local%s+%w+%s*=%s*require%s*[%(%s]*["\']([%w%._/%-]+)["\']')
             or line:match('local%s+%w+%s*=%s*require%s*[%(%s]*%[%[([%w%._/%-]+)%]%]')

  if not module then
    return nil  -- Not a require line, return original result
  end

  -- Resolve module to file path
  local rel = module:gsub("%.", "/")
  local abs = PATH.search_in_rtp({ rel .. ".lua", rel .. "/init.lua" })
           or PATH.search_with_package_path(module)

  if not abs then
    return nil  -- Module not found, return original result
  end

  -- Return enhanced result pointing to module
  return {
    language = "lua",
    kind = "module",
    path = abs,
    range = nil,  -- No specific line in module
    chain = nil,
    source = "lsp-enhanced",
    confidence = 0.95,
    exists = true,
  }
end

return M
