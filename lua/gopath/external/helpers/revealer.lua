---@module 'gopath.external.helpers.revealer'
--- Reveal a path in the system file manager (Explorer/Finder/Nautilus/…),
--- as opposed to `external/helpers/opener.lua`, which hands the path to
--- whatever application is registered for its extension.
---@description
--- Backed by lib.nvim's `cross.reveal_in_fm` (declared dependency, same
--- soft-fallback convention as `gopath.util.cross` / `external/helpers/
--- opener.lua`). Falls back to a minimal built-in per-OS reveal when
--- lib.nvim is missing.

local LOG = require("gopath.util.log")

local M = {}

---@type (fun(target: string, opts?: table):boolean, string|nil)|nil
local reveal_in_fm
do
  local ok, mod = pcall(require, "lib.nvim.cross.reveal_in_fm")
  if ok and type(mod) == "function" then
    reveal_in_fm = mod
  else
    reveal_in_fm = nil
    vim.schedule(function()
      LOG.warn(
        "optional dependency 'lib.nvim' not found — using a minimal "
          .. "built-in file-manager reveal fallback."
      )
    end)
  end
end

---Detect operating system.
---@internal
---@return "macos"|"linux"|"windows"|"unknown"
local function detect_os()
  if vim.fn.has("mac") == 1 or vim.fn.has("macunix") == 1 then
    return "macos"
  elseif vim.fn.has("unix") == 1 then
    return "linux"
  elseif vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1 then
    return "windows"
  end
  return "unknown"
end

---Minimal per-OS reveal, used only when lib.nvim is absent. Unlike
---lib.nvim's reveal_in_fm this never highlights the file inside its parent
---directory — that trick needs platform-specific handling this fallback
---deliberately doesn't carry.
---@internal
---@param path string
---@return boolean success
local function minimal_fallback_reveal(path)
  local os_type = detect_os()
  local cmd
  if os_type == "macos" then
    cmd = { "open", "-R", path }
  elseif os_type == "linux" then
    cmd = { "xdg-open", vim.fn.fnamemodify(path, ":h") }
  elseif os_type == "windows" then
    -- `/select,` and the path form a single argument; a space after the
    -- comma makes explorer.exe drop the path and open Documents instead.
    cmd = { "explorer.exe", "/select," .. path:gsub("/", "\\") }
  else
    LOG.error("Unsupported operating system for file-manager reveal")
    return false
  end

  local job_id = vim.fn.jobstart(cmd, { detach = true })
  if job_id > 0 then
    LOG.info(string.format("Revealing in file manager: %s", vim.fn.fnamemodify(path, ":t")))
    return true
  end
  LOG.error("Failed to start file manager")
  return false
end

---Reveal `path` in the system file manager: a file is selected inside its
---parent directory, a directory is navigated into.
---@param path string File or directory path
---@return boolean success True if the reveal command was invoked successfully
function M.reveal(path)
  if not path or path == "" then return false end

  if reveal_in_fm then
    local ok, err = reveal_in_fm(path)
    if ok then
      LOG.info(string.format("Revealing in file manager: %s", vim.fn.fnamemodify(path, ":t")))
      return true
    end
    LOG.warn("lib.nvim reveal_in_fm failed: " .. tostring(err) .. " — trying minimal fallback")
  end

  return minimal_fallback_reveal(path)
end

return M
