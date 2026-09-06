---@module 'gopath.providers.lsp'
---@brief LSP provider with proper range normalization.

local LOC = require("gopath.util.location")

local M = {}

---Whether any language server is attached to the current buffer.
---
---Asked before the request, because `buf_request_sync` does not return early
---when nothing is attached -- it blocks for the whole timeout instead. See
---docs/resolution.md#the-lsp-step-does-not-wait-for-a-server-that-is-not-there
---for the measurements and why this deliberately does not check
---`textDocument/definition` support.
---
---`get_active_clients` is the pre-0.10 name and deprecated since. Same
---two-step as `gopath.health`, for the same reason: this plugin supports 0.9.
---@return boolean
local function has_client()
  ---@diagnostic disable-next-line: deprecated
  local get = vim.lsp.get_clients or vim.lsp.get_active_clients
  if not get then return false end
  local ok, clients = pcall(get, { bufnr = 0 })
  return ok and type(clients) == "table" and #clients > 0
end

---Short, sync definition request with normalized ranges
---@param timeout_ms integer Timeout in milliseconds
---@return table[]|nil results List of { path: string, range: { line: integer, col: integer } }
function M.definition_at_cursor(timeout_ms)
  if not has_client() then return nil end

  local params = vim.lsp.util.make_position_params(0, "utf-8")
  local res = vim.lsp.buf_request_sync(0, "textDocument/definition", params, timeout_ms)

  if not res then return nil end

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
