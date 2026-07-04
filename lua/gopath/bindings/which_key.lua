---@module 'gopath.bindings.which_key'
---@brief Optional, guarded which-key label for the probe keymap.
---@description
--- which-key is a **soft** dependency: if it is not installed this is a
--- no-op. gopath's mappings are single g-prefixed keys (not a shared leader
--- namespace) except `probe`, which lives under the user's `<leader>`
--- prefix — so the only thing worth registering is a label for that one
--- key. Supports both the which-key v3 (`add`) and v2 (`register`) APIs.

local M = {}

---Register a label for the configured probe keymap, if which-key and the
---mapping are both available.
---@param config GopathOptions
---@return boolean registered
function M.setup(config)
  local ok, wk = pcall(require, "which-key")
  if not ok or type(wk) ~= "table" then
    return false
  end

  local probe = config.mappings and config.mappings.probe
  if not probe or probe == false then
    return false
  end

  local keys = type(probe) == "table" and probe or { probe }
  local desc = "gopath: probe path under cursor/selection"

  if type(wk.add) == "function" then
    -- which-key v3
    local specs = {}
    for _, key in ipairs(keys) do
      specs[#specs + 1] = { key, desc = desc, mode = { "n", "v" } }
    end
    wk.add(specs)
    return true
  elseif type(wk.register) == "function" then
    -- which-key v2
    local mapping = {}
    for _, key in ipairs(keys) do
      mapping[key] = desc
    end
    wk.register(mapping, { mode = "n" })
    wk.register(mapping, { mode = "v" })
    return true
  end

  return false
end

---Whether which-key is installed (for :checkhealth reporting).
---@return boolean
function M.available()
  local ok, wk = pcall(require, "which-key")
  return ok and type(wk) == "table"
end

return M
