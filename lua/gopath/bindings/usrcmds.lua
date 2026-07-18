---@module 'gopath.bindings.usrcmds'
---@brief User command registration: unified :Gopath + individual convenience commands.
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
--- Individual aliases kept for backward compatibility:
---   :GopathOpen [mode]  :GopathCopy  :GopathDebug  :GopathResolve
---   :GopathCacheBuild   :GopathCacheInfo  :GopathCacheAddRoot

local LOG = require("gopath.util.log")

local M = {}

-- ── Subcommand table ─────────────────────────────────────────────────────────

local OPEN_MODES   = { "edit", "split", "vsplit", "tab" }
local PROBE_MODES  = { "edit", "split", "vsplit" }
local CACHE_SUBS   = { "build", "info", "add-root" }
local SUBCOMMANDS  = { "open", "copy", "debug", "probe", "cache", "check" }

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

-- ── Unified :Gopath dispatcher ───────────────────────────────────────────────

---@param config GopathOptions
local function register_gopath_cmd(config, commands)
  local truncated_enabled = config.truncated and config.truncated.enable

  vim.api.nvim_create_user_command("Gopath", function(o)
    local args  = vim.split(o.args or "", "%s+", { trimempty = true })
    local sub   = args[1] or ""
    local arg2  = args[2] or ""
    local arg3  = args[3] or ""

    if sub == "open" then
      commands.resolve_and_open(norm_mode(arg2))

    elseif sub == "copy" then
      commands.resolve_and_copy()

    elseif sub == "debug" then
      commands.debug_under_cursor()

    elseif sub == "check" then
      commands.check_under_cursor()

    elseif sub == "probe" then
      commands.probe_selection({
        open_cmd = arg2 ~= "" and arg2 or "vsplit",
        ask      = true,
      })

    elseif sub == "cache" then
      if not truncated_enabled then
        LOG.warn("truncated cache is disabled in config")
        return
      end
      local cache = require("gopath.truncated.cache")

      if arg2 == "build" then
        LOG.info("Building filesystem cache…")
        cache.build_async(function(ok)
          local msg = "Cache build " .. (ok and "complete" or "failed")
          if ok then LOG.info(msg) else LOG.error(msg) end
        end)

      elseif arg2 == "info" then
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

      elseif arg2 == "add-root" then
        local dir = arg3 ~= "" and arg3 or nil
        if not dir then
          LOG.error("Usage: :Gopath cache add-root <directory>")
          return
        end
        cache.add_root(vim.fn.expand(dir), true)

      else
        LOG.error(":Gopath cache: unknown subcommand '" .. arg2
          .. "'. Use build | info | add-root")
      end

    else
      LOG.error(
        "Unknown subcommand '" .. sub .. "'.\n"
        .. "Usage: :Gopath open|copy|debug|check|probe|cache …\n"
        .. "Run :checkhealth gopath for more info.")
    end
  end, {
    nargs    = "*",
    desc     = "Gopath: unified navigation command",
    complete = function(arglead, cmdline, _)
      local parts = vim.split(cmdline, "%s+", { trimempty = true })
      local n = #parts
      local editing_last = cmdline:sub(-1) ~= " "
      local pos = editing_last and n or (n + 1)

      if pos == 2 then
        local out = {}
        for _, s in ipairs(SUBCOMMANDS) do
          if s:sub(1, #arglead) == arglead then out[#out + 1] = s end
        end
        return out
      end

      local sub_typed = (editing_last and parts[2]) or parts[2] or ""

      if pos == 3 then
        if sub_typed == "open"  then return OPEN_MODES  end
        if sub_typed == "probe" then return PROBE_MODES end
        if sub_typed == "cache" then return CACHE_SUBS  end
      end

      if pos == 4 and sub_typed == "cache" then
        local cache_sub = (editing_last and parts[3]) or parts[3] or ""
        if cache_sub == "add-root" then
          local dirs = vim.fn.getcompletion(arglead, "dir")
          return type(dirs) == "table" and dirs or {}
        end
      end

      return {}
    end,
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
      cache.add_root(vim.fn.expand(dir), true)
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
