---@module 'gopath'
---@brief Public setup and API surface for gopath.nvim.
---Handles plugin initialization, cache setup, and component registration.

local C = require("gopath.config")
local R = require("gopath.resolve")

local M = {}

---Setup gopath with user options and register keymaps/commands
---This is the main entry point called by package managers (lazy.nvim, packer, etc.)
---@param opts GopathOptions|nil User configuration
function M.setup(opts)
  -- Step 1: Merge user config with defaults
  C.setup(opts)
  local config = C.get()

  -- Step 2: Register keymaps (gP, g|, g\, g}, etc.)
  local keymaps = require("gopath.keymaps")
  keymaps.setup(config)

  -- Step 3: Register user commands (:GopathOpen, :GopathCopy, etc.)
  local usercommands = require("gopath.usercommands")
  usercommands.setup(config)

  -- Step 4: Initialize truncated path resolution (if enabled)
  if config.truncated and config.truncated.enable then
    local cache = require("gopath.truncated.cache")

    -- 4.1: Load existing cache from disk (non-blocking)
    -- This happens immediately to have data available for first resolve
    pcall(function()
      cache.load_from_disk()
    end)

    -- 4.2: Start periodic cache refresh in background (if enabled)
    -- This runs asynchronously and updates cache every N minutes
    if config.truncated.use_cache then
      local interval = config.truncated.cache_refresh_interval or 600
      cache.start_periodic_refresh(interval)
    end

    -- 4.3: Trigger initial cache build if needed (deferred to avoid startup delay)
    -- We check if cache is stale or missing, then rebuild asynchronously
    local max_age = config.truncated.max_cache_age or 3600
    if cache.needs_refresh(max_age) then
      -- Delay by 2 seconds to not impact Neovim startup time
      vim.defer_fn(function()
        cache.build_async(function(success)
          if success then
            vim.notify(
              "[gopath] Filesystem cache built successfully",
              vim.log.levels.INFO
            )
          end
        end)
      end, 2000)
    end

    -- 4.4: Setup cache autocommands (if configured)
    -- Allow triggering cache rebuild on specific events
    if config.truncated.auto_rebuild_on_save then
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("GopathCacheAutoRebuild", { clear = true }),
        pattern = config.truncated.watch_patterns or { "*.lua", "*.vim" },
        callback = function()
          -- Debounced rebuild (don't rebuild on every save)
          vim.defer_fn(function()
            if cache.needs_refresh(300) then -- 5 minute minimum between rebuilds
              cache.build_async(function() end)
            end
          end, 1000)
        end,
      })
    end
  end
end

---Core resolve entry (data only, does not open files)
---This is used internally and can be called directly for custom integrations
---@param opts GopathResolveOpts|nil Resolution options
---@return GopathResult|nil result Resolution result or nil if no match
---@return string|nil error Error message if resolution failed
function M.resolve(opts)
  return R.resolve_at_cursor(opts)
end

---Expose commands API for manual usage or custom keymaps
---Example: require("gopath").commands.resolve_and_open("vsplit")
M.commands = require("gopath.commands")

return M
