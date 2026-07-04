---@module 'gopath.external.helpers.opener'
--- Cross-platform system opener for external files.

local LOG = require("gopath.util.log")

local M = {}

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

---Build opener command for the detected OS.
---@param path string File path or URL
---@param os_type string Operating system type
---@return string[]|nil command Command and arguments, or nil if unsupported
local function build_opener_command(path, os_type)
  if os_type == "macos" then
    return { "open", path }

  elseif os_type == "linux" then
    return { "xdg-open", path }

  elseif os_type == "windows" then
    -- Windows: Normalize path separators
    local normalized_path = path:gsub("/", "\\")

    -- Use PowerShell's Start-Process for better default app handling
    -- This respects file associations properly
    return {
      "powershell.exe",
      "-NoProfile",
      "-Command",
      string.format('Start-Process "%s"', normalized_path),
    }
  end

  return nil
end

---Open a file or URL with the system's default application.
---@param path string File path or URL
---@return boolean success True if opener was invoked
function M.open_with_system(path)
  if not path or path == "" then
    return false
  end

  local os_type = detect_os()
  if os_type == "unknown" then
    LOG.error("Unsupported operating system for external opener")
    return false
  end

  local cmd = build_opener_command(path, os_type)
  if not cmd then
    LOG.error("Failed to build opener command")
    return false
  end

  -- Launch opener in background (detached)
  local job_id = vim.fn.jobstart(cmd, {
    detach = true,
    on_stderr = function(_, data)
      if data and #data > 0 then
        local err_msg = table.concat(data, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
        if err_msg ~= "" then
          vim.schedule(function()
            LOG.warn(string.format("External opener error: %s", err_msg))
          end)
        end
      end
    end,
  })

  if job_id > 0 then
    LOG.info(string.format("Opening externally: %s", vim.fn.fnamemodify(path, ":t")))
    return true
  else
    LOG.error("Failed to start external opener")
    return false
  end
end

return M
