---@module 'gopath.external.helpers.opener'
--- Cross-platform system opener for external files.
---@description
--- open.nvim is a soft dependency: when installed, external files are handed
--- to its "default" handler (system default app, incl. WSL win-path
--- translation, shared with `:Open`). Falls back to lib.nvim's
--- fs.open.url.system_opener (declared dependency, same soft-fallback
--- convention as `gopath.util.cross` / `gopath.util.log`) when open.nvim is
--- not present, or to a minimal built-in opener if lib.nvim is missing too.

local LOG = require("gopath.util.log")

local M = {}

---@type table|nil  the open_nvim module, or nil when unavailable
local open_nvim
do
  local ok, mod = pcall(require, "open_nvim")
  if ok and type(mod) == "table" and type(mod.open) == "function" then
    open_nvim = mod
  else
    open_nvim = nil
    vim.schedule(function()
      LOG.debug(
        "optional dependency 'open_nvim' not found — using built-in "
          .. "system opener fallback. Add it to your plugin spec "
          .. "(dependencies = { 'StefanBartl/open.nvim' }) for WSL support and shared handlers."
      )
    end)
  end
end

---@type table|nil  lib.nvim.fs.open.url.system_opener, or nil when unavailable
local system_opener
do
  local ok, mod = pcall(require, "lib.nvim.fs.open.url.system_opener")
  if ok then
    system_opener = mod
  else
    vim.schedule(function()
      LOG.warn(
        "optional dependency 'lib.nvim' not found — using a minimal "
          .. "built-in system opener fallback."
      )
    end)
  end
end

---Detect operating system.
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

---Minimal per-OS opener, used only when both open.nvim and lib.nvim are absent.
---@param path string File path or URL
---@return boolean success True if opener was invoked
local function minimal_fallback_open(path)
  local os_type = detect_os()
  local cmd
  if os_type == "macos" then
    cmd = { "open", path }
  elseif os_type == "linux" then
    cmd = { "xdg-open", path }
  elseif os_type == "windows" then
    cmd = { "cmd.exe", "/c", "start", "", path:gsub("/", "\\") }
  else
    LOG.error("Unsupported operating system for external opener")
    return false
  end

  local job_id = vim.fn.jobstart(cmd, { detach = true })
  if job_id > 0 then
    LOG.info(string.format("Opening externally: %s", vim.fn.fnamemodify(path, ":t")))
    return true
  end
  LOG.error("Failed to start external opener")
  return false
end

---Open `path` with the OS default handler: lib.nvim's system_opener when
---available, else a minimal built-in per-OS fallback.
---@param path string File path or URL
---@return boolean success True if opener was invoked
local function fallback_open_with_system(path)
  if system_opener then
    local ok = system_opener.open(path)
    if ok then
      LOG.info(string.format("Opening externally: %s", vim.fn.fnamemodify(path, ":t")))
      return true
    end
    LOG.error("Unsupported operating system for external opener")
    return false
  end

  return minimal_fallback_open(path)
end

---Open a file or URL with the system's default application.
---@param path string File path or URL
---@return boolean success True if opener was invoked
function M.open_with_system(path)
  if not path or path == "" then
    return false
  end

  if open_nvim then
    local ok, err = pcall(open_nvim.open, "default", "path=" .. path)
    if ok then
      return true
    end
    LOG.warn("open_nvim.open() failed: " .. tostring(err) .. " — falling back to built-in opener")
  end

  return fallback_open_with_system(path)
end

return M
