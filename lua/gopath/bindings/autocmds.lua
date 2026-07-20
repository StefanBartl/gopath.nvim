---@module 'gopath.bindings.autocmds'
---@brief Autocommands wired from config.
---@description
--- Two autocmds, kept here (rather than inline next to the code they serve) so
--- `docs/BINDINGS.md` has one stable anchor file documenting every autocommand
--- gopath registers:
---
---   1. Always on: drop the path-lookup directory caches after a write, since
---      a write can add a file those caches would otherwise not see.
---   2. Opt-in: rebuild the truncated-path filesystem cache after saving
---      matching files, debounced to at most once per 5 minutes.

local autocmd = require("lib.nvim.autocmd")

local M = {}

---@param config GopathOptions
function M.setup(config)
  -- `gopath.util.path` caches directory listings to keep gF off the hot
  -- filesystem path. Writing a buffer is the common way a new file appears
  -- mid-session, so treat it as a cache-invalidation signal. Creation through
  -- gopath's own create-on-missing invalidates directly in `gopath.create`.
  autocmd.create("BufWritePost", function()
    require("gopath.util.path").invalidate_caches()
  end, {
    group = autocmd.group("GopathPathCacheInvalidate", true),
  })

  local tcfg = config.truncated
  if not (tcfg and tcfg.enable and tcfg.auto_rebuild_on_save) then
    return
  end

  autocmd.create("BufWritePost", function()
    -- Debounced: at most one rebuild per 5 minutes.
    vim.defer_fn(function()
      local cache = require("gopath.truncated.cache")
      if cache.needs_refresh(300) then
        cache.build_async(function() end)
      end
    end, 1000)
  end, {
    group   = autocmd.group("GopathCacheAutoRebuild", true),
    pattern = tcfg.watch_patterns or { "*.lua", "*.vim" },
  })
end

return M
