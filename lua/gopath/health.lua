---@module 'gopath.health'
---@brief checkhealth provider for gopath.nvim.
---@description
--- Accessed via :checkhealth gopath. Reports the plugin's runtime state:
--- active config, Treesitter parser availability, optional external tools
--- (fd, rg, find) and the truncated-path cache status.

local M = {}

---@private
local function check_config()
  local ok, cfg = pcall(function() return require("gopath.config").get() end)
  if not ok then
    vim.health.error("Could not read gopath config — was require('gopath').setup() called?")
    return
  end
  vim.health.ok("Config loaded  (mode: " .. tostring(cfg.mode) .. ")")
  if cfg.dev_mode then
    vim.health.info("dev_mode is ON — debug notifications are active")
  end
end

---@private
local function check_treesitter()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  if not ok then
    vim.health.warn(
      "nvim-treesitter not found",
      { "Install nvim-treesitter for semantic Lua resolution (LSP still works without it)" }
    )
    return
  end
  if parsers.has_parser("lua") then
    vim.health.ok("Treesitter Lua parser installed")
  else
    vim.health.warn("Treesitter Lua parser missing", { "Run :TSInstall lua" })
  end
end

---@private
local function check_external_tools()
  for _, tool in ipairs({ "fd", "rg", "find" }) do
    if vim.fn.executable(tool) == 1 then
      vim.health.ok(tool .. " found (used for live truncated-path search)")
    else
      vim.health.info(tool .. " not found  (optional — only needed for live truncated-path fallback)")
    end
  end
end

---@private
local function check_cache()
  local ok, cache = pcall(require, "gopath.truncated.cache")
  if not ok then
    vim.health.info("Truncated cache module not loaded")
    return
  end
  local ok2, state = pcall(function() return cache._get_state() end)
  if not ok2 then
    vim.health.warn("Could not read cache state")
    return
  end
  local count = #(state.paths or {})
  if count > 0 then
    local age = state.last_built and (os.time() - state.last_built) or nil
    local age_str = age and string.format("%d min ago", math.floor(age / 60)) or "unknown"
    vim.health.ok(string.format("Cache: %d files indexed, built %s", count, age_str))
    if cache.needs_refresh() then
      vim.health.warn("Cache may be stale", { "Run :GopathCacheBuild to refresh" })
    end
  else
    vim.health.warn(
      "Cache is empty",
      { "Run :GopathCacheBuild to index your filesystem for truncated-path resolution" }
    )
  end
end

function M.check()
  vim.health.start("gopath.nvim")
  check_config()
  check_treesitter()
  check_external_tools()
  check_cache()
end

return M
