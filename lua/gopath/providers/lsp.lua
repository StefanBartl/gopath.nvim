---@module 'gopath.providers.lsp'
---@brief LSP provider with proper range normalization.

local LOC = require("gopath.util.location")

local M = {}

---Short, sync definition request with normalized ranges
---@param timeout_ms integer Timeout in milliseconds
---@return table[]|nil results List of { path: string, range: { line: integer, col: integer } }
function M.definition_at_cursor(timeout_ms)
  local params = vim.lsp.util.make_position_params(0, 'utf-8')
  local res = vim.lsp.buf_request_sync(0, "textDocument/definition", params, timeout_ms)

  if not res then
    return nil
  end

  local out = {}
  for _, r in pairs(res) do
    local result = r.result
    if type(result) == "table" then
      local list = result.uri and { result } or result

      for _, loc in ipairs(list) do
        local uri = loc.uri or loc.targetUri
        local rng = loc.range or loc.targetRange

        if uri and rng then
          local p = vim.uri_to_fname(uri)

          -- LSP ranges are 0-indexed, convert to 1-indexed
          local normalized = LOC.normalize_range({
            line = rng.start.line + 1,
            col = rng.start.character + 1,
          })

          out[#out + 1] = {
            path = p,
            range = normalized,
          }
        end
      end
    end
  end

  return (#out > 0) and out or nil
end

return M
