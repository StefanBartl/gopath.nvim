---@module 'gopath.util.filetree'
---@brief Soft dependency on filetree.nvim: resolve its active adapter when
---the plugin is installed and has completed `setup()`, else nil. Shared by
---`gopath.create` (the "Open in filetree" button on the create-missing
---dialog) and `gopath.open` (the `"filetree"` open mode) — one seam instead
---of two copies of the same `pcall(require, "filetree")` dance.

local M = {}

---@return table|nil adapter
function M.adapter()
  local ok, filetree = pcall(require, "filetree")
  if not ok or type(filetree) ~= "table" or not filetree.is_initialized() then return nil end
  local ok_adapter, adapter = pcall(filetree.adapter)
  if not ok_adapter or type(adapter) ~= "table" then return nil end
  return adapter
end

return M
