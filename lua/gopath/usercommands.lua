---@module 'gopath.usercommands'
---@brief Automatic user-command registration based on config.
---@description
--- Creates :GopathOpen, :GopathCopy, :GopathResolve, :GopathDebug and the
--- cache-management commands (:GopathCacheBuild, :GopathCacheInfo,
--- :GopathCacheAddRoot). Each command can be individually disabled via the
--- `commands` config table.

local LOG = require("gopath.util.log")

local M = {}

---Register all enabled user commands.
---@param config GopathOptions
function M.setup(config)
  if config.commands == false then return end

  local cmds     = config.commands or {}
  local commands = require("gopath.commands")

  if cmds.resolve ~= false then
    vim.api.nvim_create_user_command("GopathResolve", function()
      commands.debug_under_cursor()
    end, { desc = "Gopath: Show resolution result for symbol under cursor" })
  end

  if cmds.open ~= false then
    vim.api.nvim_create_user_command("GopathOpen", function(opts)
      local mode = opts.args ~= "" and opts.args or "edit"
      if mode == "window_vsplit" or mode == "vsplit" then
        mode = "vsplit"
      elseif mode == "window" or mode == "split" then
        mode = "window"
      end
      commands.resolve_and_open(mode)
    end, {
      nargs    = "?",
      complete = function() return { "edit", "window", "vsplit", "tab" } end,
      desc     = "Gopath: Open target (edit|window|vsplit|tab)",
    })
  end

  if cmds.copy ~= false then
    vim.api.nvim_create_user_command("GopathCopy", function()
      commands.resolve_and_copy()
    end, { desc = "Gopath: Copy path:line:col to clipboard" })
  end

  if cmds.debug ~= false then
    vim.api.nvim_create_user_command("GopathDebug", function()
      commands.debug_under_cursor()
    end, { desc = "Gopath: Debug resolution under cursor" })
  end

  if not (config.truncated and config.truncated.enable) then return end

  vim.api.nvim_create_user_command("GopathCacheBuild", function()
    local cache = require("gopath.truncated.cache")
    LOG.info("Building filesystem cache…")
    cache.build_async(function(success)
      if success then
        LOG.info("Cache build complete")
      else
        LOG.error("Cache build failed")
      end
    end)
  end, { desc = "Gopath: Rebuild filesystem cache" })

  vim.api.nvim_create_user_command("GopathCacheInfo", function()
    local cache = require("gopath.truncated.cache")
    cache.load_from_disk()
    local state = cache._get_state()
    local age   = state.last_built and (os.time() - state.last_built) or nil
    local lines = {
      "=== Gopath Cache Info ===",
      "  Files indexed: " .. #state.paths,
      "  Last built:    "
          .. (state.last_built and os.date("%Y-%m-%d %H:%M:%S", state.last_built) or "never"),
      "  Age:           "
          .. (type(age) == "number"
              and string.format("%d s (%d min)", age, math.floor(age / 60))
              or tostring(age)),
      "  Needs refresh: " .. (cache.needs_refresh() and "yes" or "no"),
      "  Building:      " .. (state.building and "yes" or "no"),
      "=========================",
    }
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Gopath: Show cache information" })

  vim.api.nvim_create_user_command("GopathCacheAddRoot", function(args)
    local dir = args.args
    if not dir or dir == "" then
      LOG.error("Usage: :GopathCacheAddRoot <directory>")
      return
    end
    dir = vim.fn.expand(dir)
    local cache = require("gopath.truncated.cache")
    cache.add_root(dir, true)
  end, {
    nargs    = 1,
    complete = "dir",
    desc     = "Gopath: Add directory to cache roots",
  })
end

return M
