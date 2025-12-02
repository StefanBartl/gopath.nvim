---@module 'gopath.external'
---@description Open files with external applications (images, PDFs, URLs, etc.).

local M = {}

---Check if a file should be opened externally based on extension or URL.
---@param path string File path or URL
---@return boolean should_open_externally
function M.should_open_externally(path)
  if not path or path == "" then
    return false
  end

  local detector = require("gopath.external.helpers.detector")
  return detector.is_external_file(path)
end

---Open a file or URL with the system's default application.
---@param path string File path or URL
---@return boolean success True if opener was invoked successfully
function M.open(path)
  if not path or path == "" then
    return false
  end

  local opener = require("gopath.external.helpers.opener")
  return opener.open_with_system(path)
end

return M
