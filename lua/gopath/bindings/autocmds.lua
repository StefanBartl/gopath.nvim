---@module 'gopath.bindings.autocmds'
---@brief Optional autocommands wired from config.
---@description
--- Currently a single opt-in autocmd: rebuild the truncated-path filesystem
--- cache after saving matching files, debounced to at most once per 5
--- minutes. Kept as its own module (rather than inline in
--- `gopath.truncated.cache` setup) so `docs/BINDINGS.md` has one stable
--- anchor file documenting every autocommand gopath registers.

local M = {}

---@param config GopathOptions
function M.setup(config)
  local tcfg = config.truncated
  if not (tcfg and tcfg.enable and tcfg.auto_rebuild_on_save) then
    return
  end

  vim.api.nvim_create_autocmd("BufWritePost", {
    group   = vim.api.nvim_create_augroup("GopathCacheAutoRebuild", { clear = true }),
    pattern = tcfg.watch_patterns or { "*.lua", "*.vim" },
    callback = function()
      -- Debounced: at most one rebuild per 5 minutes.
      vim.defer_fn(function()
        local cache = require("gopath.truncated.cache")
        if cache.needs_refresh(300) then
          cache.build_async(function() end)
        end
      end, 1000)
    end,
  })
end

return M
