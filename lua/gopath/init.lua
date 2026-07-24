---@module 'gopath'
---@brief Public setup and API surface for gopath.nvim.
---@description
--- Main entry point called by package managers (lazy.nvim, packer, …).
--- Delegates to focused helpers so that `setup()` itself stays thin:
---   • Config merge  → gopath.config
---   • Bindings      → gopath.bindings (keymaps, usrcmds, autocmds, which-key)
---   • Cache init    → private `_setup_cache()`

local C = require("gopath.config")
local R = require("gopath.resolve")

local M = {}

---Initialise the truncated-path cache subsystem.
---Separated from `setup()` to keep each function single-purpose.
---@private
---@param config GopathOptions
local function _setup_cache(config)
  local tcfg = config.truncated
  if not (tcfg and tcfg.enable) then return end

  local cache = require("gopath.truncated.cache")
  local LOG = require("gopath.util.log")

  -- Configure scan roots / depth / exclusions. Without this the cache would
  -- index nothing (scan_roots stays empty) and every resolve would fall back
  -- to the slow live search.
  cache.setup({
    roots = tcfg.cache_roots,
    max_depth = tcfg.max_depth,
    excluded_dirs = tcfg.excluded_dirs,
  })

  -- Load persisted cache immediately so the first resolve can use it.
  pcall(function()
    cache.load_from_disk()
  end)

  -- Periodic background refresh.
  if tcfg.use_cache then cache.start_periodic_refresh(tcfg.cache_refresh_interval or 600) end

  -- Initial async build when the cache is missing or stale.
  if cache.needs_refresh(tcfg.max_cache_age or 3600) then
    vim.defer_fn(function()
      cache.build_async(function(success)
        if success then
          LOG.debug("Filesystem cache built successfully")
        else
          LOG.error("Filesystem cache build failed")
        end
      end)
    end, 2000)
  end
end

---Set up gopath.nvim with user options and register keymaps / commands.
---@param opts GopathOptions|nil
function M.setup(opts)
  C.setup(opts)
  local config = C.get()

  require("gopath.bindings").setup(config)
  _setup_cache(config)
end

---Resolve the entity under the cursor without opening anything.
---Useful for custom integrations that need the raw GopathResult.
---@param opts GopathResolveOpts|nil
---@return GopathResult|nil, string|nil
function M.resolve(opts)
  return R.resolve_at_cursor(opts)
end

---Direct access to command implementations for custom keymaps.
---Example: `require("gopath").commands.resolve_and_open("vsplit")`
M.commands = require("gopath.commands")

return M
