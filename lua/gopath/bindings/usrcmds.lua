---@module 'gopath.bindings.usrcmds'
---@brief User command registration: unified :Gopath (built via
--- lib.nvim.usercmd.composer) + individual convenience commands.
---
--- Unified command:
---   :Gopath open [edit|split|vsplit|tab]   resolve & open
---   :Gopath copy                           copy path:line:col to clipboard
---   :Gopath debug                          show resolution info
---   :Gopath probe [edit|split|vsplit]      suffix/visual probe
---   :Gopath cache build                    rebuild fs cache
---   :Gopath cache info                     show cache stats
---   :Gopath cache add-root <dir>           add cache root
---
--- Individual aliases kept alongside as an explicit backward-compat layer
--- (same "keep alongside" call as pickers.nvim's compat flat aliases —
--- these are individually toggleable via config.commands.*, a deliberate
--- design, not accidental duplication):
---   :GopathOpen [mode]  :GopathCopy  :GopathDebug  :GopathResolve
---   :GopathCacheBuild   :GopathCacheInfo  :GopathCacheAddRoot

local composer = require("lib.nvim.usercmd.composer")
local expand_path = require("lib.nvim.cross.fs.expand_path")
local LOG = require("gopath.util.log")

local M = {}

-- ── Subcommand table ─────────────────────────────────────────────────────────

local OPEN_MODES   = { "edit", "split", "vsplit", "tab" }
local PROBE_MODES  = { "edit", "split", "vsplit" }

---Normalize open/probe mode strings to the keys used by commands.lua.
---@param raw string
---@return string
local function norm_mode(raw)
  local m = (raw or "edit"):lower()
  if m == "split" or m == "window" then return "window" end
  if m == "vsplit" then return "vsplit" end
  if m == "tab"   then return "tab"    end
  return "edit"
end

-- ── Cache subcommand bodies (extracted from the old inline handler so the
-- composer routes below can call them directly) ─────────────────────────────

local function cache_build()
  local cache = require("gopath.truncated.cache")
  LOG.info("Building filesystem cache…")
  cache.build_async(function(ok)
    local msg = "Cache build " .. (ok and "complete" or "failed")
    if ok then LOG.info(msg) else LOG.error(msg) end
  end)
end

