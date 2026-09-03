---@module 'gopath.providers.lsp'
---@brief LSP provider with proper range normalization.

local LOC = require("gopath.util.location")

local M = {}

---Whether any language server is attached to the current buffer.
---
---**Asked before the request, because `buf_request_sync` does not ask it.**
---With nobody to send to it does not return early -- measured 2026-09-03 on a
---buffer with zero clients, it blocked for the whole timeout and then
---answered `nil, "timeout"`: 219 ms for the 200 ms default.
---
---That fell on every resolve reaching the language pipeline in a buffer with
---no server: a `.txt`, a `gitcommit`, a scratch buffer, any filetype without
---one, and every machine running no LSP at all. Measured through
---`resolve_at_cursor` over prose, the whole call was 216 ms of which this was
---200 -- against 1.6 ms for an existing relative path, which never reaches
---this far.
---
---`get_active_clients` is the pre-0.10 name and deprecated since. Same
---two-step as `gopath.health`, for the same reason: this plugin supports 0.9.
---
---**What this deliberately does not answer** is whether an attached client
---supports `textDocument/definition`. The capability call changed shape
---across 0.9, 0.10 and 0.11 (`client.supports_method` by dot, then by colon,
---with an options table), and getting that wrong would silently reintroduce
---exactly the wait it removes. "Nobody is attached" is version-proof and is
---the case that was measured.
---@return boolean
local function has_client()
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
