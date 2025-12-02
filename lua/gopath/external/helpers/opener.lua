---@module 'gopath.external.helpers.opener'
---@description Cross-platform system opener for external files.

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
    -- Windows: use 'start' command via cmd.exe
    -- The empty string "" after start is the window title (prevents issues with paths containing spaces)
    return { "cmd.exe", "/c", "start", "", path }
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
    vim.notify(
      "[gopath.external] Unsupported operating system for external opener",
      vim.log.levels.ERROR
    )
    return false
  end

  local cmd = build_opener_command(path, os_type)
  if not cmd then
    vim.notify(
      "[gopath.external] Failed to build opener command",
      vim.log.levels.ERROR
    )
    return false
  end

  -- Launch opener in background (detached)
  local ok = pcall(vim.fn.jobstart, cmd, {
    detach = true,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        vim.notify(
          string.format("[gopath.external] Opener exited with code %d", exit_code),
          vim.log.levels.WARN
        )
      end
    end,
  })

  if ok then
    vim.notify(
      string.format("[gopath] Opened externally: %s", vim.fn.fnamemodify(path, ":t")),
      vim.log.levels.INFO
    )
  else
    vim.notify(
      "[gopath.external] Failed to start external opener",
      vim.log.levels.ERROR
    )
  end

  return ok
end

return M