local function cache_info()
  local cache = require("gopath.truncated.cache")
  cache.load_from_disk()
  local state = cache._get_state()
  local age   = state.last_built and (os.time() - state.last_built) or nil
  print("=== Gopath Cache Info ===")
  print("  Files indexed :", #(state.paths or {}))
  print("  Last built    :", state.last_built
    and os.date("%Y-%m-%d %H:%M:%S", state.last_built) or "never")
  print("  Age           :", age
    and string.format("%d s (%d min)", age, math.floor(age / 60)) or "—")
  print("  Needs refresh :", cache.needs_refresh() and "yes" or "no")
  print("  Building      :", (state.building and "yes" or "no"))
  print("=========================")
end

---@param dir string
local function cache_add_root(dir)
  local cache = require("gopath.truncated.cache")
  cache.add_root(expand_path(dir), true)
end

-- ── Unified :Gopath dispatcher ───────────────────────────────────────────────

---@param config GopathOptions
local function register_gopath_cmd(config, commands)
  local truncated_enabled = config.truncated and config.truncated.enable

  local routes = {
    { path = { "open" },
      args = { { name = "mode", type = "STRING", optional = true, enum = OPEN_MODES } },
      desc = "Resolve & open the path under the cursor",
      run = function(ctx) commands.resolve_and_open(norm_mode(ctx.args.mode)) end },

    { path = { "copy" },
      desc = "Copy path:line:col to clipboard",
      run = function() commands.resolve_and_copy() end },

    { path = { "debug" },
      desc = "Show resolution info for the path under the cursor",
      run = function() commands.debug_under_cursor() end },

    { path = { "check" },
      desc = "Check existence / offer to create the path under the cursor",
      run = function() commands.check_under_cursor() end },

    { path = { "probe" },
      args = { { name = "mode", type = "STRING", optional = true, enum = PROBE_MODES } },
      desc = "Probe path under cursor/selection",
      run = function(ctx)
        commands.probe_selection({ open_cmd = ctx.args.mode or "vsplit", ask = true })
      end },
  }

  if truncated_enabled then
    routes[#routes + 1] = { path = { "cache", "build" },
      desc = "Rebuild the filesystem cache",
      run = cache_build }
    routes[#routes + 1] = { path = { "cache", "info" },
      desc = "Show filesystem cache stats",
      run = cache_info }
    routes[#routes + 1] = { path = { "cache", "add-root" },
      args = { { name = "dir", type = "DIR" } },
      desc = "Add a directory to the filesystem cache roots",
      run = function(ctx) cache_add_root(ctx.args.dir) end }
  end

  composer.verb("Gopath", {
    desc = "Gopath: unified navigation command",
    routes = routes,
  })
end

-- ── Individual convenience commands ─────────────────────────────────────────

---@param config GopathOptions
---@param commands table
local function register_individual(config, commands)
  local cmds = config.commands or {}
  local truncated_enabled = config.truncated and config.truncated.enable

  if cmds.resolve ~= false then
    vim.api.nvim_create_user_command("GopathResolve", function()
      commands.debug_under_cursor()
    end, { desc = "Gopath: show resolution result (alias for :Gopath debug)" })
  end

  if cmds.open ~= false then
    vim.api.nvim_create_user_command("GopathOpen", function(o)
      local mode = o.args ~= "" and o.args or "edit"
      if mode == "window_vsplit" then mode = "vsplit" end
      commands.resolve_and_open(norm_mode(mode))
    end, {
      nargs    = "?",
      complete = function() return OPEN_MODES end,
      desc     = "Gopath: open target (alias for :Gopath open [mode])",
    })
  end

  if cmds.copy ~= false then
    vim.api.nvim_create_user_command("GopathCopy", function()
      commands.resolve_and_copy()
    end, { desc = "Gopath: copy path:line:col (alias for :Gopath copy)" })
  end

  if cmds.debug ~= false then
    vim.api.nvim_create_user_command("GopathDebug", function()
      commands.debug_under_cursor()
    end, { desc = "Gopath: debug resolution (alias for :Gopath debug)" })
  end

  if cmds.check ~= false then
    vim.api.nvim_create_user_command("GopathCheck", function()
      commands.check_under_cursor()
    end, { desc = "Gopath: check existence / offer create (alias for :Gopath check)" })
  end

  -- Probe command (absorbed from pathprobe)
  vim.api.nvim_create_user_command("GopathProbe", function(o)
    local mode = o.bang and "split" or (o.args ~= "" and o.args or "vsplit")
    commands.probe_selection({ open_cmd = mode, ask = true })
  end, {
    nargs    = "?",
    bang     = true,
    complete = function() return PROBE_MODES end,
    desc     = "Gopath: probe path under cursor/selection (! = split)",
  })

  if truncated_enabled then
    vim.api.nvim_create_user_command("GopathCacheBuild", function()
      local cache = require("gopath.truncated.cache")
      LOG.info("Building filesystem cache…")
      cache.build_async(function(ok)
        local msg = "Cache " .. (ok and "built" or "build failed")
        if ok then LOG.info(msg) else LOG.error(msg) end
      end)
    end, { desc = "Gopath: rebuild fs cache (alias for :Gopath cache build)" })

    vim.api.nvim_create_user_command("GopathCacheInfo", function()
      local cache = require("gopath.truncated.cache")
      cache.load_from_disk()
      local state = cache._get_state()
      local age   = state.last_built and (os.time() - state.last_built) or nil
      print("=== Gopath Cache Info ===")
      print("  Files indexed :", #(state.paths or {}))
      print("  Last built    :", state.last_built
        and os.date("%Y-%m-%d %H:%M:%S", state.last_built) or "never")
      print("  Age           :", age
        and string.format("%d s (%d min)", age, math.floor(age / 60)) or "—")
      print("  Needs refresh :", cache.needs_refresh() and "yes" or "no")
      print("=========================")
    end, { desc = "Gopath: show cache info (alias for :Gopath cache info)" })

    vim.api.nvim_create_user_command("GopathCacheAddRoot", function(o)
      local dir = o.args
      if not dir or dir == "" then
        LOG.error("Usage: :GopathCacheAddRoot <dir>")
        return
      end
      local cache = require("gopath.truncated.cache")
      cache.add_root(expand_path(dir), true)
    end, {
      nargs    = 1,
      complete = "dir",
      desc     = "Gopath: add cache root (alias for :Gopath cache add-root <dir>)",
    })
  end
end

-- ── Public setup ─────────────────────────────────────────────────────────────

---@param config GopathOptions
function M.setup(config)
  if config.commands == false then return end
  local commands = require("gopath.commands")
  register_gopath_cmd(config, commands)
  register_individual(config, commands)
end

return M
