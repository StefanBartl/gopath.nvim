---@module 'gopath.external'
---@description Open files with external applications (images, PDFs, URLs, etc.).

local M = {}

---Check if a file should be opened externally based on extension or URL.
---Respects `config.external.enable` and extends the built-in extension list
---with `config.external.extensions`, if set.
---@param path string File path or URL
---@return boolean should_open_externally
function M.should_open_externally(path)
  if not path or path == "" then return false end

  local cfg = require("gopath.config").get().external
  if cfg and cfg.enable == false then return false end

  local detector = require("gopath.external.helpers.detector")
  return detector.is_external_file(path, cfg and cfg.extensions)
end

---Open a file or URL with the system's default application.
---@param path string File path or URL
---@return boolean success True if opener was invoked successfully
function M.open(path)
  if not path or path == "" then return false end

  local opener = require("gopath.external.helpers.opener")
  return opener.open_with_system(path)
end

---Reveal a file or directory in the system file manager (Explorer/Finder/…)
---instead of opening it — selects a file inside its parent directory,
---navigates into a directory.
---@param path string File or directory path
---@return boolean success True if the reveal command was invoked successfully
function M.reveal(path)
  if not path or path == "" then return false end

  local revealer = require("gopath.external.helpers.revealer")
  return revealer.reveal(path)
end

return M
